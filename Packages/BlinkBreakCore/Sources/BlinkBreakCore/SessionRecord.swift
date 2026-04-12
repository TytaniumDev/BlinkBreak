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

    /// When the current look-away window began. Non-nil only in the `lookAway` state.
    public var lookAwayStartedAt: Date?

    /// When this record was last written (locally or from an incoming remote snapshot).
    /// Optional so legacy persisted records decode without migration.
    public var lastUpdatedAt: Date?

    /// When the user last manually stopped the session. Used to detect intentional
    /// stops vs. crashes during reconciliation. Optional so legacy records decode
    /// without migration.
    public var manualStopDate: Date?

    public init(
        sessionActive: Bool = false,
        currentCycleId: UUID? = nil,
        cycleStartedAt: Date? = nil,
        lookAwayStartedAt: Date? = nil,
        lastUpdatedAt: Date? = nil,
        manualStopDate: Date? = nil
    ) {
        self.sessionActive = sessionActive
        self.currentCycleId = currentCycleId
        self.cycleStartedAt = cycleStartedAt
        self.lookAwayStartedAt = lookAwayStartedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.manualStopDate = manualStopDate
    }

    /// Build a persistence record from an incoming WatchConnectivity snapshot.
    /// Copies `snapshot.updatedAt` into `lastUpdatedAt` so the staleness guard
    /// in `handleRemoteSnapshot` sees the right timestamp.
    public init(from snapshot: SessionSnapshot) {
        self.sessionActive = snapshot.sessionActive
        self.currentCycleId = snapshot.currentCycleId
        self.cycleStartedAt = snapshot.cycleStartedAt
        self.lookAwayStartedAt = snapshot.lookAwayStartedAt
        self.lastUpdatedAt = snapshot.updatedAt
    }

    /// The canonical "idle" record. Use this when stopping or clearing session state.
    public static let idle = SessionRecord(
        sessionActive: false,
        currentCycleId: nil,
        cycleStartedAt: nil,
        lookAwayStartedAt: nil,
        lastUpdatedAt: nil
    )
}
