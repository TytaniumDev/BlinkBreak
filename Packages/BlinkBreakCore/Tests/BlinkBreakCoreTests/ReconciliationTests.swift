//
//  ReconciliationTests.swift
//  BlinkBreakCoreTests
//
//  Targeted tests for `SessionController.reconcileOnLaunch()` — the method that
//  rebuilds UI state from persisted record + pending notifications + clock.
//

import Testing
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — reconciliation")
struct ReconciliationTests {

    @MainActor
    final class Fixture {
        let scheduler = MockNotificationScheduler()
        let persistence = InMemoryPersistence()
        let alarm = MockSessionAlarm()
        let nowBox = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
        let controller: SessionController

        init() {
            let box = nowBox
            self.controller = SessionController(
                scheduler: scheduler,
                connectivity: MockWatchConnectivity(),
                persistence: persistence,
                alarm: alarm,
                clock: { box.value }
            )
        }

        func advance(by seconds: TimeInterval) {
            nowBox.value = nowBox.value.addingTimeInterval(seconds)
        }
    }

    final class NowBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Date
        init(value: Date) { self.storage = value }
        var value: Date {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); defer { lock.unlock() }; storage = newValue }
        }
    }

    @Test("reconcile with no persisted session → idle")
    func noSession() async {
        let f = Fixture()
        f.persistence.save(.idle)

        await f.controller.reconcileOnLaunch()

        #expect(f.controller.state == .idle)
    }

    @Test("reconcile within running window → running")
    func withinRunning() async {
        let f = Fixture()
        let cycleId = UUID()
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: f.nowBox.value,
            breakActiveStartedAt: nil
        ))
        f.scheduler.stubPendingIdentifiers = CascadeBuilder.identifiers(for: cycleId)

        await f.controller.reconcileOnLaunch()

        guard case .running(let startedAt) = f.controller.state else {
            Issue.record("expected running, got \(f.controller.state)")
            return
        }
        #expect(startedAt == f.nowBox.value)
    }

    @Test("reconcile past break time with pending cascade → breakPending")
    func pastBreakWithPendingCascade() async {
        let f = Fixture()
        let cycleId = UUID()
        let started = f.nowBox.value
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: started,
            breakActiveStartedAt: nil
        ))
        f.scheduler.stubPendingIdentifiers = CascadeBuilder.identifiers(for: cycleId)

        f.advance(by: BlinkBreakConstants.breakInterval + 10)

        await f.controller.reconcileOnLaunch()

        guard case .breakPending(let startedAt) = f.controller.state else {
            Issue.record("expected breakPending, got \(f.controller.state)")
            return
        }
        #expect(startedAt == started)
    }

    @Test("reconcile past break time with no pending notifications → breakPending (single-notification design)")
    func pastBreakNoPending() async {
        let f = Fixture()
        let cycleId = UUID()
        let started = f.nowBox.value
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: started,
            breakActiveStartedAt: nil
        ))
        f.scheduler.stubPendingIdentifiers = []

        // Advance well past the break time.
        f.advance(by: BlinkBreakConstants.breakInterval + 60)

        await f.controller.reconcileOnLaunch()

        // With the single-notification design, reconcile can't distinguish
        // "notification just fired" from "notification fired a while ago" via
        // the pending list (it's in the delivered list, not pending). So we
        // unconditionally go to breakPending — the user needs to acknowledge
        // the break or stop the session manually.
        guard case .breakPending(let startedAt) = f.controller.state else {
            Issue.record("expected breakPending, got \(f.controller.state)")
            return
        }
        #expect(startedAt == started)
    }

    @Test("reconcile within breakActive window → breakActive")
    func withinBreakActiveWindow() async {
        let f = Fixture()
        let breakActiveStart = f.nowBox.value
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: breakActiveStart.addingTimeInterval(BlinkBreakConstants.lookAwayDuration),
            breakActiveStartedAt: breakActiveStart
        ))

        f.advance(by: BlinkBreakConstants.lookAwayDuration / 2)

        await f.controller.reconcileOnLaunch()

        guard case .breakActive(let startedAt) = f.controller.state else {
            Issue.record("expected breakActive, got \(f.controller.state)")
            return
        }
        #expect(startedAt == breakActiveStart)
    }

    @Test("reconcile after breakActive expired → next running cycle")
    func afterBreakActiveExpired() async {
        let f = Fixture()
        let breakActiveStart = f.nowBox.value
        let nextCycleId = UUID()
        let nextCycleStart = breakActiveStart.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: nextCycleId,
            cycleStartedAt: nextCycleStart,
            breakActiveStartedAt: breakActiveStart
        ))
        f.scheduler.stubPendingIdentifiers = CascadeBuilder.identifiers(for: nextCycleId)

        f.advance(by: BlinkBreakConstants.lookAwayDuration + 1)

        await f.controller.reconcileOnLaunch()

        guard case .running(let startedAt) = f.controller.state else {
            Issue.record("expected running, got \(f.controller.state)")
            return
        }
        #expect(startedAt == nextCycleStart)
        #expect(f.persistence.load().breakActiveStartedAt == nil)
    }

    @Test("reconcile with corrupt record (active but missing fields) → idle")
    func corruptRecord() async {
        let f = Fixture()
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: nil,
            cycleStartedAt: nil,
            breakActiveStartedAt: nil
        ))

        await f.controller.reconcileOnLaunch()

        #expect(f.controller.state == .idle)
        #expect(f.persistence.load() == .idle)
    }

    @Test("reconcile in running state re-arms the alarm for the remaining time")
    func reconcileRunningReArmsAlarm() async {
        let f = Fixture()
        let cycleId = UUID()
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: f.nowBox.value,
            breakActiveStartedAt: nil
        ))
        f.scheduler.stubPendingIdentifiers = CascadeBuilder.identifiers(for: cycleId)

        await f.controller.reconcileOnLaunch()

        #expect(f.alarm.lastArmed?.cycleId == cycleId)
        #expect(f.alarm.lastArmed?.fireDate == f.nowBox.value.addingTimeInterval(BlinkBreakConstants.breakInterval))
    }
}
