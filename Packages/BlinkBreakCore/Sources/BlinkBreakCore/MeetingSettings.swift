//
//  MeetingSettings.swift
//  BlinkBreakCore
//
//  The "skip breaks during meetings" preference, and the rule for which
//  calendar events count as meetings.
//
//  Flutter analogue: a small immutable settings model with a `copyWith`-style
//  mutable copy, plus a pure predicate method.
//

import Foundation

public struct MeetingSettings: Codable, Sendable, Equatable {

    /// Whether break alarms that land in a meeting are skipped.
    public var isEnabled: Bool

    /// Calendars the user turned off. Stored as exclusions so calendars added
    /// later count by default.
    public var excludedCalendarIds: Set<String>

    public init(isEnabled: Bool = false, excludedCalendarIds: Set<String> = []) {
        self.isEnabled = isEnabled
        self.excludedCalendarIds = excludedCalendarIds
    }

    public static let `default` = MeetingSettings()

    /// A meeting is a timed event that blocks time (not Free), that the user
    /// hasn't declined, on a calendar they haven't excluded. All-day events
    /// (holidays, birthdays, out-of-office days) never count.
    public func isMeeting(_ event: CalendarEvent) -> Bool {
        !event.isAllDay
            && event.isBusy
            && !event.isDeclined
            && event.end > event.start
            && !excludedCalendarIds.contains(event.calendarId)
    }
}
