//
//  MockNotificationScheduler.swift
//  BlinkBreakCoreTests
//
//  A test-only NotificationSchedulerProtocol that records every call instead of
//  touching UNUserNotificationCenter. Tests inspect the recorded calls to verify
//  behavior.
//

@testable import BlinkBreakCore

/// Records calls for assertion and returns stubbed pending identifiers.
final class MockNotificationScheduler: NotificationSchedulerProtocol, @unchecked Sendable {

    // MARK: - Recorded calls

    private let lock = NSLock()
    private(set) var scheduledNotifications: [ScheduledNotification] = []
    private(set) var cancelledIdentifiers: [[String]] = []
    private(set) var cancelAllCount: Int = 0
    private(set) var registerCategoriesCount: Int = 0

    /// Controls what `pendingIdentifiers()` returns. Tests can set this to simulate
    /// different reconciliation scenarios.
    var stubPendingIdentifiers: [String] = []

    // MARK: - NotificationSchedulerProtocol

    func registerCategories() {
        lock.lock()
        defer { lock.unlock() }
        registerCategoriesCount += 1
    }

    func schedule(_ notification: ScheduledNotification) {
        lock.lock()
        defer { lock.unlock() }
        scheduledNotifications.append(notification)
    }

    func cancel(identifiers: [String]) {
        lock.lock()
        defer { lock.unlock() }
        cancelledIdentifiers.append(identifiers)

        // Also remove any scheduled notifications with matching identifiers, so that
        // subsequent `scheduledNotifications` reads reflect the effective state after
        // cancellation — mirrors how the real UN API behaves.
        let set = Set(identifiers)
        scheduledNotifications.removeAll { set.contains($0.identifier) }

        // And mirror removal from stubPendingIdentifiers so reconcile sees the
        // post-cancellation state.
        stubPendingIdentifiers.removeAll { set.contains($0) }
    }

    func cancelAll() {
        lock.lock()
        defer { lock.unlock() }
        cancelAllCount += 1
        scheduledNotifications.removeAll()
        stubPendingIdentifiers.removeAll()
    }

    func pendingIdentifiers() async -> [String] {
        lock.lock()
        defer { lock.unlock() }
        // If the test set stubPendingIdentifiers explicitly, return that.
        // Otherwise, derive from scheduled notifications.
        if !stubPendingIdentifiers.isEmpty {
            return stubPendingIdentifiers
        }
        return scheduledNotifications.map { $0.identifier }
    }

    func pendingRequests() async -> [PendingNotificationInfo] {
        lock.lock()
        defer { lock.unlock() }
        return scheduledNotifications.map {
            PendingNotificationInfo(identifier: $0.identifier, fireDate: $0.fireDate)
        }
    }

    // MARK: - Test helpers

    /// The last set of identifiers passed to `cancel(identifiers:)`, or `nil` if never called.
    var lastCancelledIdentifiers: [String]? {
        lock.lock()
        defer { lock.unlock() }
        return cancelledIdentifiers.last
    }

    /// Reset all recorded state. Useful between test phases within one test.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        scheduledNotifications.removeAll()
        cancelledIdentifiers.removeAll()
        cancelAllCount = 0
        registerCategoriesCount = 0
        stubPendingIdentifiers.removeAll()
    }
}
