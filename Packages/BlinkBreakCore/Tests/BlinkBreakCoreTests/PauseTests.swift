//
//  PauseTests.swift
//  BlinkBreakCoreTests
//
//  Pausing a session inside a schedule window, resuming it, and the
//  schedule-driven stop of manually started sessions. Uses a Mon–Fri 9–5 GMT
//  schedule and virtual time.
//

import Testing
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — pause and manual stop times")
struct PauseTests {

    typealias Fixture = SessionControllerFixture
    let interval = BlinkBreakConstants.breakInterval
    let lookAway = BlinkBreakConstants.lookAwayDuration

    func at(_ weekday: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        TestCalendar.date(weekday: weekday, hour: hour, minute: minute)
    }

    /// Monday 16:00 with the schedule on, so today's window ends in an hour.
    /// Reconcile auto-starts a schedule session.
    func runningInWindow() async -> Fixture {
        let f = Fixture(now: at(2, 16), schedule: .workweekOn)
        await f.controller.reconcile()
        return f
    }

    // MARK: - canPause

    @Test("canPause is true for a running session inside a schedule window")
    func canPauseInWindow() async {
        let f = await runningInWindow()
        #expect(f.controller.state.isActive)
        #expect(f.controller.canPause)
    }

    @Test("canPause is false when idle")
    func canPauseIdle() async {
        let f = Fixture(now: at(2, 16), schedule: .workweekOn)
        #expect(f.controller.canPause == false)
    }

    @Test("canPause is false outside a schedule window")
    func canPauseOutsideWindow() async {
        let f = Fixture(now: at(7, 10), schedule: .workweekOn)
        await f.controller.start()
        #expect(f.controller.state.isActive)
        #expect(f.controller.canPause == false)
    }

    @Test("canPause is false when the schedule is off")
    func canPauseScheduleOff() async {
        let f = Fixture(now: at(2, 16))
        await f.controller.start()
        #expect(f.controller.canPause == false)
    }

    // MARK: - pause()

    @Test("pause() cancels the session's alarms and shows paused until the window end")
    func pauseCancels() async {
        let f = await runningInWindow()
        let breakAlarm = f.record.alarmId!

        await f.controller.pause()

        #expect(f.controller.state == .paused(until: at(2, 17)))
        #expect(f.alarms.cancelled.contains(breakAlarm))
        #expect(f.record.pausedUntil == at(2, 17))
        #expect(f.record.manualStopDate == at(2, 16))
        #expect(f.record.phase != .running)
    }

    @Test("pause() pre-books the next window, so the schedule resumes on its own")
    func pausePreBooksNextWindow() async {
        let f = await runningInWindow()

        await f.controller.pause()

        #expect(f.record.phase == .scheduled)
        #expect(f.record.alarmFiresAt == at(3, 9).addingTimeInterval(interval))
        #expect(f.alarms.systemAlarmIds == [f.record.alarmId!])
    }

    @Test("pause() is a no-op outside a schedule window")
    func pauseOutsideWindow() async {
        let f = Fixture(now: at(7, 10), schedule: .workweekOn)
        await f.controller.start()
        let before = f.record

        await f.controller.pause()

        #expect(f.record == before)
        #expect(f.controller.state.isActive)
    }

    @Test("pause() works from breakPending")
    func pauseFromBreakPending() async {
        let f = await runningInWindow()
        f.advance(by: interval)
        f.alarms.simulateAlerting(f.record.alarmId!)
        await f.settle()
        #expect(f.controller.state == .breakPending)
        #expect(f.controller.canPause)

        await f.controller.pause()

        #expect(f.controller.state == .paused(until: at(2, 17)))
    }

    // MARK: - While paused

    @Test("reconcile inside the window keeps the session paused and books nothing new")
    func reconcileWhilePaused() async {
        let f = await runningInWindow()
        await f.controller.pause()
        let scheduledBefore = f.alarms.scheduled.count

        f.advance(by: 600)
        await f.controller.reconcile()

        #expect(f.controller.state == .paused(until: at(2, 17)))
        #expect(f.alarms.scheduled.count == scheduledBefore)
    }

    @Test("a late removal event for the cancelled alarm doesn't knock paused back to idle")
    func lateRemovalWhilePaused() async {
        let f = await runningInWindow()
        let breakAlarm = f.record.alarmId!
        await f.controller.pause()

        f.alarms.simulateRemoval(breakAlarm)
        await f.releaseSleepsAndSettle()

        #expect(f.controller.state == .paused(until: at(2, 17)))
    }

    @Test("the pause lapses to idle when the window ends, without starting a session")
    func pauseLapses() async {
        let f = await runningInWindow()
        await f.controller.pause()
        let scheduledBefore = f.alarms.scheduled.count

        f.now.value = at(2, 17)
        await f.releaseSleepsAndSettle()

        #expect(f.controller.state == .idle)
        #expect(f.record.pausedUntil == nil)
        #expect(f.alarms.scheduled.count == scheduledBefore)
    }

    @Test("the next window starts on its own after a pause")
    func nextWindowAfterPause() async {
        let f = await runningInWindow()
        await f.controller.pause()

        f.now.value = at(3, 9)
        await f.controller.reconcile()

        #expect(f.controller.state.isActive)
        #expect(f.record.wasAutoStarted)
    }

    @Test("turning the schedule off while paused lapses the pause")
    func disableWhilePaused() async {
        let f = await runningInWindow()
        await f.controller.pause()

        f.controller.updateSchedule(.default)
        await f.settle()

        #expect(f.controller.state == .idle)
        #expect(f.record.pausedUntil == nil)
        #expect(f.alarms.systemAlarmIds.isEmpty)
    }

    @Test("editing the schedule while paused keeps the pause")
    func editWhilePaused() async {
        let f = await runningInWindow()
        await f.controller.pause()

        var schedule = WeeklySchedule.workweekOn
        schedule.days[3]?.startTime = DateComponents(hour: 8, minute: 0)
        f.controller.updateSchedule(schedule)
        await f.settle()

        #expect(f.controller.state == .paused(until: at(2, 17)))
        #expect(f.record.alarmFiresAt == at(3, 8).addingTimeInterval(interval))
    }

    @Test("Stop while paused goes idle and stays off for the rest of the window")
    func stopWhilePaused() async {
        let f = await runningInWindow()
        await f.controller.pause()

        await f.controller.stop()

        #expect(f.controller.state == .idle)
        #expect(f.record.pausedUntil == nil)
        #expect(f.record.manualStopDate != nil)

        f.advance(by: 600)
        await f.controller.reconcile()
        #expect(f.controller.state == .idle)
    }

    // MARK: - Resume and manual stop times

    @Test("Resume runs a manual session that still stops at the window end")
    func resume() async {
        let f = await runningInWindow()
        await f.controller.pause()
        f.advance(by: 600)

        await f.controller.start()

        #expect(f.controller.state == .running(breakAt: f.now.value.addingTimeInterval(interval)))
        #expect(f.record.pausedUntil == nil)
        #expect(f.record.manualStopDate == nil)
        #expect(f.record.wasAutoStarted == false)
        #expect(f.record.scheduledStopAt == at(2, 17))

        f.now.value = at(2, 17, 5)
        await f.controller.reconcile()
        #expect(f.controller.state == .idle)
    }

    @Test("a manual start outside a window stops at the end of the next window")
    func manualStartBeforeWindow() async {
        let f = Fixture(now: at(2, 7), schedule: .workweekOn)
        await f.controller.start()
        #expect(f.record.scheduledStopAt == at(2, 17))
    }

    @Test("a manual start with the schedule off has no stop time")
    func manualStartScheduleOff() async {
        let f = Fixture(now: at(2, 10))
        await f.controller.start()
        #expect(f.record.scheduledStopAt == nil)
    }

    @Test("schedule-started sessions don't record a stop time; they follow the live schedule")
    func autoStartNoStopTime() async {
        let f = await runningInWindow()
        #expect(f.record.wasAutoStarted)
        #expect(f.record.scheduledStopAt == nil)
    }

    @Test("the stop time survives cycle rolls and the look-away")
    func stopTimeSurvivesRolls() async {
        let f = Fixture(now: at(2, 10), schedule: .workweekOn)
        await f.controller.start()
        f.advance(by: interval)

        await f.controller.startBreak()
        #expect(f.record.scheduledStopAt == at(2, 17))

        f.advance(by: lookAway)
        await f.controller.respond(to: .confirm, alarmId: f.record.alarmId!)
        #expect(f.record.phase == .running)
        #expect(f.record.scheduledStopAt == at(2, 17))
    }

    @Test("a manual session whose next break would land past its stop time stops, off for the rest of the window")
    func manualStopsAtWindowEnd() async {
        let f = Fixture(now: at(2, 16, 30), schedule: .workweekOn)
        await f.controller.start()
        f.now.value = at(2, 16, 50)

        await f.controller.respond(to: .stop, alarmId: f.record.alarmId!)

        #expect(f.controller.state == .idle)
        #expect(f.record.phase == .scheduled)
        #expect(f.record.alarmFiresAt == at(3, 9).addingTimeInterval(interval))
    }

    @Test("a manual session past its stop time, found in a new window, hands over to the schedule")
    func handOffToNewWindow() async {
        let f = Fixture(now: at(2, 16, 30), schedule: .workweekOn)
        await f.controller.start()

        // The app isn't opened again until the next morning's window.
        f.now.value = at(3, 10)
        await f.controller.reconcile()

        #expect(f.controller.state.isActive)
        #expect(f.record.wasAutoStarted)
        #expect(f.record.manualStopDate == nil)
    }

    @Test("stopping in a window then editing the schedule doesn't restart the session that day")
    func stopThenEditDoesNotRestart() async {
        let f = Fixture(now: at(2, 10), schedule: .workweekOn)
        await f.controller.reconcile()
        await f.controller.stop()

        var schedule = WeeklySchedule.workweekOn
        schedule.days[3]?.startTime = DateComponents(hour: 8, minute: 0)
        f.controller.updateSchedule(schedule)
        await f.settle()

        #expect(f.controller.state == .idle)
        #expect(f.record.phase == .scheduled)
        #expect(f.record.alarmFiresAt == at(3, 8).addingTimeInterval(interval))
    }
}
