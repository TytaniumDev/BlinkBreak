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
//  A window never crosses midnight: the end time must be after the start time.
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

    /// 9 AM – 5 PM, with the given enabled flag.
    public static func nineToFive(isEnabled: Bool) -> DaySchedule {
        DaySchedule(
            isEnabled: isEnabled,
            startTime: DateComponents(hour: 9, minute: 0),
            endTime: DateComponents(hour: 17, minute: 0)
        )
    }

    /// Minutes after midnight for the start time.
    public var startMinutes: Int { Self.minutes(startTime) }

    /// Minutes after midnight for the end time.
    public var endMinutes: Int { Self.minutes(endTime) }

    /// True when the day is enabled and its window has a positive length.
    public var hasActiveWindow: Bool { isEnabled && endMinutes > startMinutes }

    /// A copy with a new start time, rounded down to 5 minutes. Pushes the end
    /// time later if needed so the window stays at least 5 minutes long.
    public func settingStart(hour: Int, minute: Int) -> DaySchedule {
        let start = min(Self.roundedToStep(hour * 60 + minute), Self.lastMinute - Self.step)
        var copy = self
        copy.startTime = Self.components(start)
        if endMinutes <= start {
            copy.endTime = Self.components(min(start + 60, Self.lastMinute))
        }
        return copy
    }

    /// A copy with a new end time, rounded down to 5 minutes and kept at least
    /// 5 minutes after the start time.
    public func settingEnd(hour: Int, minute: Int) -> DaySchedule {
        let end = max(Self.roundedToStep(hour * 60 + minute), startMinutes + Self.step)
        var copy = self
        copy.endTime = Self.components(min(end, Self.lastMinute))
        return copy
    }

    private static let step = 5
    /// 23:55 — the latest selectable time on a 5-minute grid.
    private static let lastMinute = 24 * 60 - step

    private static func roundedToStep(_ minutes: Int) -> Int {
        minutes / step * step
    }

    private static func components(_ minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    private static func minutes(_ components: DateComponents) -> Int {
        (components.hour ?? 0) * 60 + (components.minute ?? 0)
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

    /// The schedule for `weekday`, or a disabled 9–5 day if none is stored.
    public func day(_ weekday: Int) -> DaySchedule {
        days[weekday] ?? .nineToFive(isEnabled: false)
    }

    /// What new users get: master toggle off, Mon–Fri 9 AM – 5 PM ready to go.
    public static let `default`: WeeklySchedule = {
        var days: [Int: DaySchedule] = [:]
        for weekday in 1...7 {
            days[weekday] = .nineToFive(isEnabled: (2...6).contains(weekday))
        }
        return WeeklySchedule(isEnabled: false, days: days)
    }()
}
