//
//  SessionControllerTests.swift
//  BlinkBreakCoreTests
//
//  State-machine tests for SessionController. Uses mocks for all collaborators and
//  a mutable fake clock so tests run instantly with no real sleeping.
//
//  Written in Swift Testing (the `import Testing` framework), not legacy XCTest.
//

import Testing
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — state machine")
struct SessionControllerTests {

    // MARK: - Fixtures

    /// A fresh, fully-wired controller with mocks for each collaborator and a mutable
    /// `fakeNow` box so tests can advance virtual time.
    @MainActor
    final class Fixture {
        let scheduler = MockNotificationScheduler()
        let connectivity = MockWatchConnectivity()
        let persistence = InMemoryPersistence()
        let alarm = MockSessionAlarm()
        let nowBox = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
        let controller: SessionController

        init() {
            let box = nowBox
            self.controller = SessionController(
                scheduler: scheduler,
                connectivity: connectivity,
                persistence: persistence,
                alarm: alarm,
                clock: { box.value }
            )
        }

        func advance(by seconds: TimeInterval) {
            nowBox.value = nowBox.value.addingTimeInterval(seconds)
        }
    }

    /// Thread-safe mutable box around a `Date` so the fixture's `clock` closure can
    /// capture it by reference and read the latest value on each call.
    final class NowBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Date
        init(value: Date) { self.storage = value }
        var value: Date {
            get {
                lock.lock(); defer { lock.unlock() }
                return storage
            }
            set {
                lock.lock(); defer { lock.unlock() }
                storage = newValue
            }
        }
    }

    // MARK: - start()

    @Test("start() transitions idle → running with clock time as cycleStartedAt")
    func startTransitionsToRunning() {
        let f = Fixture()
        #expect(f.controller.state == .idle)

        f.controller.start()

        guard case .running(let startedAt) = f.controller.state else {
            Issue.record("expected running, got \(f.controller.state)")
            return
        }
        #expect(startedAt == f.nowBox.value)
    }

    @Test("start() schedules a single break notification")
    func startSchedulesSingleBreakNotification() {
        let f = Fixture()
        f.controller.start()

        #expect(f.scheduler.scheduledNotifications.count == 1)
        let n = f.scheduler.scheduledNotifications[0]
        #expect(n.isTimeSensitive)
        #expect(n.categoryIdentifier == BlinkBreakConstants.breakCategoryId)
        #expect(n.soundName == BlinkBreakConstants.breakSoundFileName)
        let cycleId = f.persistence.load().currentCycleId!
        #expect(n.identifier == BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString)
        #expect(n.threadIdentifier == cycleId.uuidString)
    }

    @Test("start() persists an active record")
    func startPersistsRecord() {
        let f = Fixture()
        f.controller.start()

        let record = f.persistence.load()
        #expect(record.sessionActive)
        #expect(record.currentCycleId != nil)
        #expect(record.cycleStartedAt == f.nowBox.value)
        #expect(record.lookAwayStartedAt == nil)
    }

    @Test("start() broadcasts a snapshot to the Watch")
    func startBroadcastsSnapshot() {
        let f = Fixture()
        f.controller.start()

        #expect(f.connectivity.broadcasts.count == 1)
        #expect(f.connectivity.lastBroadcast?.sessionActive == true)
    }

    @Test("start() wipes stale notifications from a previous crashed session")
    func startCancelsStaleNotifications() {
        let f = Fixture()
        f.scheduler.schedule(ScheduledNotification(
            identifier: "stale.old",
            title: "x", body: "x",
            fireDate: f.nowBox.value.addingTimeInterval(60),
            isTimeSensitive: false,
            threadIdentifier: "stale",
            categoryIdentifier: nil
        ))

        f.controller.start()

        #expect(f.scheduler.cancelAllCount == 1)
        #expect(f.scheduler.scheduledNotifications.count == 1)
        #expect(!f.scheduler.scheduledNotifications.contains { $0.identifier == "stale.old" })
    }

    // MARK: - stop()

    @Test("stop() transitions any state → idle")
    func stopTransitionsToIdle() {
        let f = Fixture()
        f.controller.start()

        f.controller.stop()

        #expect(f.controller.state == .idle)
    }

    @Test("stop() cancels all notifications")
    func stopCancelsEverything() {
        let f = Fixture()
        f.controller.start()
        let initial = f.scheduler.cancelAllCount

        f.controller.stop()

        #expect(f.scheduler.cancelAllCount == initial + 1)
    }

    @Test("stop() persists idle record")
    func stopPersistsIdle() {
        let f = Fixture()
        f.controller.start()

        f.controller.stop()

        let record = f.persistence.load()
        #expect(record.sessionActive == false)
        #expect(record.currentCycleId == nil)
        #expect(record.lastUpdatedAt != nil)
    }

    @Test("stop() broadcasts an inactive snapshot")
    func stopBroadcastsIdle() {
        let f = Fixture()
        f.controller.start()
        f.connectivity.reset()

        f.controller.stop()

        #expect(f.connectivity.broadcasts.count == 1)
        #expect(f.connectivity.lastBroadcast?.sessionActive == false)
    }

    // MARK: - handleStartBreakAction()

    @Test("handleStartBreakAction with current cycleId transitions running → lookAway")
    func ackTransitionsToLookAway() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!
        f.advance(by: BlinkBreakConstants.breakInterval + 1)

        f.controller.handleStartBreakAction(cycleId: cycleId)

        guard case .lookAway(let startedAt) = f.controller.state else {
            Issue.record("expected lookAway, got \(f.controller.state)")
            return
        }
        #expect(startedAt == f.nowBox.value)
    }

    @Test("handleStartBreakAction with stale cycleId is a no-op")
    func ackWithStaleCycleIdIgnored() {
        let f = Fixture()
        f.controller.start()
        let stateBefore = f.controller.state

        f.controller.handleStartBreakAction(cycleId: UUID())

        #expect(f.controller.state == stateBefore)
    }

    @Test("handleStartBreakAction while idle is a no-op")
    func ackWhileIdleIgnored() {
        let f = Fixture()
        f.controller.handleStartBreakAction(cycleId: UUID())

        #expect(f.controller.state == .idle)
        #expect(f.scheduler.scheduledNotifications.isEmpty)
    }

    @Test("handleStartBreakAction cancels the old cascade")
    func ackCancelsOldCascade() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!
        f.advance(by: BlinkBreakConstants.breakInterval)

        f.controller.handleStartBreakAction(cycleId: cycleId)

        let cancelled = f.scheduler.lastCancelledIdentifiers ?? []
        #expect(cancelled.contains(BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString))
    }

    @Test("handleStartBreakAction schedules a done notification + next break notification")
    func ackSchedulesDoneAndNextBreak() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!
        f.advance(by: BlinkBreakConstants.breakInterval)

        f.controller.handleStartBreakAction(cycleId: cycleId)

        // After ack: old break cancelled, done scheduled (1) + new break scheduled (1) = 2 remaining.
        #expect(f.scheduler.scheduledNotifications.count == 2)

        let ids = f.scheduler.scheduledNotifications.map(\.identifier)
        #expect(ids.contains(BlinkBreakConstants.doneIdPrefix + cycleId.uuidString))

        let newCycleId = f.persistence.load().currentCycleId!
        #expect(newCycleId != cycleId)
        #expect(ids.contains(BlinkBreakConstants.breakPrimaryIdPrefix + newCycleId.uuidString))
    }

    @Test("handleStartBreakAction advances persistence to a new cycle")
    func ackUpdatesPersistenceWithNewCycle() {
        let f = Fixture()
        f.controller.start()
        let oldCycleId = f.persistence.load().currentCycleId!
        f.advance(by: BlinkBreakConstants.breakInterval)

        f.controller.handleStartBreakAction(cycleId: oldCycleId)

        let record = f.persistence.load()
        #expect(record.sessionActive)
        #expect(record.currentCycleId != oldCycleId)
        #expect(record.lookAwayStartedAt == f.nowBox.value)
        #expect(record.cycleStartedAt == f.nowBox.value.addingTimeInterval(BlinkBreakConstants.lookAwayDuration))
    }

    // MARK: - Full session loop

    // MARK: - Alarm wiring

    @Test("start() arms the alarm with the cycleId and correct fireDate")
    func startArmsAlarm() {
        let f = Fixture()
        f.controller.start()

        let armed = f.alarm.lastArmed
        #expect(armed != nil)
        #expect(armed?.cycleId == f.persistence.load().currentCycleId)
        #expect(armed?.fireDate == f.nowBox.value.addingTimeInterval(BlinkBreakConstants.breakInterval))
    }

    @Test("stop() disarms the current cycle's alarm")
    func stopDisarmsAlarm() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!

        f.controller.stop()

        #expect(f.alarm.lastDisarmedCycleId == cycleId)
    }

    @Test("handleStartBreakAction disarms the current cycle and arms the next")
    func ackDisarmsAndReArms() {
        let f = Fixture()
        f.controller.start()
        let firstCycleId = f.persistence.load().currentCycleId!
        f.advance(by: BlinkBreakConstants.breakInterval)

        f.controller.handleStartBreakAction(cycleId: firstCycleId)

        #expect(f.alarm.disarmedCycleIds.contains(firstCycleId))
        #expect(f.alarm.armedCalls.count == 2)  // start + re-arm
        let nextArmed = f.alarm.lastArmed!
        #expect(nextArmed.cycleId == f.persistence.load().currentCycleId)
    }

    // MARK: - handleRemoteSnapshot

    @Test("handleRemoteSnapshot with a remote ack cancels delivered notifications for the acked cycle")
    func remoteAckCancelsDelivered() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!
        f.advance(by: BlinkBreakConstants.breakInterval)

        let remoteSnapshot = SessionSnapshot(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: f.nowBox.value.addingTimeInterval(BlinkBreakConstants.lookAwayDuration),
            lookAwayStartedAt: f.nowBox.value,
            updatedAt: f.nowBox.value
        )
        f.controller.handleRemoteSnapshot(remoteSnapshot)

        let cancelled = f.scheduler.lastCancelledIdentifiers ?? []
        #expect(cancelled.contains(BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString))
    }

    @Test("handleRemoteSnapshot with a remote ack disarms the local alarm for the acked cycle")
    func remoteAckDisarmsAlarm() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!
        f.alarm.reset()
        f.advance(by: BlinkBreakConstants.breakInterval)

        let remoteSnapshot = SessionSnapshot(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: f.nowBox.value.addingTimeInterval(BlinkBreakConstants.lookAwayDuration),
            lookAwayStartedAt: f.nowBox.value,
            updatedAt: f.nowBox.value
        )
        f.controller.handleRemoteSnapshot(remoteSnapshot)

        #expect(f.alarm.disarmedCycleIds.contains(cycleId))
    }

    @Test("handleRemoteSnapshot is idempotent when called twice with the same snapshot")
    func remoteSnapshotDoubleDelivery() {
        let f = Fixture()
        f.controller.start()
        f.advance(by: BlinkBreakConstants.breakInterval)

        let snapshot = SessionSnapshot(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: f.nowBox.value.addingTimeInterval(BlinkBreakConstants.lookAwayDuration),
            lookAwayStartedAt: f.nowBox.value,
            updatedAt: f.nowBox.value
        )
        f.controller.handleRemoteSnapshot(snapshot)
        let recordAfterFirst = f.persistence.load()
        f.controller.handleRemoteSnapshot(snapshot)
        let recordAfterSecond = f.persistence.load()

        #expect(recordAfterFirst == recordAfterSecond)
    }

    @Test("handleRemoteSnapshot ignores snapshots older than the local lastUpdatedAt")
    func remoteSnapshotStaleIgnored() {
        let f = Fixture()
        f.controller.start()
        let cycleIdBefore = f.persistence.load().currentCycleId

        var rec = f.persistence.load()
        rec.lastUpdatedAt = f.nowBox.value.addingTimeInterval(100)
        f.persistence.save(rec)

        let stale = SessionSnapshot(
            sessionActive: false,
            currentCycleId: nil,
            cycleStartedAt: nil,
            lookAwayStartedAt: nil,
            updatedAt: f.nowBox.value.addingTimeInterval(50)
        )
        f.controller.handleRemoteSnapshot(stale)

        #expect(f.persistence.load().currentCycleId == cycleIdBefore)
    }

    @Test("full loop: start → wait → ack → wait → reconcile → stop")
    func fullLoop() async {
        let f = Fixture()

        // Start
        f.controller.start()
        let firstCycleId = f.persistence.load().currentCycleId!
        #expect(f.controller.state.description == "running")

        // Break time arrives
        f.advance(by: BlinkBreakConstants.breakInterval)

        // User acknowledges
        f.controller.handleStartBreakAction(cycleId: firstCycleId)
        #expect(f.controller.state.description == "lookAway")

        // Look-away elapses
        f.advance(by: BlinkBreakConstants.lookAwayDuration + 1)

        // Reconcile picks up that we've rolled into the next running cycle
        await f.controller.reconcileOnLaunch()
        #expect(f.controller.state.description == "running")

        let newRecord = f.persistence.load()
        #expect(newRecord.currentCycleId != firstCycleId)

        // User stops
        f.controller.stop()
        #expect(f.controller.state == .idle)
        #expect(f.persistence.load().sessionActive == false)
    }
}
