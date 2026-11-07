//
//  CalendarEventCache.swift
//  BlinkBreakCore
//
//  The last batch of events a network-backed calendar source fetched, so
//  meetings are still skipped when the fetch fails — for example when an
//  alarm button wakes the app with no network.
//
//  Flutter analogue: a small value type you'd persist with SharedPreferences
//  as a JSON blob, with one query method.
//

import Foundation

public struct CalendarEventCache: Codable, Sendable, Equatable {

    /// The time range that was fetched.
    public let fetchedFrom: Date
    public let fetchedTo: Date
    public let events: [CalendarEvent]

    public init(fetchedFrom: Date, fetchedTo: Date, events: [CalendarEvent]) {
        self.fetchedFrom = fetchedFrom
        self.fetchedTo = fetchedTo
        self.events = events
    }

    /// Cached events that overlap `start..<end`. Only `fetchedFrom..<fetchedTo`
    /// is known; meetings outside it are missing.
    public func events(from start: Date, to end: Date) -> [CalendarEvent] {
        events.filter { $0.start < end && $0.end > start }
    }
}
