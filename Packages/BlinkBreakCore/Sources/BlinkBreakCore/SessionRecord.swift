//
//  SessionRecord.swift
//  BlinkBreakCore
//
//  The Codable struct persisted to UserDefaults. It is the single source of
//  truth for where the session is in the 20-20-20 cycle: which phase, which
//  alarm the session owns, and when that alarm fires. `SessionState` (what the
//  UI shows) is derived from it plus the clock.
//
//  Flutter analogue: the @JsonSerializable() model you'd stash in SharedPreferences.
//

import Foundation

/// The persisted session record. Written on every transition by `SessionController`.
public struct SessionRecord: Codable, Equatable, Sendable {

    /// Where the session is in the cycle.
    public enum Phase: String, Codable, Sendable {
        /// No session. No alarm is owned.
        case idle
        /// The weekly schedule has pre-booked the first break of an upcoming
        /// window. The UI stays idle until the window opens.
        case scheduled
        /// Counting down to a break. The break-due alarm is pending or alerting.
        case running
        /// The 20-second look-away is in progress. The look-away alarm is
        /// pending or alerting.
        case lookingAway
    }

    public var phase: Phase

    /// The one alarm this session owns. Nil when idle.
    public var alarmId: UUID?

    /// When `alarmId` fires. Nil when idle.
    public var alarmFiresAt: Date?

    /// True when the weekly schedule started this session. Only these sessions
    /// stop automatically at the end of a schedule window.
    public var wasAutoStarted: Bool

    /// When the user last stopped (or paused) a session inside a schedule window.
    /// Keeps the schedule from restarting the session for the rest of that window.
    /// Carried on idle and pre-booked records.
    public var manualStopDate: Date?

    /// Set while the user has paused inside a schedule window: the end of that
    /// window. The UI shows `.paused` until then; afterwards the pause lapses and
    /// the schedule takes over again. Carried on idle and pre-booked records.
    public var pausedUntil: Date?

    /// For manually started sessions (including Resume) while the weekly schedule
    /// is on: when to hand control back to the schedule — the end of the window
    /// open at start, or of the next one to open. Nil for schedule-started
    /// sessions (they follow the live schedule) and when the schedule is off.
    public var scheduledStopAt: Date?

    public init(
        phase: Phase = .idle,
        alarmId: UUID? = nil,
        alarmFiresAt: Date? = nil,
        wasAutoStarted: Bool = false,
        manualStopDate: Date? = nil,
        pausedUntil: Date? = nil,
        scheduledStopAt: Date? = nil
    ) {
        self.phase = phase
        self.alarmId = alarmId
        self.alarmFiresAt = alarmFiresAt
        self.wasAutoStarted = wasAutoStarted
        self.manualStopDate = manualStopDate
        self.pausedUntil = pausedUntil
        self.scheduledStopAt = scheduledStopAt
    }

    /// The kind of `alarmId`, implied by the phase.
    public var alarmKind: AlarmKind? {
        switch phase {
        case .idle: return nil
        case .scheduled, .running: return .breakDue
        case .lookingAway: return .lookAwayDone
        }
    }
}
