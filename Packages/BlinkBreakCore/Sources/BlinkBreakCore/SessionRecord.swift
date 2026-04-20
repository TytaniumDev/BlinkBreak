//
//  SessionRecord.swift
//  BlinkBreakCore
//
//  The Codable persistence struct stored in UserDefaults. Small on purpose: the
//  pending alarm queue is the source of truth for "what happens next"; this record
//  is just what lets the UI rehydrate on launch.
//
//  Flutter analogue: the @JsonSerializable() model you'd stash in SharedPreferences.
//

import Foundation

/// The persisted session record. Written on every state transition and read once on
/// app launch to rehydrate UI state.
public struct SessionRecord: Codable, Equatable, Sendable {

    /// Whether a session is currently active. `false` means idle.
    public var sessionActive: Bool

    /// The current cycle's UUID. Used to tag alarms so we can cancel the
    /// break alarm on acknowledgment without touching unrelated cycles.
    public var currentCycleId: UUID?

    /// When the current running-state cycle began. Used to derive the next-break fire time.
    /// Nil in the idle state.
    public var cycleStartedAt: Date?

    /// When the current break window began. Non-nil only in the `breakActive` state.
    public var breakActiveStartedAt: Date?

    /// When the user last manually stopped the session. Used to detect intentional
    /// stops vs. crashes during reconciliation. Optional so legacy records decode
    /// without migration.
    public var manualStopDate: Date?

    /// Whether this session was started automatically by the weekly schedule evaluator
    /// (as opposed to the user manually tapping Start). Only schedule-started sessions
    /// are eligible for automatic schedule-based stopping. Optional so legacy records
    /// decode without migration; nil is treated as false.
    public var wasAutoStarted: Bool?

    /// The AlarmKit alarm ID currently scheduled for this session, if any. Persisted so
    /// reconciliation after app kill can correlate the in-memory cycle with the alarm
    /// the system is still tracking. Optional for backwards compatibility.
    public var currentAlarmId: UUID?

    /// Backwards-compatible coding keys: `breakActiveStartedAt` is encoded as
    /// `"lookAwayStartedAt"` so existing persisted records decode without migration.
    enum CodingKeys: String, CodingKey {
        case sessionActive
        case currentCycleId
        case cycleStartedAt
        case breakActiveStartedAt = "lookAwayStartedAt"
        case manualStopDate
        case wasAutoStarted
        case currentAlarmId
    }

    public init(
        sessionActive: Bool = false,
        currentCycleId: UUID? = nil,
        cycleStartedAt: Date? = nil,
        breakActiveStartedAt: Date? = nil,
        manualStopDate: Date? = nil,
        wasAutoStarted: Bool? = nil,
        currentAlarmId: UUID? = nil
    ) {
        self.sessionActive = sessionActive
        self.currentCycleId = currentCycleId
        self.cycleStartedAt = cycleStartedAt
        self.breakActiveStartedAt = breakActiveStartedAt
        self.manualStopDate = manualStopDate
        self.wasAutoStarted = wasAutoStarted
        self.currentAlarmId = currentAlarmId
    }

    /// The canonical "idle" record. Use this when stopping or clearing session state.
    public static let idle = SessionRecord(
        sessionActive: false,
        currentCycleId: nil,
        cycleStartedAt: nil,
        breakActiveStartedAt: nil
    )
}
