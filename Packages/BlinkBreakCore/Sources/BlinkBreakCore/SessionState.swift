//
//  SessionState.swift
//  BlinkBreakCore
//
//  The four-case state enum that drives all UI. Views `switch` on this enum to
//  render their body; they never contain business logic beyond that.
//
//  Flutter analogue: a sealed class with four subtypes, rendered with a switch.
//

import Foundation

/// What the UI shows. Derived by `SessionController` from the persisted
/// `SessionRecord` and the clock.
///
/// ```
///    idle ────(Start)────► running ────(break alarm fires)────► breakPending
///      ▲                      ▲                                     │
///      │                      │                          (user taps "Start break")
///   (Stop, from any state)    │                                     ▼
///      │                      └──────(20 s look-away ends)──── breakActive
/// ```
public enum SessionState: Equatable, Sendable {

    /// No session running.
    case idle

    /// Counting down to the next break.
    /// - Parameter breakAt: When the break alarm fires.
    case running(breakAt: Date)

    /// The break alarm is alerting; waiting for the user to start the break.
    case breakPending

    /// The user is looking away.
    /// - Parameter endsAt: When the look-away alarm fires.
    case breakActive(endsAt: Date)
}

extension SessionState {

    /// Maps a persisted record to UI state at `now`.
    static func derive(from record: SessionRecord, now: Date) -> SessionState {
        guard let firesAt = record.alarmFiresAt else { return .idle }
        switch record.phase {
        case .idle:
            return .idle
        case .scheduled where now < firesAt.addingTimeInterval(-BlinkBreakConstants.breakInterval):
            return .idle
        case .scheduled, .running:
            return now < firesAt ? .running(breakAt: firesAt) : .breakPending
        case .lookingAway:
            return .breakActive(endsAt: firesAt)
        }
    }

    /// `true` for every state except `.idle`.
    public var isActive: Bool {
        self != .idle
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
