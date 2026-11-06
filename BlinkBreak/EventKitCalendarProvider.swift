//
//  EventKitCalendarProvider.swift
//  BlinkBreak
//
//  Concrete `CalendarProviderProtocol` backed by EventKit. The only file that
//  imports EventKit; `BlinkBreakCore` stays platform-agnostic.
//
//  EventKit reads every account the user added to the iPhone (iCloud, Google,
//  Exchange, subscribed calendars), so work and personal calendars both work
//  without any sign-in code here.
//
//  Flutter analogue: the platform side of a calendar plugin.
//

import BlinkBreakCore
import EventKit
import Foundation

// `@unchecked Sendable`: EKEventStore isn't marked Sendable, but it's safe to
// read from any thread, and this class only ever reads from it.
final class EventKitCalendarProvider: CalendarProviderProtocol, @unchecked Sendable {

    let changes: AsyncStream<Void>
    private let store: EKEventStore
    private let observer: NSObjectProtocol

    init() {
        let store = EKEventStore()
        self.store = store
        // Only "something changed" matters, so a burst of sync updates collapses to one.
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        self.changes = changes
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: nil
        ) { _ in
            continuation.yield()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - CalendarProviderProtocol

    func accessStatus() async -> CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        // Write-only access can't read events, so it's as good as denied here.
        case .denied, .restricted, .writeOnly: return .denied
        @unknown default: return .denied
        }
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            // A store created before access was granted can keep serving the
            // empty, pre-permission view of the database until it's reset.
            if granted { store.reset() }
            return granted
        } catch {
            AppLogger.shared.log(.error, "calendar access request failed: \(error)")
            return false
        }
    }

    func calendars() async -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, accountTitle: $0.source?.title ?? "") }
            .sorted { ($0.accountTitle, $0.title) < ($1.accountTitle, $1.title) }
    }

    func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.calendarEvent)
    }

    private static func calendarEvent(_ event: EKEvent) -> CalendarEvent {
        let myStatus = event.attendees?.first(where: \.isCurrentUser)?.participantStatus
        return CalendarEvent(
            calendarId: event.calendar?.calendarIdentifier ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isBusy: event.availability != .free,
            isDeclined: event.status == .canceled || myStatus == .declined
        )
    }
}
