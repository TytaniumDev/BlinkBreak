//
//  WeeklyScheduleTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the WeeklySchedule and DaySchedule data models.
//

import Testing
@testable import BlinkBreakCore

@Suite("WeeklySchedule — data model")
struct WeeklyScheduleTests {

    @Test("WeeklySchedule round-trips through JSON")
    func roundTrip() throws {
        let schedule = WeeklySchedule(
            isEnabled: true,
            days: [
                2: .nineToFive(isEnabled: true),
                7: DaySchedule(isEnabled: false,
                               startTime: DateComponents(hour: 10, minute: 0),
                               endTime: DateComponents(hour: 14, minute: 30))
            ]
        )
        let data = try JSONEncoder().encode(schedule)
        #expect(try JSONDecoder().decode(WeeklySchedule.self, from: data) == schedule)
    }

    @Test("default: master off, Mon–Fri 9–5 enabled, weekend disabled")
    func defaultSchedule() {
        let schedule = WeeklySchedule.default
        #expect(schedule.isEnabled == false)
        for weekday in 2...6 {
            #expect(schedule.day(weekday) == .nineToFive(isEnabled: true))
        }
        for weekday in [1, 7] {
            #expect(schedule.day(weekday) == .nineToFive(isEnabled: false))
        }
    }

    @Test("day(_:) falls back to a disabled 9–5 day")
    func dayFallback() {
        #expect(WeeklySchedule(isEnabled: true, days: [:]).day(3) == .nineToFive(isEnabled: false))
    }

    @Test("settingStart rounds to 5 minutes and pushes the end later when needed")
    func settingStart() {
        let day = DaySchedule.nineToFive(isEnabled: true)

        let earlier = day.settingStart(hour: 8, minute: 37)
        #expect(earlier.startTime == DateComponents(hour: 8, minute: 35))
        #expect(earlier.endTime == DateComponents(hour: 17, minute: 0))

        let pastEnd = day.settingStart(hour: 18, minute: 0)
        #expect(pastEnd.startTime == DateComponents(hour: 18, minute: 0))
        #expect(pastEnd.endTime == DateComponents(hour: 19, minute: 0))
        #expect(pastEnd.hasActiveWindow)

        let lateNight = day.settingStart(hour: 23, minute: 59)
        #expect(lateNight.startTime == DateComponents(hour: 23, minute: 50))
        #expect(lateNight.endTime == DateComponents(hour: 23, minute: 55))
        #expect(lateNight.hasActiveWindow)
    }

    @Test("settingEnd rounds to 5 minutes and stays after the start")
    func settingEnd() {
        let day = DaySchedule.nineToFive(isEnabled: true)
        #expect(day.settingEnd(hour: 12, minute: 14).endTime == DateComponents(hour: 12, minute: 10))
        #expect(day.settingEnd(hour: 8, minute: 0).endTime == DateComponents(hour: 9, minute: 5))
        #expect(day.settingEnd(hour: 23, minute: 59).endTime == DateComponents(hour: 23, minute: 55))
    }

    @Test("minutes and hasActiveWindow")
    func minutes() {
        let day = DaySchedule(
            isEnabled: true,
            startTime: DateComponents(hour: 8, minute: 30),
            endTime: DateComponents(hour: 12, minute: 15)
        )
        #expect(day.startMinutes == 510)
        #expect(day.endMinutes == 735)
        #expect(day.hasActiveWindow)

        var reversed = day
        reversed.endTime = DateComponents(hour: 8, minute: 0)
        #expect(reversed.hasActiveWindow == false)

        var disabled = day
        disabled.isEnabled = false
        #expect(disabled.hasActiveWindow == false)
    }
}
