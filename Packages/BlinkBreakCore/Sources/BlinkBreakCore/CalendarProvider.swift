//
//  CalendarProvider.swift
//  BlinkBreakCore
//
//  Protocol abstraction over the device calendar (EventKit). Zero EventKit
//  imports here — the concrete iOS-target wrapper imports EventKit; the test
//  mock returns canned events.
//
//  Like the alarm scheduler, the provider is deliberately dumb: it reports raw
//  events. Which of them count as meetings is decided in `MeetingSettings`, so
//  that rule is unit-tested.
//
//  Flutter analogue: an abstract CalendarService with a platform-specific iOS
//  implementation (the `device_calendar` plugin's role).
//

import Foundation

/// One event on one of the user's calendars, as the system reports it.
public struct CalendarEvent: Sendable, Equatable {
    public let calendarId: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    /// False when the event is marked Free (it doesn't block time).
    public let isBusy: Bool
    /// True when the user declined the invitation, or the event was cancelled.
    public let isDeclined: Bool

    public init(
        calendarId: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        isBusy: Bool = true,
        isDeclined: Bool = false
    ) {
        self.calendarId = calendarId
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isBusy = isBusy
        self.isDeclined = isDeclined
    }
}

/// A calendar the user can include or exclude.
public struct CalendarInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// The account it belongs to, e.g. "iCloud" or "name@gmail.com".
    public let accountTitle: String

    public init(id: String, title: String, accountTitle: String) {
        self.id = id
        self.title = title
        self.accountTitle = accountTitle
    }
}

/// Whether the user allows the app to read their calendars.
public enum CalendarAccessStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

/// The narrow surface SessionController needs from the device calendar.
public protocol CalendarProviderProtocol: Sendable {

    /// Current access. Never prompts the user.
    func accessStatus() async -> CalendarAccessStatus

    /// Prompt for access if the user hasn't been asked yet.
    /// - Returns: Whether access is granted.
    func requestAccess() async -> Bool

    /// Every calendar that holds events.
    func calendars() async -> [CalendarInfo]

    /// Events that overlap `start..<end`, across all calendars. Empty without access.
    func events(from start: Date, to end: Date) async -> [CalendarEvent]

    /// Fires whenever the calendar database changes (an event is added, moved,
    /// or synced in). SessionController is the only subscriber.
    var changes: AsyncStream<Void> { get }
}
