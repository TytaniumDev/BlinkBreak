//
//  ScheduleEvaluationTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the pure schedule math in WeeklySchedule+Evaluation.swift.
//  2026-04-05 is a Sunday; `TestCalendar.date(weekday:)` indexes that week.
//

import Testing
@testable import BlinkBreakCore

@Suite("WeeklySchedule — evaluation")
struct ScheduleEvaluationTests {

    let calendar = TestCalendar.gmt
    let schedule = WeeklySchedule.workweekOn

    func at(_ weekday: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        TestCalendar.date(weekday: weekday, hour: hour, minute: minute)
    }

    // MARK: - isActive

    @Test("inactive when the schedule is off")
    func scheduleOff() {
        #expect(WeeklySchedule.default.isActive(at: at(2, 10), calendar: calendar) == false)
    }

    @Test("inactive on a disabled day")
    func disabledDay() {
        #expect(schedule.isActive(at: at(7, 10), calendar: calendar) == false)
    }

    @Test("active inside the window, start inclusive, end exclusive")
    func windowBounds() {
        #expect(schedule.isActive(at: at(2, 8, 59), calendar: calendar) == false)
        #expect(schedule.isActive(at: at(2, 9), calendar: calendar))
        #expect(schedule.isActive(at: at(2, 12), calendar: calendar))
        #expect(schedule.isActive(at: at(2, 16, 59), calendar: calendar))
        #expect(schedule.isActive(at: at(2, 17), calendar: calendar) == false)
    }

    @Test("a manual stop inside today's window keeps it inactive for the rest of the window")
    func manualStopSameWindow() {
        #expect(schedule.isActive(at: at(2, 14), manualStopDate: at(2, 11), calendar: calendar) == false)
    }

    @Test("a manual stop from another day or outside the window doesn't matter")
    func manualStopElsewhere() {
        #expect(schedule.isActive(at: at(3, 14), manualStopDate: at(2, 11), calendar: calendar))
        #expect(schedule.isActive(at: at(2, 14), manualStopDate: at(2, 8), calendar: calendar))
    }

    @Test("a window whose end isn't after its start never activates")
    func invalidWindow() {
        var broken = schedule
        broken.days[2] = DaySchedule(
            isEnabled: true,
            startTime: DateComponents(hour: 17, minute: 0),
            endTime: DateComponents(hour: 9, minute: 0)
        )
        #expect(broken.isActive(at: at(2, 18), calendar: calendar) == false)
        #expect(broken.isActive(at: at(2, 8), calendar: calendar) == false)
    }

    // MARK: - nextWindowStart

    @Test("before today's window → today's start")
    func nextToday() {
        #expect(schedule.nextWindowStart(after: at(2, 7), calendar: calendar) == at(2, 9))
    }

    @Test("during or after today's window → tomorrow's start")
    func nextTomorrow() {
        #expect(schedule.nextWindowStart(after: at(2, 10), calendar: calendar) == at(3, 9))
        #expect(schedule.nextWindowStart(after: at(2, 18), calendar: calendar) == at(3, 9))
    }

    @Test("Friday evening → Monday, skipping the weekend")
    func nextSkipsWeekend() {
        let nextMonday = at(2, 9).addingTimeInterval(7 * 86_400)
        #expect(schedule.nextWindowStart(after: at(6, 18), calendar: calendar) == nextMonday)
    }

    @Test("a single enabled day finds itself a week later")
    func nextWeek() {
        var single = WeeklySchedule(isEnabled: true, days: [2: .nineToFive(isEnabled: true)])
        single.isEnabled = true
        let nextMonday = at(2, 9).addingTimeInterval(7 * 86_400)
        #expect(single.nextWindowStart(after: at(2, 10), calendar: calendar) == nextMonday)
    }

    @Test("nil when the schedule is off or has no enabled days")
    func nextNone() {
        #expect(WeeklySchedule.default.nextWindowStart(after: at(2, 7), calendar: calendar) == nil)
        #expect(WeeklySchedule(isEnabled: true, days: [:]).nextWindowStart(after: at(2, 7), calendar: calendar) == nil)
    }

    // MARK: - currentOrNextWindowEnd

    @Test("inside or before today's window → today's end")
    func windowEndToday() {
        #expect(schedule.currentOrNextWindowEnd(from: at(2, 10), calendar: calendar) == at(2, 17))
        #expect(schedule.currentOrNextWindowEnd(from: at(2, 7), calendar: calendar) == at(2, 17))
    }

    @Test("after today's window, or exactly at its end → tomorrow's end")
    func windowEndTomorrow() {
        #expect(schedule.currentOrNextWindowEnd(from: at(2, 18), calendar: calendar) == at(3, 17))
        #expect(schedule.currentOrNextWindowEnd(from: at(2, 17), calendar: calendar) == at(3, 17))
    }

    @Test("skips disabled days (Saturday → Monday's end)")
    func windowEndSkipsWeekend() {
        let mondayEnd = at(2, 17).addingTimeInterval(7 * 86_400)
        #expect(schedule.currentOrNextWindowEnd(from: at(7, 10), calendar: calendar) == mondayEnd)
    }

    @Test("skips a malformed window whose end is before its start")
    func windowEndSkipsMalformed() {
        var broken = schedule
        broken.days[2] = DaySchedule(
            isEnabled: true,
            startTime: DateComponents(hour: 17, minute: 0),
            endTime: DateComponents(hour: 9, minute: 0)
        )
        #expect(broken.currentOrNextWindowEnd(from: at(2, 10), calendar: calendar) == at(3, 17))
    }

    @Test("nil when the schedule is off or has no enabled days")
    func windowEndNone() {
        #expect(WeeklySchedule.default.currentOrNextWindowEnd(from: at(2, 10), calendar: calendar) == nil)
        #expect(WeeklySchedule(isEnabled: true, days: [:]).currentOrNextWindowEnd(from: at(2, 10), calendar: calendar) == nil)
    }

    // MARK: - statusText

    @Test("status text for before, during, and after the window")
    func statusText() {
        #expect(schedule.statusText(at: at(2, 7), calendar: calendar)?.hasPrefix("Starts at") == true)
        #expect(schedule.statusText(at: at(2, 10), calendar: calendar)?.hasPrefix("Active until") == true)
        #expect(schedule.statusText(at: at(2, 18), calendar: calendar)?.hasPrefix("Next: Tue") == true)
        #expect(schedule.statusText(at: at(6, 18), calendar: calendar)?.hasPrefix("Next: Mon") == true)
    }

    @Test("no status text when the schedule is off")
    func statusOff() {
        #expect(WeeklySchedule.default.statusText(at: at(2, 10), calendar: calendar) == nil)
    }
}
