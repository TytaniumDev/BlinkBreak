//
//  WeeklyScheduleTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the WeeklySchedule and DaySchedule data models: JSON round-trips,
//  default schedule (Mon-Fri 9-5), and empty schedule (master toggle off).
//
//  Written in Swift Testing (the `import Testing` framework), not legacy XCTest.
//

import Testing
import Foundation
@testable import BlinkBreakCore

@Suite("WeeklySchedule — data model")
struct WeeklyScheduleTests {

    @Test("DaySchedule round-trips through JSON")
    func dayScheduleRoundTrip() throws {
        let day = DaySchedule(
            isEnabled: true,
            startTime: DateComponents(hour: 9, minute: 0),
            endTime: DateComponents(hour: 17, minute: 30)
        )
        let data = try JSONEncoder().encode(day)
        let decoded = try JSONDecoder().decode(DaySchedule.self, from: data)
        #expect(decoded == day)
    }

    @Test("WeeklySchedule round-trips through JSON")
    func weeklyScheduleRoundTrip() throws {
        let schedule = WeeklySchedule(
            isEnabled: true,
            days: [
                2: DaySchedule(isEnabled: true,
                               startTime: DateComponents(hour: 9, minute: 0),
                               endTime: DateComponents(hour: 17, minute: 0)),
                7: DaySchedule(isEnabled: false,
                               startTime: DateComponents(hour: 10, minute: 0),
                               endTime: DateComponents(hour: 14, minute: 0))
            ]
        )
        let data = try JSONEncoder().encode(schedule)
        let decoded = try JSONDecoder().decode(WeeklySchedule.self, from: data)
        #expect(decoded == schedule)
    }

    @Test("WeeklySchedule.default has Mon-Fri 9-5 enabled, Sat-Sun disabled")
    func defaultSchedule() {
        let schedule = WeeklySchedule.default
        #expect(schedule.isEnabled == true)
        for weekday in 2...6 {
            let day = schedule.days[weekday]
            #expect(day != nil)
            #expect(day?.isEnabled == true)
            #expect(day?.startTime.hour == 9)
            #expect(day?.startTime.minute == 0)
            #expect(day?.endTime.hour == 17)
            #expect(day?.endTime.minute == 0)
        }
        for weekday in [1, 7] {
            let day = schedule.days[weekday]
            #expect(day != nil)
            #expect(day?.isEnabled == false)
        }
    }

    @Test("WeeklySchedule.empty has master toggle off")
    func emptySchedule() {
        let schedule = WeeklySchedule.empty
        #expect(schedule.isEnabled == false)
    }
}
