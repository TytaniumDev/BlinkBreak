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
///    idle ────(Start)────► running ────(primary notification fires)────► breakActive
///      ▲                      │                                              │
///      │                      │                                   (user taps "Start break")
///      │                      │                                              │
///   (Stop, from any state)   (Stop)                                           ▼
///      │                      │                                         lookAway
///      └──────────────────────┴──────(done notification, 20 s later)────────┘
/// ```
public enum SessionState: Equatable, Sendable {

    /// No session running. Start button is visible. No pending notifications.
    case idle

    /// A session is active, counting down to the next break.
    /// - Parameter cycleStartedAt: When the current 20-minute countdown started.
    ///   The next break fires at `cycleStartedAt + BlinkBreakConstants.breakInterval`.
    case running(cycleStartedAt: Date)

    /// The primary break notification has fired. Awaiting user acknowledgment.
    /// If the app is foregrounded, show the red alert UI. If not, the cascade is
    /// buzzing the Watch in the background and this state is never visibly rendered.
    /// - Parameter cycleStartedAt: When the 20-minute countdown for this cycle started.
    case breakActive(cycleStartedAt: Date)

    /// The user has tapped "Start break". The 20-second look-away is counting down.
    /// - Parameter lookAwayStartedAt: When the look-away began. The `done` haptic
    ///   fires at `lookAwayStartedAt + BlinkBreakConstants.lookAwayDuration`.
    case lookAway(lookAwayStartedAt: Date)
}

// MARK: - Convenience queries

extension SessionState {

    /// `true` if the session is active in any form (not `.idle`).
    public var isActive: Bool {
        switch self {
        case .idle:
            return false
        case .running, .breakActive, .lookAway:
            return true
        }
    }

    /// The name of the current state, for logging and debugging.
    public var name: String {
        switch self {
        case .idle:        return "idle"
        case .running:     return "running"
        case .breakActive: return "breakActive"
        case .lookAway:    return "lookAway"
        }
    }
}

extension SessionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: return "idle"
        case .running: return "running"
        case .breakActive: return "breakActive"
        case .lookAway: return "lookAway"
        }
    }
}
