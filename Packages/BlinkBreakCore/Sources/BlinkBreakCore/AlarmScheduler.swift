//
//  AlarmScheduler.swift
//  BlinkBreakCore
//
//  Protocol abstraction over AlarmKit's AlarmManager. Zero AlarmKit imports
//  here — the concrete iOS-target wrapper imports AlarmKit; the test mock
//  records calls and publishes events on demand.
//
//  The scheduler is deliberately dumb: it schedules, cancels, and reports what
//  the system currently holds. It does not remember which alarm is which —
//  `SessionRecord` already knows the kind of the one alarm a session owns.
//
//  Flutter analogue: an abstract AlarmService with a platform-specific iOS
//  implementation that wraps the AlarmKit channel.
//

import Foundation

/// Which beat of the 20-20-20 cycle an alarm represents. Only affects how the
/// alarm is presented (title, button label).
public enum AlarmKind: String, Sendable, Codable {
    /// The 20-minute "look away now" alarm.
    case breakDue
    /// The 20-second "look-away period is over" alarm.
    case lookAwayDone
}

/// Changes the system reports for alarms this app owns.
public enum AlarmEvent: Sendable, Equatable {
    /// The alarm started alerting (the full-screen alarm UI is up).
    case alerting(alarmId: UUID)
    /// The alarm is gone from the system: the user stopped it, it was
    /// cancelled, or it finished alerting.
    case removed(alarmId: UUID)
}

/// A snapshot of one alarm the system currently holds for this app.
public struct ScheduledAlarm: Sendable, Equatable {
    public let alarmId: UUID
    /// True while the system alarm UI is showing.
    public let isAlerting: Bool

    public init(alarmId: UUID, isAlerting: Bool = false) {
        self.alarmId = alarmId
        self.isAlerting = isAlerting
    }
}

/// Whether the user allows the app to schedule alarms.
public enum AlarmAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

/// Errors the scheduler can raise.
public enum AlarmSchedulerError: Error, Sendable, Equatable {
    /// The user denied alarm permission.
    case authorizationDenied
    /// The underlying scheduler call failed for some other reason.
    case schedulingFailed(reason: String)
    /// Reading the system's alarm list failed. Not the same as "no alarms".
    case listingFailed(reason: String)
}

/// The narrow surface SessionController needs from AlarmKit.
public protocol AlarmSchedulerProtocol: Sendable {

    /// Current authorization. Never prompts the user.
    func authorizationStatus() async -> AlarmAuthorizationStatus

    /// Schedule a one-shot alarm at `fireDate`. Prompts for permission first if
    /// the user hasn't been asked yet.
    /// - Returns: The new alarm's ID.
    /// - Throws: `AlarmSchedulerError`.
    func schedule(_ kind: AlarmKind, at fireDate: Date, muteSound: Bool) async throws -> UUID

    /// Cancel an alarm. Cancelling an unknown ID is a no-op.
    func cancel(alarmId: UUID) async

    /// Every alarm the system currently holds for this app, including ones
    /// scheduled by earlier app launches.
    /// - Throws: `AlarmSchedulerError.listingFailed` when the system can't be
    ///   read. Callers must not treat a failed read as an empty list.
    func currentAlarms() async throws -> [ScheduledAlarm]

    /// Alarm lifecycle changes. SessionController is the only subscriber.
    var events: AsyncStream<AlarmEvent> { get }
}
