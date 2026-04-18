//
//  AlarmScheduler.swift
//  BlinkBreakCore
//
//  Protocol abstraction over AlarmKit's AlarmManager. Zero AlarmKit imports
//  here — concrete iOS-target wrapper imports AlarmKit; mock impl for tests
//  publishes events synchronously.
//
//  SessionController depends on this protocol, not on AlarmKit directly.
//
//  Flutter analogue: an abstract AlarmService with a platform-specific iOS
//  implementation that wraps the AlarmKit channel.
//

import Foundation

/// Which beat of the 20-20-20 cycle this alarm represents.
public enum AlarmKind: String, Sendable, Codable {
    /// The 20-minute "look away now" alarm.
    case breakDue
    /// The 20-second "look-away period is over" alarm.
    case lookAwayDone
}

/// Events emitted by the alarm scheduler. Sent on the `events` AsyncStream so
/// SessionController can react to system-driven state transitions (alarm fired,
/// user dismissed) without polling.
public enum AlarmEvent: Sendable, Equatable {
    /// The alarm fired and is now showing the alert UI to the user.
    case fired(alarmId: UUID, kind: AlarmKind)
    /// The user acknowledged the alarm (tapped Stop) or it was cancelled.
    case dismissed(alarmId: UUID, kind: AlarmKind)
}

/// A snapshot of an alarm currently scheduled with the system.
/// Returned from `currentAlarms()` for reconciliation after app kill.
public struct ScheduledAlarmInfo: Sendable, Equatable {
    public let alarmId: UUID
    public let kind: AlarmKind
    /// True when this alarm is currently showing the system alert UI (the user
    /// hasn't dismissed it yet). Reconciliation uses this to distinguish "scheduled
    /// for later" from "firing right now."
    public let isAlerting: Bool

    public init(alarmId: UUID, kind: AlarmKind, isAlerting: Bool = false) {
        self.alarmId = alarmId
        self.kind = kind
        self.isAlerting = isAlerting
    }
}

/// Errors the scheduler can raise.
public enum AlarmSchedulerError: Error, Sendable, Equatable {
    /// User denied alarm permission; scheduler can't function until granted.
    case authorizationDenied
    /// Underlying scheduler call failed for some other reason.
    case schedulingFailed(reason: String)
}

/// The narrow surface SessionController needs from AlarmKit.
///
/// `AnyObject` because the iOS implementation holds an internal `AsyncStream`
/// continuation that must persist across calls. The mock is a class for the same
/// reason. `Sendable` because SessionController's main-actor `init` spins up a
/// `Task { for await event in alarmScheduler.events { ... } }` that crosses
/// actor isolation boundaries.
public protocol AlarmSchedulerProtocol: AnyObject, Sendable {

    /// Request user permission for alarms. Returns `true` if granted (or already
    /// granted). Idempotent — safe to call on every app launch.
    func requestAuthorizationIfNeeded() async throws -> Bool

    /// Schedule a countdown alarm that fires after `duration` seconds.
    /// Returns the UUID assigned to the new alarm (callers should persist this
    /// for cancellation and event-correlation).
    /// - Parameter muteSound: When true, the alarm fires silently (full-screen UI
    ///   still appears, no audio). Uses the bundled silent CAF file.
    func scheduleCountdown(duration: TimeInterval, kind: AlarmKind, muteSound: Bool) async throws -> UUID

    /// Cancel a specific alarm by ID. Idempotent — cancelling an unknown ID is a no-op.
    func cancel(alarmId: UUID) async

    /// Cancel every alarm this scheduler has scheduled. Used when the session stops.
    func cancelAll() async

    /// Snapshot the currently-scheduled alarms. Used for reconciliation on launch.
    func currentAlarms() async -> [ScheduledAlarmInfo]

    /// AsyncStream of fired/dismissed events. SessionController subscribes once at init.
    var events: AsyncStream<AlarmEvent> { get }
}
