//
//  SessionRecord.swift
//  BlinkBreakCore
//
//  The Codable persistence struct stored in UserDefaults. Small on purpose: the
//  pending notification queue is the source of truth for "what happens next";
//  this record is just what lets the UI rehydrate on launch.
//
//  `lastUpdatedAt` is a staleness marker used by `SessionController.handleRemoteSnapshot`
//  to drop out-of-order snapshot deliveries. It's optional for Codable backwards
//  compatibility with pre-redesign persisted records.
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

    /// Backwards-compatible coding keys: `breakActiveStartedAt` is encoded as
    /// `"lookAwayStartedAt"` so existing persisted records decode without migration.
    enum CodingKeys: String, CodingKey {
        case sessionActive
        case currentCycleId
        case cycleStartedAt
        case breakActiveStartedAt = "lookAwayStartedAt"
        case lastUpdatedAt
        case manualStopDate
        case wasAutoStarted
    }

    /// Whether this session was started automatically by the weekly schedule evaluator
    /// (as opposed to the user manually tapping Start). Only schedule-started sessions
    /// are eligible for automatic schedule-based stopping. Optional so legacy records
    /// decode without migration; nil is treated as false.
    public var wasAutoStarted: Bool?

    public init(
        sessionActive: Bool = false,
        currentCycleId: UUID? = nil,
        cycleStartedAt: Date? = nil,
        breakActiveStartedAt: Date? = nil,
        lastUpdatedAt: Date? = nil,
        manualStopDate: Date? = nil,
        wasAutoStarted: Bool? = nil
    ) {
        self.sessionActive = sessionActive
        self.currentCycleId = currentCycleId
        self.cycleStartedAt = cycleStartedAt
        self.breakActiveStartedAt = breakActiveStartedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.manualStopDate = manualStopDate
        self.wasAutoStarted = wasAutoStarted
    }

    /// The canonical "idle" record. Use this when stopping or clearing session state.
    public static let idle = SessionRecord(
        sessionActive: false,
        currentCycleId: nil,
        cycleStartedAt: nil,
        breakActiveStartedAt: nil,
        lastUpdatedAt: nil
    )
}
