//
//  PauseTests.swift
//  BlinkBreakCoreTests
//
//  Tests for pausing a session inside a schedule window, resuming it, and the
//  schedule-driven stop of manually started sessions.
//

import Testing
import Foundation
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — pause / resume")
struct PauseTests {

    /// A fixture with the schedule enabled, the clock inside a window, and the
    /// window ending one hour from "now".
    private func makeInWindowFixture() -> (SessionControllerFixture, MockScheduleEvaluator, Date) {
        let evaluator = MockScheduleEvaluator()
        let f = SessionControllerFixture(evaluator: evaluator)
        f.controller.updateSchedule(.default)
        let windowEnd = f.nowBox.value.addingTimeInterval(60 * 60)
        evaluator.stubbedWindowEnd = windowEnd
        evaluator.stubbedShouldBeActiveBlock = { date in date < windowEnd }
        return (f, evaluator, windowEnd)
    }

    /// Auto-start a session via the schedule and let it settle into `.running`.
    private func autoStart(_ f: SessionControllerFixture) async {
        await f.controller.reconcile()
        await settle()
    }

    // MARK: - canPause

    @Test("canPause is true for a running session inside a schedule window")
    func canPauseInWindow() async {
        let (f, _, _) = makeInWindowFixture()
        await autoStart(f)
        #expect(f.controller.state.isActive)
        #expect(f.controller.canPause)
    }

    @Test("canPause is false when idle")
    func canPauseIdle() {
        let (f, _, _) = makeInWindowFixture()
        #expect(f.controller.canPause == false)
    }

    @Test("canPause is false outside a schedule window")
    func canPauseOutsideWindow() async {
        let (f, evaluator, _) = makeInWindowFixture()
        evaluator.stubbedShouldBeActiveBlock = { _ in false }
        f.controller.start()
        await settle()
        #expect(f.controller.state.isActive)
        #expect(f.controller.canPause == false)
    }

    @Test("canPause is false when the schedule is disabled")
    func canPauseScheduleDisabled() async {
        let (f, _, _) = makeInWindowFixture()
        f.controller.updateSchedule(.empty)
        f.controller.start()
        await settle()
        #expect(f.controller.canPause == false)
    }

    // MARK: - pause()

    @Test("pause() cancels alarms and transitions to paused until the window end")
    func pauseTransitions() async {
        let (f, _, windowEnd) = makeInWindowFixture()
        await autoStart(f)
        let cancelAllBefore = f.alarmScheduler.cancelAllCount

        f.controller.pause()
        await settle()

        #expect(f.controller.state == .paused(until: windowEnd))
        #expect(f.alarmScheduler.cancelAllCount == cancelAllBefore + 1)
        let record = f.persistence.load()
        #expect(record.sessionActive == false)
        #expect(record.pausedUntil == windowEnd)
        #expect(record.manualStopDate == f.nowBox.value)
        #expect(record.currentAlarmId == nil)
    }

    @Test("pause() is a no-op outside a schedule window")
    func pauseNoOpOutsideWindow() async {
        let (f, evaluator, _) = makeInWindowFixture()
        evaluator.stubbedShouldBeActiveBlock = { _ in false }
        f.controller.start()
        await settle()
        let stateBefore = f.controller.state

        f.controller.pause()
        await settle()

        #expect(f.controller.state == stateBefore)
        #expect(f.persistence.load().sessionActive == true)
    }

    @Test("pause() works from breakPending")
    func pauseFromBreakPending() async {
        let (f, _, windowEnd) = makeInWindowFixture()
        await autoStart(f)
        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        #expect(f.controller.canPause)

        f.controller.pause()
        await settle()

        #expect(f.controller.state == .paused(until: windowEnd))
    }

    // MARK: - While paused

    @Test("reconcile inside the window keeps the session paused and schedules nothing")
    func reconcileStaysPaused() async {
        let (f, _, windowEnd) = makeInWindowFixture()
        await autoStart(f)
        f.controller.pause()
        await settle()
        let scheduledBefore = f.alarmScheduler.scheduled.count

        f.advance(by: 30 * 60)
        await f.controller.reconcile()
        await settle()

        #expect(f.controller.state == .paused(until: windowEnd))
        #expect(f.alarmScheduler.scheduled.count == scheduledBefore)
    }

    @Test("a late dismissed event for the cancelled alarm doesn't knock paused back to idle")
    func lateDismissKeepsPaused() async {
        let (f, _, windowEnd) = makeInWindowFixture()
        await autoStart(f)
        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.controller.pause()
        await settle()

        f.alarmScheduler.simulateDismiss(alarmId: breakAlarmId, kind: .breakDue)
        await settle()

        #expect(f.controller.state == .paused(until: windowEnd))
    }

    @Test("pause lapses to idle once the window ends, without auto-starting")
    func pauseLapsesAtWindowEnd() async {
        let (f, _, _) = makeInWindowFixture()
        await autoStart(f)
        f.controller.pause()
        await settle()
        let scheduledBefore = f.alarmScheduler.scheduled.count

        f.advance(by: 60 * 60 + 1)
        await f.controller.reconcile()
        await settle()

        #expect(f.controller.state == .idle)
        #expect(f.persistence.load().pausedUntil == nil)
        #expect(f.alarmScheduler.scheduled.count == scheduledBefore)
    }

    @Test("the next schedule window auto-starts after a pause lapsed")
    func nextWindowAutoStartsAfterPause() async {
        let (f, evaluator, _) = makeInWindowFixture()
        await autoStart(f)
        f.controller.pause()
        await settle()

        // Jump to the next day's window.
        f.advance(by: 24 * 60 * 60)
        evaluator.stubbedShouldBeActiveBlock = { _ in true }
        await f.controller.reconcile()
        await settle()

        #expect(f.controller.state.isActive)
        #expect(f.persistence.load().wasAutoStarted == true)
    }

    @Test("disabling the schedule while paused lapses the pause on reconcile")
    func scheduleDisabledWhilePaused() async {
        let (f, _, _) = makeInWindowFixture()
        await autoStart(f)
        f.controller.pause()
        await settle()

        f.controller.updateSchedule(.empty)
        await f.controller.reconcile()
        await settle()

        #expect(f.controller.state == .idle)
    }

    @Test("stop() from paused goes idle and clears the pause")
    func stopFromPaused() async {
        let (f, _, _) = makeInWindowFixture()
        await autoStart(f)
        f.controller.pause()
        await settle()

        f.controller.stop()
        await settle()

        #expect(f.controller.state == .idle)
        let record = f.persistence.load()
        #expect(record.pausedUntil == nil)
        // Still inside today's window → stays off for the rest of it.
        #expect(record.manualStopDate != nil)
    }

    // MARK: - Resume

    @Test("resuming (start from paused) runs a session that still stops at the window end")
    func resumeStopsAtWindowEnd() async {
        let (f, _, windowEnd) = makeInWindowFixture()
        await autoStart(f)
        f.controller.pause()
        await settle()

        f.advance(by: 10 * 60)
        f.controller.start()
        await settle()

        #expect(f.controller.state == .running(cycleStartedAt: f.nowBox.value))
        let record = f.persistence.load()
        #expect(record.sessionActive == true)
        #expect(record.pausedUntil == nil)
        #expect(record.manualStopDate == nil)
        #expect(record.scheduledStopAt == windowEnd)

        f.advance(by: 60 * 60)
        await f.controller.reconcile()
        await settle()
        #expect(f.controller.state == .idle)
    }
}

@MainActor
@Suite("SessionController — manual sessions stop at the next schedule end")
struct ManualSessionScheduleStopTests {

    private func makeFixture() -> (SessionControllerFixture, MockScheduleEvaluator) {
        let evaluator = MockScheduleEvaluator()
        let f = SessionControllerFixture(evaluator: evaluator)
        f.controller.updateSchedule(.default)
        return (f, evaluator)
    }

    @Test("manual start records the next window end as scheduledStopAt")
    func manualStartRecordsStop() async {
        let (f, evaluator) = makeFixture()
        let windowEnd = f.nowBox.value.addingTimeInterval(3 * 60 * 60)
        evaluator.stubbedWindowEnd = windowEnd

        f.controller.start()
        await settle()

        #expect(f.persistence.load().scheduledStopAt == windowEnd)
    }

    @Test("manual start with the schedule disabled has no scheduledStopAt")
    func manualStartScheduleDisabled() async {
        let (f, evaluator) = makeFixture()
        f.controller.updateSchedule(.empty)
        evaluator.stubbedWindowEnd = f.nowBox.value.addingTimeInterval(60)

        f.controller.start()
        await settle()

        #expect(f.persistence.load().scheduledStopAt == nil)
    }

    @Test("auto-started sessions don't record scheduledStopAt (they follow the live schedule)")
    func autoStartHasNoStop() async {
        let (f, evaluator) = makeFixture()
        evaluator.stubbedShouldBeActive = true
        evaluator.stubbedWindowEnd = f.nowBox.value.addingTimeInterval(60)

        await f.controller.reconcile()
        await settle()

        #expect(f.persistence.load().wasAutoStarted == true)
        #expect(f.persistence.load().scheduledStopAt == nil)
    }

    @Test("reconcile stops a manual session once scheduledStopAt has passed")
    func reconcileStopsAfterStopAt() async {
        let (f, evaluator) = makeFixture()
        let windowEnd = f.nowBox.value.addingTimeInterval(60 * 60)
        evaluator.stubbedWindowEnd = windowEnd
        f.controller.start()
        await settle()

        f.advance(by: 30 * 60)
        await f.controller.reconcile()
        await settle()
        #expect(f.controller.state.isActive)

        f.advance(by: 30 * 60)
        await f.controller.reconcile()
        await settle()
        #expect(f.controller.state == .idle)
        #expect(f.persistence.load().manualStopDate == nil)
    }

    @Test("scheduledStopAt survives a cycle roll")
    func stopAtCarriedAcrossRoll() async {
        let (f, evaluator) = makeFixture()
        let windowEnd = f.nowBox.value.addingTimeInterval(5 * 60 * 60)
        evaluator.stubbedWindowEnd = windowEnd
        f.controller.start()
        await settle()

        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        f.alarmScheduler.simulateDismiss(alarmId: breakAlarmId, kind: .breakDue)
        await settle()

        #expect(f.persistence.load().currentAlarmId != breakAlarmId)
        #expect(f.persistence.load().scheduledStopAt == windowEnd)
    }

    @Test("lookAwayDone dismissed when the next break would fire past scheduledStopAt stops the session")
    func rollPastStopAtStops() async {
        let (f, evaluator) = makeFixture()
        // Window ends before the next break would fire.
        let windowEnd = f.nowBox.value.addingTimeInterval(BlinkBreakConstants.breakInterval / 2)
        evaluator.stubbedWindowEnd = windowEnd
        f.controller.start()
        await settle()

        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        f.persistence.saveAcknowledgeRequestedAlarmId(breakAlarmId)
        f.alarmScheduler.simulateDismiss(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        let lookAwayId = f.alarmScheduler.scheduled.last!.alarmId
        #expect(f.alarmScheduler.scheduled.last!.kind == .lookAwayDone)

        let scheduledBefore = f.alarmScheduler.scheduled.count
        f.alarmScheduler.simulateFire(alarmId: lookAwayId, kind: .lookAwayDone)
        f.alarmScheduler.simulateDismiss(alarmId: lookAwayId, kind: .lookAwayDone)
        await settle()

        #expect(f.controller.state == .idle)
        #expect(f.alarmScheduler.scheduled.count == scheduledBefore)
    }

    @Test("a manual session past its stop that finds a new window open hands off to the schedule")
    func expiredManualSessionHandsOffToOpenWindow() async {
        let (f, evaluator) = makeFixture()
        let firstWindowEnd = f.nowBox.value.addingTimeInterval(60 * 60)
        evaluator.stubbedWindowEnd = firstWindowEnd
        f.controller.start()
        await settle()

        // App wasn't opened until the next day's window.
        f.advance(by: 24 * 60 * 60)
        evaluator.stubbedShouldBeActive = true
        await f.controller.reconcile()
        await settle()

        #expect(f.controller.state.isActive)
        let record = f.persistence.load()
        #expect(record.wasAutoStarted == true)
        #expect(record.manualStopDate == nil)
    }
}
