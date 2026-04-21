//
//  SessionRecord.swift
//  BlinkBreakCore
//
//  The Codable persistence struct stored in UserDefaults. Small on purpose: the
//  AlarmKit system alarm set is the source of truth for "what happens next";
//  this record carries the cycle metadata needed to interpret those alarms on
//  launch.
//
//  Flutter analogue: the @JsonSerializable() model you'd stash in SharedPreferences.
//

import Foundation

/// The persisted session record. Written on every state transition and read once on
/// app launch to rehydrate UI state.
public struct SessionRecord: Codable, Equatable, Sendable {

    /// Whether a session is currently active. `false` means idle.
    public var sessionActive: Bool

    /// The current cycle's UUID. Used to tag notifications so we can cancel the
    /// break notification on acknowledgment without touching unrelated cycles.
    public var currentCycleId: UUID?

    /// When the current running-state cycle began. Used to derive the next-break fire time.
    /// Nil in the idle state.
    public var cycleStartedAt: Date?

    /// When the current break window began. Non-nil only in the `breakActive` state.
    public var breakActiveStartedAt: Date?

    /// When this record was last written (locally or from an incoming remote snapshot).
    /// Optional so legacy persisted records decode without migration.
    public var lastUpdatedAt: Date?

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

    public init(
        sessionActive: Bool = false,
        currentCycleId: UUID? = nil,
        cycleStartedAt: Date? = nil,
        breakActiveStartedAt: Date? = nil,
        lastUpdatedAt: Date? = nil,
        manualStopDate: Date? = nil,
        wasAutoStarted: Bool? = nil,
        currentAlarmId: UUID? = nil
    ) {
        self.sessionActive = sessionActive
        self.currentCycleId = currentCycleId
        self.cycleStartedAt = cycleStartedAt
        self.breakActiveStartedAt = breakActiveStartedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.manualStopDate = manualStopDate
        self.wasAutoStarted = wasAutoStarted
        self.currentAlarmId = currentAlarmId
    }

    /// The canonical "idle" record. Use this when stopping or clearing session state.
    public static let idle = SessionRecord(
        sessionActive: false,
        currentCycleId: nil,
        cycleStartedAt: nil,
        breakActiveStartedAt: nil,
        lastUpdatedAt: nil
    )

    // MARK: - Codable
    //
    // Custom coding to support a legacy key: earlier builds persisted
    // `breakActiveStartedAt` under the name `lookAwayStartedAt`. Users upgrading
    // mid-break-active would otherwise silently lose that timestamp. Encoding
    // always uses the new key; decoding accepts either.

    private enum CodingKeys: String, CodingKey {
        case sessionActive
        case currentCycleId
        case cycleStartedAt
        case breakActiveStartedAt
        case lastUpdatedAt
        case manualStopDate
        case wasAutoStarted
        case currentAlarmId
        case lookAwayStartedAt // legacy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionActive = try c.decodeIfPresent(Bool.self, forKey: .sessionActive) ?? false
        self.currentCycleId = try c.decodeIfPresent(UUID.self, forKey: .currentCycleId)
        self.cycleStartedAt = try c.decodeIfPresent(Date.self, forKey: .cycleStartedAt)
        self.breakActiveStartedAt = try c.decodeIfPresent(Date.self, forKey: .breakActiveStartedAt)
            ?? c.decodeIfPresent(Date.self, forKey: .lookAwayStartedAt)
        self.lastUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
        self.manualStopDate = try c.decodeIfPresent(Date.self, forKey: .manualStopDate)
        self.wasAutoStarted = try c.decodeIfPresent(Bool.self, forKey: .wasAutoStarted)
        self.currentAlarmId = try c.decodeIfPresent(UUID.self, forKey: .currentAlarmId)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionActive, forKey: .sessionActive)
        try c.encodeIfPresent(currentCycleId, forKey: .currentCycleId)
        try c.encodeIfPresent(cycleStartedAt, forKey: .cycleStartedAt)
        try c.encodeIfPresent(breakActiveStartedAt, forKey: .breakActiveStartedAt)
        try c.encodeIfPresent(lastUpdatedAt, forKey: .lastUpdatedAt)
        try c.encodeIfPresent(manualStopDate, forKey: .manualStopDate)
        try c.encodeIfPresent(wasAutoStarted, forKey: .wasAutoStarted)
        try c.encodeIfPresent(currentAlarmId, forKey: .currentAlarmId)
    }
}
