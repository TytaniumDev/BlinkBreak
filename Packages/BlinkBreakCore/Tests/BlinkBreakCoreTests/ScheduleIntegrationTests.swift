//
//  ScheduleIntegrationTests.swift
//  BlinkBreakCoreTests
//
//  How SessionController follows the weekly schedule: auto-start inside a
//  window, pre-booking the first break of the next window, stopping at the end
//  of a window, and respecting manual stops. Uses the real schedule math with a
//  Mon–Fri 9–5 GMT schedule and virtual time.
//

import Testing
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — weekly schedule")
struct ScheduleIntegrationTests {

    typealias Fixture = SessionControllerFixture
    let interval = BlinkBreakConstants.breakInterval
    let lookAway = BlinkBreakConstants.lookAwayDuration

    func at(_ weekday: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        TestCalendar.date(weekday: weekday, hour: hour, minute: minute)
    }

    // MARK: - Editing

    @Test("updateSchedule saves and publishes immediately")
    func updatePersists() async {
        let f = Fixture()
        f.controller.updateSchedule(.workweekOn)
        #expect(f.controller.weeklySchedule == .workweekOn)
        #expect(f.persistence.loadSchedule() == .workweekOn)
    }

    @Test("scheduleStatus comes from the schedule")
    func status() async {
        let f = Fixture(now: at(2, 8), schedule: .workweekOn)
        #expect(f.controller.scheduleStatus(at: at(2, 8))?.hasPrefix("Starts at") == true)
        #expect(f.controller.scheduleStatus(at: at(2, 10))?.hasPrefix("Active until") == true)
    }

    // MARK: - Auto-start

    @Test("turning the schedule on inside a window starts a session right away")
    func enableInsideWindow() async {
        let f = Fixture(now: at(2, 10))

        f.controller.updateSchedule(.workweekOn)
        await f.settle()

        #expect(f.controller.state == .running(breakAt: at(2, 10).addingTimeInterval(interval)))
        #expect(f.record.wasAutoStarted)
    }

    @Test("reconcile inside a window starts a session")
    func reconcileInsideWindow() async {
        let f = Fixture(now: at(2, 10), schedule: .workweekOn)
        await f.controller.reconcile()
        #expect(f.record.phase == .running)
        #expect(f.record.wasAutoStarted)
    }

    @Test("outside a window, the first break of the next window is pre-booked and the UI stays idle")
    func preBook() async {
        let f = Fixture(now: at(2, 7))

        f.controller.updateSchedule(.workweekOn)
        await f.settle()

        #expect(f.controller.state == .idle)
        #expect(f.record.phase == .scheduled)
        #expect(f.alarms.lastScheduled?.kind == .breakDue)
        #expect(f.alarms.lastScheduled?.fireDate == at(2, 9).addingTimeInterval(interval))
    }

    @Test("Friday evening pre-books Monday morning")
    func preBookSkipsWeekend() async {
        let f = Fixture(now: at(6, 18), schedule: .workweekOn)
        await f.controller.reconcile()
        #expect(f.alarms.lastScheduled?.fireDate == at(2, 9).addingTimeInterval(interval + 7 * 86_400))
    }

    @Test("when the pre-booked window opens, the UI shows the running countdown")
    func preBookedWindowOpens() async {
        let f = Fixture(now: at(2, 7), schedule: .workweekOn)
        await f.controller.reconcile()

        f.now.value = at(2, 9)
        await f.releaseSleepsAndSettle()

        #expect(f.controller.state == .running(breakAt: at(2, 9).addingTimeInterval(interval)))
        #expect(f.record.phase == .running)
    }

    @Test("the pre-booked alarm's \"Start break\" works even if the app never ran in between")
    func preBookedAlarmConfirm() async {
        let f = Fixture(now: at(2, 7), schedule: .workweekOn)
        await f.controller.reconcile()
        let alarm = f.record.alarmId!

        f.now.value = at(2, 9, 20)
        await f.controller.respond(to: .confirm, alarmId: alarm)

        #expect(f.record.phase == .lookingAway)
    }

    @Test("turning the schedule off drops the pre-booked alarm")
    func disableDropsPreBook() async {
        let f = Fixture(now: at(2, 7), schedule: .workweekOn)
        await f.controller.reconcile()
        let preBooked = f.record.alarmId!

        f.controller.updateSchedule(.default)
        await f.settle()

        #expect(f.record.phase == .idle)
        #expect(f.alarms.cancelled.contains(preBooked))
        #expect(f.alarms.systemAlarmIds.isEmpty)
    }

    @Test("editing the start time re-books the pre-booked alarm")
    func editReBooks() async {
        let f = Fixture(now: at(2, 7), schedule: .workweekOn)
        await f.controller.reconcile()

        var schedule = WeeklySchedule.workweekOn
        schedule.days[2]?.startTime = DateComponents(hour: 8, minute: 0)
        f.controller.updateSchedule(schedule)
        await f.settle()

        #expect(f.alarms.systemAlarmIds.count == 1)
        #expect(f.record.alarmFiresAt == at(2, 8).addingTimeInterval(interval))
    }

    // MARK: - Manual stop

    @Test("stopping inside a window remembers it and pre-books the next day instead of restarting")
    func manualStopInWindow() async {
        let f = Fixture(now: at(2, 10), schedule: .workweekOn)
        await f.controller.reconcile()

        await f.controller.stop()

        #expect(f.controller.state == .idle)
        #expect(f.record.phase == .scheduled)
        #expect(f.record.alarmFiresAt == at(3, 9).addingTimeInterval(interval))

        f.advance(by: 3600)
        await f.controller.reconcile()
        #expect(f.record.alarmFiresAt == at(3, 9).addingTimeInterval(interval), "no restart later in the window")
    }

    @Test("stopping outside any window doesn't record a manual stop")
    func manualStopOutsideWindow() async {
        let f = Fixture(now: at(7, 10))
        await f.startRunning()

        await f.controller.stop()

        #expect(f.record.manualStopDate == nil)
    }

    @Test("a manual Start during a stopped window runs normally")
    func manualStartAfterStop() async {
        let f = Fixture(now: at(2, 10), schedule: .workweekOn)
        await f.controller.reconcile()
        await f.controller.stop()

        await f.controller.start()

        #expect(f.record.phase == .running)
        #expect(f.record.wasAutoStarted == false)
    }

    // MARK: - End of window

    @Test("schedule-started: a cycle that would ring after the window ends stops and pre-books the next day")
    func autoStopAtWindowEnd() async {
        let f = Fixture(now: at(2, 16, 30), schedule: .workweekOn)
        await f.controller.reconcile()
        let alarm = f.record.alarmId!

        f.now.value = at(2, 16, 50)
        await f.controller.respond(to: .stop, alarmId: alarm)

        #expect(f.controller.state == .idle)
        #expect(f.record.phase == .scheduled)
        #expect(f.record.alarmFiresAt == at(3, 9).addingTimeInterval(interval))
    }

    @Test("schedule-started: look-away ending near the window end stops, and the ringing alarm keeps ringing")
    func autoStopAfterLookAway() async {
        let f = Fixture(now: at(2, 16, 30), schedule: .workweekOn)
        await f.controller.reconcile()
        f.now.value = at(2, 16, 50)
        await f.controller.startBreak()
        let lookAwayAlarm = f.record.alarmId!

        f.advance(by: lookAway + BlinkBreakConstants.lookAwayCompletionMargin)
        f.alarms.simulateAlerting(lookAwayAlarm)
        await f.settle()

        #expect(f.record.phase == .scheduled)
        #expect(f.alarms.systemAlarmIds.contains(lookAwayAlarm))
    }

    @Test("schedule-started: \"Start break\" answered after the window ended stops instead")
    func lateStartBreak() async {
        let f = Fixture(now: at(2, 16, 30), schedule: .workweekOn)
        await f.controller.reconcile()
        let alarm = f.record.alarmId!

        f.now.value = at(2, 17, 30)
        await f.controller.respond(to: .confirm, alarmId: alarm)

        #expect(f.alarms.scheduled.contains { $0.kind == .lookAwayDone } == false)
        #expect(f.record.phase == .scheduled)
    }

    @Test("schedule-started: reconcile after the window ends stops an unanswered session")
    func reconcileAfterWindow() async {
        let f = Fixture(now: at(2, 16, 30), schedule: .workweekOn)
        await f.controller.reconcile()

        f.now.value = at(2, 18)
        await f.controller.reconcile()

        #expect(f.controller.state == .idle)
        #expect(f.record.alarmFiresAt == at(3, 9).addingTimeInterval(interval))
    }

    @Test("a manual session started with the schedule off ignores the schedule turned on later")
    func manualIgnoresSchedule() async {
        let f = Fixture(now: at(2, 16, 50))
        let alarm = await f.startRunning()
        f.controller.updateSchedule(.workweekOn)
        await f.settle()

        f.now.value = at(2, 17, 10)
        await f.controller.reconcile()
        #expect(f.record.phase == .running)

        await f.controller.respond(to: .stop, alarmId: alarm)
        #expect(f.record.phase == .running)
        #expect(f.record.wasAutoStarted == false)
    }
}
