//
//  WeeklySchedule.swift
//  BlinkBreakCore
//
//  Data model for the weekly auto-start/stop schedule. Each day of the week can have
//  an independent start and end time. The schedule toggle enables/disables the entire
//  schedule without losing per-day configuration.
//
//  Days are keyed by `Weekday`, an enum whose raw values match Foundation's
//  Calendar.component(.weekday) numbering (1 = Sunday … 7 = Saturday).
//  Times are stored as DateComponents with .hour and .minute only.
//
//  Flutter analogue: a plain Dart data class with fromJson/toJson, stored in SharedPreferences.
//

import Foundation

/// Days of the week, keyed to Foundation's `Calendar.component(.weekday, from:)` values.
public enum Weekday: Int, Codable, Sendable, CaseIterable, Hashable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    /// Resolve from Calendar's raw weekday integer (1...7). Returns nil for out-of-range values.
    public init?(calendarWeekday: Int) {
        self.init(rawValue: calendarWeekday)
    }
}

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

/// The full weekly schedule. `isEnabled` is the schedule toggle; `days` maps each
/// `Weekday` to its per-day schedule.
public struct WeeklySchedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var days: [Weekday: DaySchedule]

    public init(isEnabled: Bool, days: [Weekday: DaySchedule]) {
        self.isEnabled = isEnabled
        self.days = days
    }

    /// Mon-Fri 9 AM – 5 PM enabled, Sat-Sun present but disabled.
    public static let `default`: WeeklySchedule = {
        var days: [Weekday: DaySchedule] = [:]
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
        for weekday: Weekday in [.monday, .tuesday, .wednesday, .thursday, .friday] {
            days[weekday] = workday
        }
        days[.sunday] = weekend
        days[.saturday] = weekend
        return WeeklySchedule(isEnabled: true, days: days)
    }()

    /// Empty schedule with the schedule toggle off. Useful as a "scheduling disabled" sentinel.
    public static let empty = WeeklySchedule(isEnabled: false, days: [:])
}
