//
//  Constants.swift
//  BlinkBreakCore
//
//  All hardcoded values for the 20-20-20 rule, notification identifiers, and tunables.
//  These are compile-time only — never read from UserDefaults, never configurable at runtime.
//
//  Flutter analogue: think of this as a `class Constants` with only `static const` members.
//

import Foundation

/// Namespaced constants for BlinkBreak. Never instantiated.
public enum BlinkBreakConstants {

    // MARK: - Timer durations

    /// How long the user works between breaks. Hardcoded per the 20-20-20 rule.
    public static let breakInterval: TimeInterval = 20 * 60  // 20 minutes

    /// How long the user looks 20 feet away during a break. Hardcoded per the 20-20-20 rule.
    public static let lookAwayDuration: TimeInterval = 20    // 20 seconds

    // MARK: - Notification cascade tuning

    /// How many seconds between each haptic nudge in the break cascade.
    public static let nudgeInterval: TimeInterval = 5

    /// How many nudges fire after the primary break notification before the cascade gives up.
    /// With 5 nudges at 5-second intervals, the wrist buzzes for 25 seconds after the primary,
    /// for a total of ~30 seconds of "alarm-like" buzzing before it stops.
    public static let nudgeCount: Int = 5

    // MARK: - Notification identifiers

    /// Prefix for the primary break notification. Formatted with the cycle UUID.
    public static let breakPrimaryIdPrefix = "break.primary."

    /// Prefix for the nudge notifications. Formatted with `<cycleId>.<n>`.
    public static let breakNudgeIdPrefix = "break.nudge."

    /// Prefix for the "done looking away, back to work" notification.
    public static let doneIdPrefix = "done."

    /// Filename (without directory path) of the bundled custom alarm sound for the break
    /// notification. iOS looks for this in the app bundle and truncates at 30 seconds.
    public static let breakSoundFileName = "break-alarm.caf"

    /// Notification category ID for the break-alert action ("Start break" button).
    public static let breakCategoryId = "BLINKBREAK_BREAK_CATEGORY"

    /// Action identifier for the Start break button on notifications.
    public static let startBreakActionId = "START_BREAK"

    // MARK: - Persistence keys

    /// UserDefaults key for the persisted session record. Single-key storage; the value is
    /// a JSON-encoded `SessionRecord`.
    public static let sessionRecordKey = "BlinkBreak.SessionRecord"
}
