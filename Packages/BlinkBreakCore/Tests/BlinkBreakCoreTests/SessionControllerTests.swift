//
//  SessionControllerTests.swift
//  BlinkBreakCoreTests
//
//  State-machine tests for SessionController. Uses an AlarmKit mock + virtual time.
//
//  AlarmKit is event-driven, so most state transitions are driven by simulating
//  alarm events (`fire`, `dismiss`) rather than by advancing the clock and calling
//  reconcile. Where the production code spawns a Task to schedule an alarm, tests
//  await `Task.yield()` (or a small `Task.sleep`) to let the spawned task complete.
//
//  Written in Swift Testing (the `import Testing` framework), not legacy XCTest.
//

import Testing
import Foundation
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — state machine")
struct SessionControllerTests {

    // MARK: - Fixtures

    @MainActor
    final class Fixture {
        let alarmScheduler = MockAlarmScheduler()
        let persistence = InMemoryPersistence()
        let nowBox = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
        let controller: SessionController

        init() {
            let box = nowBox
            self.controller = SessionController(
                alarmScheduler: alarmScheduler,
                persistence: persistence,
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

    /// SessionController spawns Tasks for alarm-scheduling work. Tests need to let
    /// those tasks complete before asserting. `settle()` yields a few times — that's
    /// enough for any awaited sequence in the controller to flush given everything
    /// runs on the main actor.
    private func settle() async {
        for _ in 0..<3 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    // MARK: - start()

    @Test("start() transitions idle → running with clock time as cycleStartedAt")
    func startTransitionsToRunning() async {
        let f = Fixture()
        #expect(f.controller.state == .idle)

        f.controller.start()
        await settle()

        guard case .running(let startedAt) = f.controller.state else {
            Issue.record("expected running, got \(f.controller.state)")
            return
        }
        #expect(startedAt == f.nowBox.value)
    }

    @Test("start() schedules a single break-due alarm")
    func startSchedulesBreakAlarm() async {
        let f = Fixture()
        f.controller.start()
        await settle()

        #expect(f.alarmScheduler.scheduled.count == 1)
        let call = f.alarmScheduler.scheduled[0]
        #expect(call.kind == .breakDue)
        #expect(call.duration == BlinkBreakConstants.breakInterval)
    }

    @Test("start() persists an active record with currentAlarmId set")
    func startPersistsRecord() async {
        let f = Fixture()
        f.controller.start()
        await settle()

        let record = f.persistence.load()
        #expect(record.sessionActive)
        #expect(record.currentCycleId != nil)
        #expect(record.cycleStartedAt == f.nowBox.value)
        #expect(record.breakActiveStartedAt == nil)
        #expect(record.currentAlarmId != nil)
        #expect(record.currentAlarmId == f.alarmScheduler.scheduled.last?.alarmId)
    }

    @Test("start() cancels any previously-scheduled alarms first")
    func startCancelsExistingAlarms() async {
        let f = Fixture()

        f.controller.start()
        await settle()
        let firstCancelAllCount = f.alarmScheduler.cancelAllCount

        f.controller.start()
        await settle()

        #expect(f.alarmScheduler.cancelAllCount == firstCancelAllCount + 1)
    }

    // MARK: - stop()

    @Test("stop() transitions any state → idle")
    func stopTransitionsToIdle() async {
        let f = Fixture()
        f.controller.start()
        await settle()

        f.controller.stop()
        await settle()

        #expect(f.controller.state == .idle)
    }

    @Test("stop() cancels all alarms")
    func stopCancelsEverything() async {
        let f = Fixture()
        f.controller.start()
        await settle()
        let initial = f.alarmScheduler.cancelAllCount

        f.controller.stop()
        await settle()

        #expect(f.alarmScheduler.cancelAllCount == initial + 1)
    }

    @Test("stop() persists idle record")
    func stopPersistsIdle() async {
        let f = Fixture()
        f.controller.start()
        await settle()

        f.controller.stop()
        await settle()

        let record = f.persistence.load()
        #expect(record.sessionActive == false)
        #expect(record.currentCycleId == nil)
        #expect(record.lastUpdatedAt != nil)
    }

    // MARK: - Event-driven transitions

    @Test("break-due alarm firing transitions running → breakPending")
    func breakAlarmFireGoesToBreakPending() async {
        let f = Fixture()
        f.controller.start()
        await settle()
        let alarmId = f.alarmScheduler.scheduled.last!.alarmId

        f.alarmScheduler.simulateFire(alarmId: alarmId, kind: .breakDue)
        await settle()

        guard case .breakPending = f.controller.state else {
            Issue.record("expected breakPending, got \(f.controller.state)")
            return
        }
    }

    @Test("break-due alarm dismissal transitions to breakActive + schedules look-away")
    func breakDismissSchedulesLookAway() async {
        let f = Fixture()
        f.controller.start()
        await settle()
        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId

        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        f.advance(by: 5)
        f.alarmScheduler.simulateDismiss(alarmId: breakAlarmId, kind: .breakDue)
        await settle()

        // Should have scheduled a look-away alarm
        let lookAwayCalls = f.alarmScheduler.scheduled.filter { $0.kind == .lookAwayDone }
        #expect(lookAwayCalls.count == 1)
        #expect(lookAwayCalls[0].duration == BlinkBreakConstants.lookAwayDuration)

        // State should be breakActive
        guard case .breakActive(let startedAt) = f.controller.state else {
            Issue.record("expected breakActive, got \(f.controller.state)")
            return
        }
        #expect(startedAt == f.nowBox.value)

        // Persistence should have advanced the alarm ID + breakActiveStartedAt
        let record = f.persistence.load()
        #expect(record.breakActiveStartedAt == f.nowBox.value)
        #expect(record.currentAlarmId == lookAwayCalls[0].alarmId)
    }

    @Test("look-away alarm dismissal rolls to next cycle")
    func lookAwayDismissRollsCycle() async {
        let f = Fixture()
        f.controller.start()
        await settle()
        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        f.alarmScheduler.simulateDismiss(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        let lookAwayAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        let firstCycleId = f.persistence.load().currentCycleId!

        f.advance(by: BlinkBreakConstants.lookAwayDuration)
        f.alarmScheduler.simulateFire(alarmId: lookAwayAlarmId, kind: .lookAwayDone)
        f.alarmScheduler.simulateDismiss(alarmId: lookAwayAlarmId, kind: .lookAwayDone)
        await settle()

        // State should be running with new cycle
        guard case .running = f.controller.state else {
            Issue.record("expected running, got \(f.controller.state)")
            return
        }
        let record = f.persistence.load()
        #expect(record.currentCycleId != firstCycleId)
        #expect(record.breakActiveStartedAt == nil)

        // A new break alarm should be scheduled
        let breakCalls = f.alarmScheduler.scheduled.filter { $0.kind == .breakDue }
        #expect(breakCalls.count == 2)  // initial + next-cycle
    }

    @Test("dismissed event for stale alarmId is ignored")
    func staleDismissIgnored() async {
        let f = Fixture()
        f.controller.start()
        await settle()
        let stateBefore = f.controller.state

        f.alarmScheduler.simulateDismiss(alarmId: UUID(), kind: .breakDue)
        await settle()

        #expect(f.controller.state == stateBefore)
    }

    // MARK: - acknowledgeCurrentBreak()

    @Test("acknowledgeCurrentBreak triggers the same flow as alarm dismissal")
    func acknowledgeFromInsideAppFlow() async {
        let f = Fixture()
        f.controller.start()
        await settle()
        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()

        f.controller.acknowledgeCurrentBreak()
        await settle()

        // Should have cancelled the break alarm + scheduled look-away
        #expect(f.alarmScheduler.cancelledIds.contains(breakAlarmId))
        let lookAwayCalls = f.alarmScheduler.scheduled.filter { $0.kind == .lookAwayDone }
        #expect(lookAwayCalls.count == 1)
        guard case .breakActive = f.controller.state else {
            Issue.record("expected breakActive, got \(f.controller.state)")
            return
        }
    }

    @Test("acknowledgeCurrentBreak with no current alarm is a no-op")
    func acknowledgeWhileIdleIgnored() async {
        let f = Fixture()
        f.controller.acknowledgeCurrentBreak()
        await settle()

        #expect(f.controller.state == .idle)
        #expect(f.alarmScheduler.scheduled.isEmpty)
    }

    // MARK: - Full loop

    @Test("full loop: start → break fires → ack → look-away → roll cycle")
    func fullLoop() async {
        let f = Fixture()

        f.controller.start()
        await settle()
        #expect(f.controller.state.description == "running")
        let firstCycleId = f.persistence.load().currentCycleId!

        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        #expect(f.controller.state.description == "breakPending")

        f.alarmScheduler.simulateDismiss(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        #expect(f.controller.state.description == "breakActive")

        let lookAwayAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.advance(by: BlinkBreakConstants.lookAwayDuration)
        f.alarmScheduler.simulateFire(alarmId: lookAwayAlarmId, kind: .lookAwayDone)
        f.alarmScheduler.simulateDismiss(alarmId: lookAwayAlarmId, kind: .lookAwayDone)
        await settle()

        #expect(f.controller.state.description == "running")
        #expect(f.persistence.load().currentCycleId != firstCycleId)

        f.controller.stop()
        await settle()
        #expect(f.controller.state == .idle)
        #expect(f.persistence.load().sessionActive == false)
    }
}
