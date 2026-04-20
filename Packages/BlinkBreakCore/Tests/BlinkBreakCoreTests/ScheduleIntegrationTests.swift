//
//  ScheduleIntegrationTests.swift
//  BlinkBreakCoreTests
//
//  Tests for SessionController's schedule-driven auto-start/stop behavior.
//

@testable import BlinkBreakCore
import Foundation
import Testing

@MainActor
@Suite("SessionController — schedule integration")
struct ScheduleIntegrationTests {

    typealias Fixture = TestFixture

    @Test("reconcile auto-starts when evaluator says active and state is idle")
    func autoStart() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)
        f.evaluator.stubbedShouldBeActive = true
        #expect(f.controller.state == .idle)
        await f.controller.reconcile()
        await settle()
        #expect(f.controller.state != .idle)
        #expect(f.persistence.load().sessionActive == true)
    }

    @Test("reconcile auto-stops a schedule-started session when evaluator says inactive")
    func autoStop() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)
        f.evaluator.stubbedShouldBeActive = true
        await f.controller.reconcile()
        await settle()
        #expect(f.controller.state != .idle)

        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcile()
        await settle()
        #expect(f.controller.state == .idle)
    }

    @Test("reconcile does not auto-start when evaluator returns false")
    func noAutoStartWhenInactive() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcile()
        await settle()
        #expect(f.controller.state == .idle)
    }

    @Test("stop() sets manualStopDate when evaluator says within window")
    func stopSetsManualStopDate() async {
        let f = Fixture()
        f.evaluator.stubbedShouldBeActive = true
        await f.controller.start()
        await f.controller.stop()
        #expect(f.persistence.load().manualStopDate != nil)
    }

    @Test("stop() does not set manualStopDate when evaluator says outside window")
    func stopNoManualStopDateOutsideWindow() async {
        let f = Fixture()
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.start()
        await f.controller.stop()
        #expect(f.persistence.load().manualStopDate == nil)
    }

    @Test("reconcile passes manualStopDate to evaluator")
    func passesManualStopDate() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)
        let stopDate = Date(timeIntervalSince1970: 1_699_999_000)
        var record = SessionRecord.idle
        record.manualStopDate = stopDate
        f.persistence.save(record)
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcile()
        await settle()
        #expect(f.evaluator.shouldBeActiveCalls.last?.manualStopDate == stopDate)
    }

    @Test("reconcile does not auto-stop a manually started session")
    func manualStartNotAutoStopped() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)
        await f.controller.start()
        #expect(f.controller.state != .idle)

        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcile()
        await settle()
        #expect(f.controller.state != .idle)
    }

    @Test("reconcile does not auto-stop a manually started session even after multiple reconcile ticks")
    func manualStartSurvivesMultipleTicks() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)
        await f.controller.start()
        f.evaluator.stubbedShouldBeActive = false
        for _ in 0..<5 {
            f.advance(by: 1)
            await f.controller.reconcile()
            await settle()
        }
        #expect(f.controller.state != .idle)
    }

    @Test("auto-started session remains auto-stoppable after a break cycle")
    func autoStartSurvivesBreakCycle() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)
        f.evaluator.stubbedShouldBeActive = true
        await f.controller.reconcile()
        await settle()
        #expect(f.controller.state != .idle)

        // Drive a full break cycle via simulated alarm events.
        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        f.alarmScheduler.simulateDismiss(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        let lookAwayAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: lookAwayAlarmId, kind: .lookAwayDone)
        f.alarmScheduler.simulateDismiss(alarmId: lookAwayAlarmId, kind: .lookAwayDone)
        await settle()
        #expect(f.controller.state != .idle)

        // Schedule says inactive → should auto-stop because session was schedule-started.
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcile()
        await settle()
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
