//
//  SessionState.swift
//  BlinkBreakCore
//
//  The five-case state enum that drives all UI and the state machine. Views `switch`
//  on this enum to render their body; they never contain business logic beyond that.
//
//  Flutter analogue: this is the equivalent of a sealed class with five subtypes,
//  consumed by a Selector<SessionState, SessionState> and rendered with a switch.
//

import Foundation

/// The five possible states of a BlinkBreak session. Published by `SessionController`
/// and observed by all views.
///
/// ```
///    idle ────(Start)────► running ────(break-due alarm fires)────► breakPending
///      ▲                      │                                         │
///      │                      │                              (user taps "Start break")
///      │                      │                                         │
///   (Stop, from any state)   (Stop)                                      ▼
///      │                      │                                    breakActive
///      └──────────────────────┴──────(look-away alarm, 20 s later)───────┘
///
///    running / breakPending / breakActive ──(Pause, inside a schedule window)──► paused
///    paused ──(Resume)──► running        paused ──(schedule window ends)──► idle
/// ```
public enum SessionState: Equatable, Sendable {

    /// No session running. Start button is visible. No pending notifications.
    case idle

    /// A session is active, counting down to the next break.
    /// - Parameter cycleStartedAt: When the current 20-minute countdown started.
    ///   The next break fires at `cycleStartedAt + BlinkBreakConstants.breakInterval`.
    case running(cycleStartedAt: Date)

    /// The break-due alarm has fired. AlarmKit is showing the full-screen alert UI;
    /// the app (if foregrounded) renders this state while the user acknowledges.
    /// - Parameter cycleStartedAt: When the 20-minute countdown for this cycle started.
    case breakPending(cycleStartedAt: Date)

    /// The user has tapped "Start break". The 20-second break is counting down.
    /// - Parameter startedAt: When the break began. The look-away alarm fires at
    ///   `startedAt + BlinkBreakConstants.lookAwayDuration`.
    case breakActive(startedAt: Date)

    /// The user paused a session during a weekly-schedule window (e.g. for a nap).
    /// No alarms are scheduled and the schedule won't auto-restart the session
    /// until the user resumes. When the window ends the pause lapses into `.idle`,
    /// so the schedule auto-starts again at the next scheduled window as usual.
    /// - Parameter until: The end of the schedule window the pause belongs to.
    case paused(until: Date)
}

// MARK: - Convenience queries

extension SessionState {

    /// `true` if a session is running in any form — i.e. alarms are scheduled.
    /// `.idle` and `.paused` are both inactive.
    public var isActive: Bool {
        switch self {
        case .idle, .paused:
            return false
        case .running, .breakPending, .breakActive:
            return true
        }
    }

}

extension SessionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: return "idle"
        case .running: return "running"
        case .breakPending: return "breakPending"
        case .breakActive: return "breakActive"
        case .paused: return "paused"
        }
    }
}
