//
//  GoogleCalendarAPI.swift
//  BlinkBreak
//
//  The two Google Calendar REST calls BlinkBreak makes, as plain request
//  builders and response decoders (no networking here):
//
//  - `calendarList.list`: which calendars the signed-in account can see,
//    including calendars shared with it as free/busy only.
//  - `freeBusy.query`: when those calendars are busy. Free/busy is all a
//    shared work calendar exposes, and all meeting skipping needs.
//
//  Flutter analogue: the request/response half of a REST client class,
//  with `fromJson` factories.
//

import BlinkBreakCore
import Foundation

enum GoogleCalendarAPI {

    /// The OAuth scopes requested at sign-in. Read-only: the calendar list and busy times.
    static let scopes = [
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
        "https://www.googleapis.com/auth/calendar.freebusy"
    ]

    /// `freeBusy.query` accepts at most this many calendars per request.
    static let maxCalendarsPerQuery = 50

    private static let baseURL = URL(string: "https://www.googleapis.com/calendar/v3")!
    private static let timeout: TimeInterval = 10

    // MARK: - Requests

    static func calendarListRequest(accessToken: String) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appending(path: "users/me/calendarList"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "minAccessRole", value: "freeBusyReader"),
            URLQueryItem(name: "maxResults", value: "250")
        ]
        return request(url: components.url!, accessToken: accessToken)
    }

    static func freeBusyRequest(calendarIds: [String], from start: Date, to end: Date, accessToken: String) throws -> URLRequest {
        var request = request(url: baseURL.appending(path: "freeBusy"), accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(FreeBusyQuery(
            timeMin: formatter.string(from: start),
            timeMax: formatter.string(from: end),
            items: calendarIds.map { FreeBusyQuery.Item(id: $0) }
        ))
        return request
    }

    // MARK: - Responses

    /// - Parameter accountEmail: Shown as the calendars' account in the picker.
    static func decodeCalendars(_ data: Data, accountEmail: String) throws -> [CalendarInfo] {
        try JSONDecoder().decode(CalendarListResponse.self, from: data).items
            .filter { $0.deleted != true }
            .map { CalendarInfo(id: $0.id, title: $0.summaryOverride ?? $0.summary ?? $0.id, accountTitle: "Google · \(accountEmail)") }
    }

    /// Busy blocks as events. Calendars Google couldn't read report errors and
    /// no busy times, so they're simply skipped.
    static func decodeBusyTimes(_ data: Data) throws -> [CalendarEvent] {
        let response = try JSONDecoder().decode(FreeBusyResponse.self, from: data)
        return response.calendars.flatMap { calendarId, calendar in
            (calendar.busy ?? []).compactMap { block -> CalendarEvent? in
                guard let start = parseDate(block.start), let end = parseDate(block.end) else { return nil }
                return CalendarEvent(calendarId: calendarId, start: start, end: end)
            }
        }
    }

    // MARK: - Private

    private static func request(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// RFC 3339, the format Google uses for times.
    private static var formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func parseDate(_ string: String) -> Date? {
        if let date = formatter.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }

    private struct FreeBusyQuery: Encodable {
        struct Item: Encodable { let id: String }
        let timeMin: String
        let timeMax: String
        let items: [Item]
    }

    private struct CalendarListResponse: Decodable {
        struct Entry: Decodable {
            let id: String
            let summary: String?
            let summaryOverride: String?
            let deleted: Bool?
        }
        let items: [Entry]
    }

    private struct FreeBusyResponse: Decodable {
        struct Calendar: Decodable {
            struct Block: Decodable {
                let start: String
                let end: String
            }
            let busy: [Block]?
        }
        let calendars: [String: Calendar]
    }
}
