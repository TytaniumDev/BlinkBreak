//
//  SessionControllerProtocol.swift
//  BlinkBreakCore
//
//  The view-facing protocol for the session controller. Views depend on this protocol,
//  not on the concrete SessionController class. This gives us:
//
//  - PreviewSessionController (in the app target) for SwiftUI previews without real alarms.
//  - A hard boundary: a view cannot accidentally reach the scheduler or persistence
//    because the protocol doesn't expose them.
//
//  Conformers are `@Observable`, so SwiftUI re-renders a view whenever a property
//  it read changes — no @Published / @ObservedObject wrappers needed.
//
//  Flutter analogue: an abstract class that a ChangeNotifier implements, consumed
//  by widgets via a Provider of the abstract type.
//

import Foundation
import Observation

@MainActor
public protocol SessionControllerProtocol: AnyObject, Observable {

    /// What the UI should show. Views `switch` on this.
    var state: SessionState { get }

    /// The weekly auto-start schedule.
    var weeklySchedule: WeeklySchedule { get }

    /// Whether alarms play silently (the full-screen UI still appears).
    var muteAlarmSound: Bool { get }

    /// True when the user has denied alarm permission.
    var authorizationDenied: Bool { get }

    /// Idle-screen schedule status at `date`, e.g. "Starts at 9:00 AM".
    func scheduleStatus(at date: Date) -> String?

    /// idle / paused → running. Schedules the first break alarm. Doubles as
    /// "Resume" from the paused state.
    func start() async

    /// Any state → idle. Cancels all alarms.
    func stop() async

    /// True when `pause()` would do something: a session is running and a
    /// weekly-schedule window is open right now. Reads the clock, so views that
    /// re-render every second (RunningView's timeline) pick up window changes.
    var canPause: Bool { get }

    /// running / breakPending / breakActive → paused, for the rest of the current
    /// schedule window. Cancels all alarms. No-op when `canPause` is false.
    func pause() async

    /// breakPending → breakActive. The in-app equivalent of the alarm's "Start break" button.
    func startBreak() async

    /// running → breakPending in about a second, by moving the break alarm up.
    func takeBreakNow() async

    /// Re-sync with the system: permission, alarms that fired or vanished while
    /// the app wasn't running, and the weekly schedule. Call when the app becomes active.
    func reconcile() async

    /// Save a new schedule. Updates `weeklySchedule` immediately.
    func updateSchedule(_ schedule: WeeklySchedule)

    /// Save the mute preference. Updates `muteAlarmSound` immediately.
    func updateAlarmSound(muted: Bool)
}
