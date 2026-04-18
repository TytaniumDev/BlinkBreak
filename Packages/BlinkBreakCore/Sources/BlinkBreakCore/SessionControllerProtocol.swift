//
//  SessionControllerProtocol.swift
//  BlinkBreakCore
//
//  The view-facing protocol for the session controller. Views depend on this protocol,
//  not on the concrete SessionController class. This gives us:
//
//  - PreviewSessionController (in the app target) for SwiftUI previews without real timers.
//  - MockSessionController (in tests) for any view-level testing we ever add.
//  - A hard boundary: a view cannot accidentally call scheduler or persistence methods
//    because the protocol doesn't expose them.
//
//  Flutter analogue: think of this as an abstract class that a ChangeNotifier implements,
//  consumed by widgets via a Provider of the abstract type.
//

import Foundation
import Combine

/// The view-facing interface for the session controller. All SwiftUI views depend on this
/// protocol via `@ObservedObject` or `@StateObject`, never on the concrete class.
@MainActor
public protocol SessionControllerProtocol: ObservableObject {

    /// The current session state. Views `switch` on this to render their body.
    var state: SessionState { get }

    /// Start a new session. Transitions idle → running. Schedules the first break alarm.
    func start()

    /// Stop the current session. Transitions any-state → idle. Cancels all pending alarms.
    func stop()

    /// Acknowledge the currently-active break from inside the app. Used by
    /// `BreakPendingView` when the user taps the in-app "Start break" button.
    /// Cancels the alerting break alarm and synthesizes a dismissed event so the
    /// controller schedules the look-away phase.
    func acknowledgeCurrentBreak()

    /// Rebuilds in-memory state from persistence + the alarm scheduler + the clock.
    /// Called on app launch, foregrounding, and periodic ticks. Never trusts in-memory state.
    func reconcile() async

    /// The current weekly schedule. Views observe this to display schedule settings.
    var weeklySchedule: WeeklySchedule { get }

    /// Replace the weekly schedule and persist it.
    func updateSchedule(_ schedule: WeeklySchedule)

    /// Whether the alarm sound is muted. When true, AlarmKit alarms fire silently
    /// (full-screen UI still appears). Persisted across launches.
    var muteAlarmSound: Bool { get }

    /// Update and persist the alarm-sound mute preference. If the session is in the
    /// `.running` state, the scheduled alarm is cancelled and rescheduled immediately with the
    /// new sound setting (within a few seconds).
    func updateAlarmSound(muted: Bool)
}
