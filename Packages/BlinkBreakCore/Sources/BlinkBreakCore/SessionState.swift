//
//  SessionState.swift
//  BlinkBreakCore
//
//  The four-case state enum that drives all UI and the state machine. Views `switch`
//  on this enum to render their body; they never contain business logic beyond that.
//
//  Flutter analogue: this is the equivalent of a sealed class with four subtypes,
//  consumed by a Selector<SessionState, SessionState> and rendered with a switch.
//

import Foundation

/// The four possible states of a BlinkBreak session. Published by `SessionController`
/// and observed by all views.
///
/// ```
///    idle ────(Start)────► running ────(primary notification fires)────► breakPending
///      ▲                      │                                              │
///      │                      │                                   (user taps "Start break")
///      │                      │                                              │
///   (Stop, from any state)   (Stop)                                           ▼
///      │                      │                                         breakActive
///      └──────────────────────┴──────(done notification, 20 s later)────────┘
/// ```
public enum SessionState: Equatable, Sendable {

    /// No session running. Start button is visible. No pending notifications.
    case idle

    /// A session is active, counting down to the next break.
    /// - Parameter cycleStartedAt: When the current 20-minute countdown started.
    ///   The next break fires at `cycleStartedAt + BlinkBreakConstants.breakInterval`.
    case running(cycleStartedAt: Date)

    /// The break-due alarm has fired. Awaiting user acknowledgment via the
    /// AlarmKit takeover's "Start break" button or the in-app BreakPendingView.
    /// - Parameter cycleStartedAt: When the 20-minute countdown for this cycle started.
    case breakPending(cycleStartedAt: Date)

    /// The user has tapped "Start break". The 20-second break is counting down.
    /// - Parameter startedAt: When the break began. The `done` haptic
    ///   fires at `startedAt + BlinkBreakConstants.lookAwayDuration`.
    case breakActive(startedAt: Date)
}

// MARK: - Convenience queries

extension SessionState {

    /// `true` if the session is active in any form (not `.idle`).
    public var isActive: Bool {
        switch self {
        case .idle:
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
        }
    }
}
