//
//  MockCalendarProvider.swift
//  BlinkBreakCoreTests
//
//  Test double for CalendarProviderProtocol. Holds an in-memory list of
//  events so tests can:
//  - Add meetings (`addEvent`) and announce a calendar change (`simulateChange`).
//  - Stub the access status and how the permission prompt is answered.
//

import Foundation
import Synchronization
@testable import BlinkBreakCore

final class MockCalendarProvider: CalendarProviderProtocol {

    private struct Storage {
        var events: [CalendarEvent] = []
        var calendars: [CalendarInfo] = []
        var status: CalendarAccessStatus = .authorized
        var grantsOnRequest = true
        var requestCount = 0
    }

    private let storage = Mutex(Storage())
    private let continuation: AsyncStream<Void>.Continuation
    let changes: AsyncStream<Void>

    init() {
        (changes, continuation) = AsyncStream.makeStream()
    }

    // MARK: - Inspection

    var requestCount: Int { storage.withLock { $0.requestCount } }

    // MARK: - Stubbing

    func addEvent(_ event: CalendarEvent) {
        storage.withLock { $0.events.append(event) }
    }

    func setCalendars(_ calendars: [CalendarInfo]) {
        storage.withLock { $0.calendars = calendars }
    }

    /// `grantsOnRequest` is how the user answers the prompt when status is `.notDetermined`.
    func stubAccess(_ status: CalendarAccessStatus, grantsOnRequest: Bool = true) {
        storage.withLock {
            $0.status = status
            $0.grantsOnRequest = grantsOnRequest
        }
    }

    func simulateChange() {
        continuation.yield()
    }

    // MARK: - CalendarProviderProtocol

    func accessStatus() async -> CalendarAccessStatus {
        storage.withLock { $0.status }
    }

    func requestAccess() async -> Bool {
        storage.withLock { storage in
            storage.requestCount += 1
            if storage.status == .notDetermined {
                storage.status = storage.grantsOnRequest ? .authorized : .denied
            }
            return storage.status == .authorized
        }
    }

    func calendars() async -> [CalendarInfo] {
        storage.withLock { $0.status == .authorized ? $0.calendars : [] }
    }

    func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        storage.withLock { storage in
            guard storage.status == .authorized else { return [] }
            return storage.events.filter { $0.start < end && $0.end > start }
        }
    }
}
