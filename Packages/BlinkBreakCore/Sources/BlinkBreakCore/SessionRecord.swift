//
//  SessionRecord.swift
//  BlinkBreakCore
//
//  The Codable persistence struct stored in UserDefaults. Small on purpose: the
//  pending notification queue is the source of truth for "what happens next";
//  this record is just what lets the UI rehydrate on launch.
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
    /// cascade on acknowledgment without touching unrelated cycles.
    public var currentCycleId: UUID?

    /// When the current running-state cycle began. Used to derive the next-break fire time.
    /// Nil in the idle state.
    public var cycleStartedAt: Date?

    /// When the current look-away window began. Non-nil only in the `lookAway` state.
    public var lookAwayStartedAt: Date?

    public init(
        sessionActive: Bool = false,
        currentCycleId: UUID? = nil,
        cycleStartedAt: Date? = nil,
        lookAwayStartedAt: Date? = nil
    ) {
        self.sessionActive = sessionActive
        self.currentCycleId = currentCycleId
        self.cycleStartedAt = cycleStartedAt
        self.lookAwayStartedAt = lookAwayStartedAt
    }

    /// The canonical "idle" record. Use this when stopping or clearing session state.
    public static let idle = SessionRecord(
        sessionActive: false,
        currentCycleId: nil,
        cycleStartedAt: nil,
        lookAwayStartedAt: nil
    )
}
