//
//  ScheduleEvaluatorTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the pure schedule evaluation logic.
//

import Testing
import Foundation
@testable import BlinkBreakCore

@Suite("ScheduleEvaluator — shouldBeActive")
struct ScheduleEvaluatorShouldBeActiveTests {

    let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        return cal
    }()

    /// 2026-04-05 is Sunday (weekday 1), 2026-04-06 is Monday (weekday 2), etc.
    func date(weekday: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4
        comps.day = 5 + (weekday - 1)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return calendar.date(from: comps)!
    }

    func evaluator(schedule: WeeklySchedule) -> ScheduleEvaluator {
        ScheduleEvaluator(schedule: { schedule })
    }

    @Test("Returns false when master toggle is off")
    func masterToggleOff() {
        var schedule = WeeklySchedule.default
        schedule.isEnabled = false
        let eval = evaluator(schedule: schedule)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 10, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == false)
    }

    @Test("Returns false for a disabled day")
    func disabledDay() {
        let eval = evaluator(schedule: .default)
        #expect(eval.shouldBeActive(at: date(weekday: 7, hour: 10, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == false)
    }

    @Test("Returns true within a day's window")
    func withinWindow() {
        let eval = evaluator(schedule: .default)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 12, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == true)
    }

    @Test("Returns true at exactly the start time")
    func exactlyAtStart() {
        let eval = evaluator(schedule: .default)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 9, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == true)
    }

    @Test("Returns false at exactly the end time (exclusive)")
    func exactlyAtEnd() {
        let eval = evaluator(schedule: .default)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 17, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == false)
    }

    @Test("Returns false before the start time")
    func beforeStart() {
        let eval = evaluator(schedule: .default)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 8, minute: 59),
                                     manualStopDate: nil, calendar: calendar) == false)
    }

    @Test("Returns false after the end time")
    func afterEnd() {
        let eval = evaluator(schedule: .default)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 17, minute: 1),
                                     manualStopDate: nil, calendar: calendar) == false)
    }

    @Test("Returns false when manualStopDate is within today's window")
    func manualStopOverride() {
        let eval = evaluator(schedule: .default)
        let stopDate = date(weekday: 2, hour: 14, minute: 0)
        let checkDate = date(weekday: 2, hour: 15, minute: 0)
        #expect(eval.shouldBeActive(at: checkDate, manualStopDate: stopDate,
                                     calendar: calendar) == false)
    }

    @Test("manualStopDate from yesterday is ignored")
    func manualStopYesterdayIgnored() {
        let eval = evaluator(schedule: .default)
        let stopDate = date(weekday: 2, hour: 14, minute: 0)
        let checkDate = date(weekday: 3, hour: 10, minute: 0)
        #expect(eval.shouldBeActive(at: checkDate, manualStopDate: stopDate,
                                     calendar: calendar) == true)
    }

    @Test("manualStopDate outside today's window is ignored")
    func manualStopOutsideWindowIgnored() {
        let eval = evaluator(schedule: .default)
        let stopDate = date(weekday: 2, hour: 7, minute: 0)
        let checkDate = date(weekday: 2, hour: 10, minute: 0)
        #expect(eval.shouldBeActive(at: checkDate, manualStopDate: stopDate,
                                     calendar: calendar) == true)
    }

    @Test("Returns false when day has no entry in schedule")
    func missingDayEntry() {
        let schedule = WeeklySchedule(isEnabled: true, days: [:])
        let eval = evaluator(schedule: schedule)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 10, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == false)
    }
}

@Suite("ScheduleEvaluator — nextTransitionDate")
struct ScheduleEvaluatorNextTransitionTests {

    let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        return cal
    }()

    func date(weekday: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4
        comps.day = 5 + (weekday - 1)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return calendar.date(from: comps)!
    }

    func absoluteDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return calendar.date(from: comps)!
    }

    func evaluator(schedule: WeeklySchedule) -> ScheduleEvaluator {
        ScheduleEvaluator(schedule: { schedule })
    }

    @Test("Finds next start when before today's window")
    func nextStartBeforeWindow() {
        let eval = evaluator(schedule: .default)
        let from = date(weekday: 2, hour: 7, minute: 0)
        let next = eval.nextTransitionDate(from: from, calendar: calendar)
        #expect(next == date(weekday: 2, hour: 9, minute: 0))
    }

    @Test("Finds next end when inside today's window")
    func nextEndInsideWindow() {
        let eval = evaluator(schedule: .default)
        let from = date(weekday: 2, hour: 12, minute: 0)
        let next = eval.nextTransitionDate(from: from, calendar: calendar)
        #expect(next == date(weekday: 2, hour: 17, minute: 0))
    }

    @Test("Skips disabled days to find next enabled start")
    func skipsDisabledDays() {
        let eval = evaluator(schedule: .default)
        let from = date(weekday: 6, hour: 18, minute: 0) // Fri April 10, 6pm
        let next = eval.nextTransitionDate(from: from, calendar: calendar)
        #expect(next == absoluteDate(year: 2026, month: 4, day: 13, hour: 9, minute: 0))
    }

    @Test("Returns nil when no days are enabled")
    func noDaysEnabled() {
        let schedule = WeeklySchedule(isEnabled: true, days: [:])
        let eval = evaluator(schedule: schedule)
        #expect(eval.nextTransitionDate(from: date(weekday: 2, hour: 10, minute: 0),
                                         calendar: calendar) == nil)
    }

    @Test("Returns nil when master toggle is off")
    func masterToggleOff() {
        var schedule = WeeklySchedule.default
        schedule.isEnabled = false
        let eval = evaluator(schedule: schedule)
        #expect(eval.nextTransitionDate(from: date(weekday: 2, hour: 10, minute: 0),
                                         calendar: calendar) == nil)
    }
}
