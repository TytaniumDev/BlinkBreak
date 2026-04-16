//
//  ScheduleIntegrationTests.swift
//  BlinkBreakCoreTests
//
//  Tests for SessionController's schedule-driven auto-start/stop behavior.
//

import Testing
import Foundation
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — schedule integration")
struct ScheduleIntegrationTests {

    @MainActor
    final class Fixture {
        let scheduler = MockNotificationScheduler()
        let persistence = InMemoryPersistence()
        let evaluator = MockScheduleEvaluator()
        let nowBox: NowBox
        let controller: SessionController

        init() {
            let box = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
            self.nowBox = box
            self.controller = SessionController(
                scheduler: scheduler,
                persistence: persistence,
                scheduleEvaluator: evaluator,
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

    @Test("reconcile auto-starts when evaluator says active and state is idle")
    func autoStart() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)  // Enable schedule so evaluateSchedule() runs
        f.evaluator.stubbedShouldBeActive = true
        #expect(f.controller.state == .idle)
        await f.controller.reconcile()
        #expect(f.controller.state != .idle)
        #expect(f.persistence.load().sessionActive == true)
    }

    @Test("reconcile auto-stops a schedule-started session when evaluator says inactive")
    func autoStop() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)  // Enable schedule so evaluateSchedule() runs
        // Auto-start via the schedule evaluator (not a manual start()).
        f.evaluator.stubbedShouldBeActive = true
        await f.controller.reconcile()
        #expect(f.controller.state != .idle)
        // Schedule window ends → evaluator now says inactive → should auto-stop.
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcile()
        #expect(f.controller.state == .idle)
    }

    @Test("reconcile does not auto-start when evaluator returns false")
    func noAutoStartWhenInactive() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)  // Enable schedule so evaluateSchedule() runs
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcile()
        #expect(f.controller.state == .idle)
    }

    @Test("stop() sets manualStopDate when evaluator says within window")
    func stopSetsManualStopDate() {
        let f = Fixture()
        f.evaluator.stubbedShouldBeActive = true
        f.controller.start()
        f.controller.stop()
        #expect(f.persistence.load().manualStopDate != nil)
    }

    @Test("stop() does not set manualStopDate when evaluator says outside window")
    func stopNoManualStopDateOutsideWindow() {
        let f = Fixture()
        f.evaluator.stubbedShouldBeActive = false
        f.controller.start()
        f.controller.stop()
        #expect(f.persistence.load().manualStopDate == nil)
    }

    @Test("reconcile passes manualStopDate to evaluator")
    func passesManualStopDate() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)  // Enable schedule so evaluateSchedule() runs
        let stopDate = Date(timeIntervalSince1970: 1_699_999_000)
        var record = SessionRecord.idle
        record.manualStopDate = stopDate
        f.persistence.save(record)
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcile()
        #expect(f.evaluator.shouldBeActiveCalls.last?.manualStopDate == stopDate)
    }

    @Test("reconcile does not auto-stop a manually started session")
    func manualStartNotAutoStopped() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)  // Enable schedule
        f.controller.start()                    // User manually taps Start
        #expect(f.controller.state != .idle)
        f.evaluator.stubbedShouldBeActive = false  // Outside schedule window
        await f.controller.reconcile()
        // Manual start must survive — schedule should not override user intent.
        #expect(f.controller.state != .idle)
    }

    @Test("reconcile does not auto-stop a manually started session even after multiple reconcile ticks")
    func manualStartSurvivesMultipleTicks() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)
        f.controller.start()
        f.evaluator.stubbedShouldBeActive = false
        // Simulate several 1-second ticks from RootView
        for _ in 0..<5 {
            f.advance(by: 1)
            await f.controller.reconcile()
        }
        #expect(f.controller.state != .idle)
    }

    @Test("auto-started session remains auto-stoppable after a break cycle")
    func autoStartSurvivesBreakCycle() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)
        // Auto-start via schedule.
        f.evaluator.stubbedShouldBeActive = true
        await f.controller.reconcile()
        #expect(f.controller.state != .idle)

        // Advance past the break interval so reconcile transitions to breakPending.
        f.advance(by: BlinkBreakConstants.breakInterval + 1)
        await f.controller.reconcile()

        // Acknowledge the break to transition through breakActive → running.
        let cycleId = f.persistence.load().currentCycleId!
        f.controller.handleStartBreakAction(cycleId: cycleId)

        // Advance past the look-away window.
        f.advance(by: BlinkBreakConstants.lookAwayDuration + 1)
        await f.controller.reconcile()
        #expect(f.controller.state != .idle)

        // Now schedule says inactive → should still auto-stop because the session
        // was schedule-started, even though we went through a full break cycle.
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcile()
        #expect(f.controller.state == .idle)
    }

    @Test("updateSchedule saves to persistence and updates published property")
    func updateSchedule() {
        let f = Fixture()
        let schedule = WeeklySchedule.default
        f.controller.updateSchedule(schedule)
        #expect(f.controller.weeklySchedule == schedule)
        #expect(f.persistence.loadSchedule() == schedule)
    }
}
