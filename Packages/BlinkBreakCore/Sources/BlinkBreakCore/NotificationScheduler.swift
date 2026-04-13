//
//  NotificationScheduler.swift
//  BlinkBreakCore
//
//  Protocol abstraction over UNUserNotificationCenter, plus a real implementation
//  that handles the break cascade and a way to cancel notifications by cycleId.
//
//  Why a protocol: SessionController calls this to schedule/cancel notifications,
//  but tests must not touch the real UNUserNotificationCenter. Tests pass a
//  MockNotificationScheduler that just records calls.
//
//  Flutter analogue: think of this as an abstract NotificationRepository with
//  a FirebaseNotificationRepository and a MockNotificationRepository.
//

import Foundation
@preconcurrency import UserNotifications

// MARK: - Public value types

/// A description of a notification to schedule. Platform-neutral — the real scheduler
/// translates it to a UNNotificationRequest, the mock scheduler just records it.
public struct ScheduledNotification: Equatable, Sendable {

    /// The unique identifier for this notification (used for cancellation).
    public let identifier: String

    /// Notification title shown on the banner / Watch face.
    public let title: String

    /// Notification body.
    public let body: String

    /// When the notification should fire, in absolute wall-clock time.
    public let fireDate: Date

    /// Whether this notification should break through Focus modes.
    /// Corresponds to `UNNotificationInterruptionLevel.timeSensitive`.
    public let isTimeSensitive: Bool

    /// Group identifier used to collapse related notifications into a single Notification
    /// Center entry. All notifications for one cycle share a thread ID.
    public let threadIdentifier: String

    /// If non-nil, attaches the given category ID so the notification exposes action buttons.
    public let categoryIdentifier: String?

    /// If non-nil, plays the named custom sound file bundled in the app when the notification
    /// fires. If nil, uses `UNNotificationSound.default`. iOS caps custom notification sounds
    /// at 30 seconds; files longer than that fall back to the default.
    public let soundName: String?

    public init(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        isTimeSensitive: Bool,
        threadIdentifier: String,
        categoryIdentifier: String?,
        soundName: String? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.isTimeSensitive = isTimeSensitive
        self.threadIdentifier = threadIdentifier
        self.categoryIdentifier = categoryIdentifier
        self.soundName = soundName
    }
}

// MARK: - Protocol

/// Schedules and cancels local notifications. SessionController depends on this protocol;
/// the real `UNNotificationScheduler` and test `MockNotificationScheduler` both conform.
public protocol NotificationSchedulerProtocol: Sendable {

    /// Register the notification category with the "Start break" action. Call once at launch.
    func registerCategories()

    /// Schedule a single notification.
    func schedule(_ notification: ScheduledNotification)

    /// Cancel pending and delivered notifications with the given identifiers.
    func cancel(identifiers: [String])

    /// Cancel every pending and delivered notification the app owns.
    func cancelAll()

    /// Return the identifiers of all currently-pending notifications.
    /// Used by reconciliation on launch. Async because UNUserNotificationCenter's API is async.
    func pendingIdentifiers() async -> [String]

    /// Return identifier + fire date for all currently-pending notifications.
    /// Used by DiagnosticCollector for bug reports. Async because UNUserNotificationCenter's
    /// API is async.
    func pendingRequests() async -> [PendingNotificationInfo]
}

// MARK: - Cascade builder

/// Builds the list of `ScheduledNotification`s that make up one break cascade.
///
/// Public so tests can call it directly without going through the scheduler.
public enum CascadeBuilder {

    /// Build the single break notification for one cycle.
    /// - Parameters:
    ///   - cycleId: The UUID identifying this cycle.
    ///   - cycleStartedAt: When the 20-minute countdown began.
    /// - Returns: One ScheduledNotification with the custom alarm sound attached.
    public static func buildBreakNotification(
        cycleId: UUID,
        cycleStartedAt: Date
    ) -> ScheduledNotification {
        ScheduledNotification(
            identifier: BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString,
            title: "Time to look away",
            body: "Tap to start your 20-second break.",
            fireDate: cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval),
            isTimeSensitive: true,
            threadIdentifier: cycleId.uuidString,
            categoryIdentifier: BlinkBreakConstants.breakCategoryId,
            soundName: BlinkBreakConstants.breakSoundFileName
        )
    }

    /// Build the single "done, look back at your screen" notification.
    public static func buildDoneNotification(
        cycleId: UUID,
        breakActiveStartedAt: Date
    ) -> ScheduledNotification {
        ScheduledNotification(
            identifier: BlinkBreakConstants.doneIdPrefix + cycleId.uuidString,
            title: "Back to work",
            body: "Your eyes had a rest. Carry on.",
            fireDate: breakActiveStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration),
            isTimeSensitive: false,
            threadIdentifier: cycleId.uuidString,
            categoryIdentifier: nil
        )
    }

    /// Returns every notification identifier that belongs to a specific cycle.
    /// Used for targeted cancellation — "cancel the notifications for this cycle" translates
    /// into `cancel(identifiers: CascadeBuilder.identifiers(for: cycleId))`.
    public static func identifiers(for cycleId: UUID) -> [String] {
        [
            BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString,
            BlinkBreakConstants.doneIdPrefix + cycleId.uuidString
        ]
    }
}

// MARK: - Real implementation

/// The production implementation of `NotificationSchedulerProtocol`, wrapping
/// `UNUserNotificationCenter.current()`.
///
/// Marked `@unchecked Sendable` because `UNUserNotificationCenter` is thread-safe but
/// hasn't adopted `Sendable` yet in the SDK headers.
public final class UNNotificationScheduler: NotificationSchedulerProtocol, @unchecked Sendable {

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func registerCategories() {
        // The "Start break" action attached to every break-cascade notification.
        // `.foreground` means tapping this action brings the app to the foreground (even
        // though our handler schedules work in the background — .foreground here just means
        // "this is a user-facing UI action", it doesn't require the app to show UI).
        let startBreakAction = UNNotificationAction(
            identifier: BlinkBreakConstants.startBreakActionId,
            title: "Start break",
            options: [.foreground]
        )
        let breakCategory = UNNotificationCategory(
            identifier: BlinkBreakConstants.breakCategoryId,
            actions: [startBreakAction],
            intentIdentifiers: [],
            options: []
        )
        let scheduleAction = UNNotificationAction(
            identifier: BlinkBreakConstants.scheduleStartActionId,
            title: "Open",
            options: [.foreground]
        )
        let scheduleCategory = UNNotificationCategory(
            identifier: BlinkBreakConstants.scheduleCategoryId,
            actions: [scheduleAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([breakCategory, scheduleCategory])
    }

    public func schedule(_ notification: ScheduledNotification) {
        let content = Self.makeContent(for: notification)

        // Fire date is absolute wall-clock; convert to a calendar-based trigger.
        let interval = max(notification.fireDate.timeIntervalSinceNow, 1)  // UN requires > 0
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            if let error = error {
                // We log instead of crashing; scheduling failures are rare enough that we
                // surface them via UI if they happen during a user-initiated mutation.
                print("[BlinkBreakCore] notification schedule failed: \(error)")
            }
        }
    }

    /// Builds the `UNMutableNotificationContent` for a `ScheduledNotification`. Pure
    /// function — no touching of `UNUserNotificationCenter` — so tests can call it
    /// directly to verify the payload the scheduler would submit.
    public static func makeContent(for notification: ScheduledNotification) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = resolveSound(for: notification)
        content.threadIdentifier = notification.threadIdentifier
        if let category = notification.categoryIdentifier {
            content.categoryIdentifier = category
        }
        // .timeSensitive lets the notification punch through Focus modes on iOS 15+ / watchOS 8+.
        if notification.isTimeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        return content
    }

    /// Always returns a non-nil sound so the notification is never accidentally silent.
    /// - iOS with a custom `soundName`: returns that named bundled sound file.
    /// - iOS with `soundName == nil`: returns `.default`. The previous implementation
    ///   left `content.sound` unset in this case, which is how the "Back to work"
    ///   notification ended up delivering with no sound or vibration.
    /// - watchOS: always `.default` (watchOS ignores custom sound files and
    ///   `UNNotificationSound(named:)` is unavailable there).
    private static func resolveSound(for notification: ScheduledNotification) -> UNNotificationSound {
        #if os(iOS)
        if let soundName = notification.soundName {
            return UNNotificationSound(named: UNNotificationSoundName(soundName))
        }
        return .default
        #else
        return .default
        #endif
    }

    public func cancel(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    public func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map { $0.identifier })
            }
        }
    }

    public func pendingRequests() async -> [PendingNotificationInfo] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let infos = requests.map { request in
                    PendingNotificationInfo(
                        identifier: request.identifier,
                        fireDate: (request.trigger as? UNTimeIntervalNotificationTrigger)
                            .flatMap { $0.nextTriggerDate() }
                    )
                }
                continuation.resume(returning: infos)
            }
        }
    }
}
