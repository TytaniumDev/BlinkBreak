//
//  WeeklySchedule.swift
//  BlinkBreakCore
//
//  Data model for the weekly auto-start/stop schedule. Each day of the week can have
//  an independent start and end time. The master toggle enables/disables the entire
//  schedule without losing per-day configuration.
//
//  Times are stored as DateComponents with .hour and .minute only. Days are keyed by
//  Foundation weekday integers (1 = Sunday, 7 = Saturday) to match Calendar APIs.
//
//  Flutter analogue: a plain Dart data class with fromJson/toJson, stored in SharedPreferences.
//

import Foundation

/// A single day's schedule window: whether the day is active and the start/end times.
public struct DaySchedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var startTime: DateComponents
    public var endTime: DateComponents

    public init(isEnabled: Bool, startTime: DateComponents, endTime: DateComponents) {
        self.isEnabled = isEnabled
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// The full weekly schedule. `isEnabled` is the master toggle; `days` maps Foundation
/// weekday integers (1 = Sunday … 7 = Saturday) to per-day schedules.
public struct WeeklySchedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var days: [Int: DaySchedule]

    public init(isEnabled: Bool, days: [Int: DaySchedule]) {
        self.isEnabled = isEnabled
        self.days = days
    }

    /// Mon-Fri 9 AM – 5 PM enabled, Sat-Sun present but disabled.
    public static let `default`: WeeklySchedule = {
        var days: [Int: DaySchedule] = [:]
        let workday = DaySchedule(
            isEnabled: true,
            startTime: DateComponents(hour: 9, minute: 0),
            endTime: DateComponents(hour: 17, minute: 0)
        )
        let weekend = DaySchedule(
            isEnabled: false,
            startTime: DateComponents(hour: 9, minute: 0),
            endTime: DateComponents(hour: 17, minute: 0)
        )
        for weekday in 2...6 { days[weekday] = workday }
        days[1] = weekend
        days[7] = weekend
        return WeeklySchedule(isEnabled: true, days: days)
    }()

    /// Empty schedule with the master toggle off. Useful as a "scheduling disabled" sentinel.
    public static let empty = WeeklySchedule(isEnabled: false, days: [:])
}
