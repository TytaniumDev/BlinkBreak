//
//  GoogleCalendarProvider.swift
//  BlinkBreak
//
//  `CalendarProviderProtocol` backed by the Google Calendar API. Reads busy
//  times (free/busy) for every calendar the connected Google account can see,
//  including a work calendar shared with it as free/busy only.
//
//  Network failures fall back to the last successful results, kept in
//  UserDefaults, so an alarm button tapped with no network still skips
//  meetings fetched earlier.
//
//  Flutter analogue: a repository that calls a REST client and caches the
//  last response in SharedPreferences.
//

import BlinkBreakCore
import Foundation

final class GoogleCalendarProvider: CalendarProviderProtocol {

    let changes: AsyncStream<Void>
    private let account: GoogleCalendarAccount
    private let session: URLSession
    private let cache: GoogleCalendarCache

    /// Each fetch covers at least this much, so the cache is useful offline.
    private static let minimumFetchSpan: TimeInterval = 24 * 60 * 60

    init(account: GoogleCalendarAccount, session: URLSession = .shared, cache: GoogleCalendarCache = GoogleCalendarCache()) {
        self.account = account
        self.session = session
        self.cache = cache
        self.changes = account.changes
    }

    // MARK: - CalendarProviderProtocol

    /// Connecting happens through the "Connect" button, not a system prompt.
    func accessStatus() async -> CalendarAccessStatus {
        await account.isConnected ? .authorized : .notDetermined
    }

    func requestAccess() async -> Bool {
        await account.isConnected
    }

    func calendars() async -> [CalendarInfo] {
        guard let token = await account.accessToken(), let email = await account.email else {
            return await account.isConnected ? cache.calendars : []
        }
        do {
            let (data, _) = try await session.data(for: GoogleCalendarAPI.calendarListRequest(accessToken: token))
            let calendars = try GoogleCalendarAPI.decodeCalendars(data, accountEmail: email)
            cache.calendars = calendars
            return calendars
        } catch {
            AppLogger.shared.log(.warning, "google: calendar list failed: \(error)")
            return cache.calendars
        }
    }

    func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        guard await account.isConnected else {
            cache.clear()
            return []
        }
        let fetchEnd = max(end, start.addingTimeInterval(Self.minimumFetchSpan))
        do {
            let events = try await fetchBusyTimes(from: start, to: fetchEnd)
            cache.events = CalendarEventCache(fetchedFrom: start, fetchedTo: fetchEnd, events: events)
            return events.filter { $0.start < end && $0.end > start }
        } catch {
            AppLogger.shared.log(.warning, "google: busy times failed, using cache: \(error)")
            return cache.events?.events(from: start, to: end) ?? []
        }
    }

    // MARK: - Private

    private func fetchBusyTimes(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        guard let token = await account.accessToken() else { throw URLError(.userAuthenticationRequired) }
        var calendarIds = cache.calendars.map(\.id)
        if calendarIds.isEmpty {
            calendarIds = await calendars().map(\.id)
        }
        var events: [CalendarEvent] = []
        for offset in stride(from: 0, to: calendarIds.count, by: GoogleCalendarAPI.maxCalendarsPerQuery) {
            let batch = Array(calendarIds[offset..<min(offset + GoogleCalendarAPI.maxCalendarsPerQuery, calendarIds.count)])
            let request = try GoogleCalendarAPI.freeBusyRequest(calendarIds: batch, from: start, to: end, accessToken: token)
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            events += try GoogleCalendarAPI.decodeBusyTimes(data)
        }
        return events
    }
}

/// The Google calendar list and last busy times, persisted for offline use.
struct GoogleCalendarCache: Sendable {

    private enum Key {
        static let calendars = "BlinkBreak.GoogleCalendar.Calendars"
        static let events = "BlinkBreak.GoogleCalendar.Events"
    }

    // UserDefaults is documented as thread-safe but isn't marked Sendable in the SDK.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var calendars: [CalendarInfo] {
        get { decode([CalendarInfo].self, forKey: Key.calendars) ?? [] }
        nonmutating set { encode(newValue, forKey: Key.calendars) }
    }

    var events: CalendarEventCache? {
        get { decode(CalendarEventCache.self, forKey: Key.events) }
        nonmutating set { encode(newValue, forKey: Key.events) }
    }

    func clear() {
        defaults.removeObject(forKey: Key.calendars)
        defaults.removeObject(forKey: Key.events)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
