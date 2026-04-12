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

    /// Start a new session. Transitions idle → running. Schedules the first break cascade.
    func start()

    /// Stop the current session. Transitions any-state → idle. Cancels all pending notifications.
    func stop()

    /// Handle the user tapping "Start break" on a notification action.
    /// - Parameter cycleId: The UUID extracted from the tapped notification's identifier.
    ///   If this doesn't match the current cycle, the tap is treated as stale and ignored.
    func handleStartBreakAction(cycleId: UUID)

    /// Acknowledge the currently-active break from inside the app. Used by
    /// `BreakActiveView` when the user taps the in-app "Start break" button.
    /// The controller looks up its own current cycleId and calls `handleStartBreakAction`.
    /// Views don't need to know about cycleIds.
    func acknowledgeCurrentBreak()

    /// Called from onAppear / applicationDidBecomeActive. Rebuilds the in-memory state
    /// from UserDefaults + pending notifications. Never trusts in-memory state.
    func reconcileOnLaunch() async

    /// The current weekly schedule. Views observe this to display schedule settings.
    var weeklySchedule: WeeklySchedule { get }

    /// Replace the weekly schedule and persist it.
    func updateSchedule(_ schedule: WeeklySchedule)
}
