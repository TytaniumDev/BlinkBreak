//
//  CompositeCalendarProvider.swift
//  BlinkBreakCore
//
//  Presents several calendar sources (the iPhone's calendars, a Google
//  account) to SessionController as one. Events and calendars are combined;
//  a change in any source is a change.
//
//  Flutter analogue: a repository that merges several data sources, with
//  `StreamGroup.merge` for their change streams.
//

import Foundation

public struct CompositeCalendarProvider: CalendarProviderProtocol {

    private let providers: [CalendarProviderProtocol]
    public let changes: AsyncStream<Void>

    public init(_ providers: [CalendarProviderProtocol]) {
        self.providers = providers
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        self.changes = changes
        let sources = providers.map(\.changes)
        let forwarding = Task {
            await withTaskGroup(of: Void.self) { group in
                for source in sources {
                    group.addTask {
                        for await _ in source {
                            continuation.yield()
                        }
                    }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in forwarding.cancel() }
    }

    /// Authorized if any source is; otherwise denied if any source is.
    public func accessStatus() async -> CalendarAccessStatus {
        var statuses: [CalendarAccessStatus] = []
        for provider in providers {
            statuses.append(await provider.accessStatus())
        }
        if statuses.contains(.authorized) { return .authorized }
        if statuses.contains(.denied) { return .denied }
        return .notDetermined
    }

    /// Asks each source in turn (so system prompts never overlap). Granted if any source grants.
    public func requestAccess() async -> Bool {
        var granted = false
        for provider in providers {
            if await provider.requestAccess() {
                granted = true
            }
        }
        return granted
    }

    public func calendars() async -> [CalendarInfo] {
        var calendars: [CalendarInfo] = []
        for provider in providers {
            calendars += await provider.calendars()
        }
        return calendars
    }

    /// Reads every source at once, since some go over the network.
    public func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        await withTaskGroup(of: [CalendarEvent].self) { group in
            for provider in providers {
                group.addTask { await provider.events(from: start, to: end) }
            }
            var events: [CalendarEvent] = []
            for await batch in group {
                events += batch
            }
            return events
        }
    }
}
