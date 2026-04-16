//
//  Constants.swift
//  BlinkBreakCore
//
//  All hardcoded values for the 20-20-20 rule, persistence keys, and tunables.
//  Timer durations support runtime overrides via environment variables so that
//  XCUITest integration tests can shrink real wall-clock waits from minutes to seconds.
//  Production builds don't set those env vars and get the unmodified 20-20-20 values.
//
//  Flutter analogue: think of this as a `class Constants` with only `static const` members,
//  except a few values are seeded from ProcessInfo.environment once at first access.
//

import Foundation

/// Namespaced constants for BlinkBreak. Never instantiated.
public enum BlinkBreakConstants {

    // MARK: - Timer durations (env-overridable for integration tests)

    /// How long the user works between breaks. Defaults to the 20-minute 20-20-20 rule,
    /// but can be shrunk via the `BB_BREAK_INTERVAL` environment variable (in seconds) so
    /// XCUITest integration tests can exercise a full cycle in ~3 seconds of wall-clock time.
    ///
    /// Evaluated at first access and frozen for the rest of the process. Production builds
    /// never set this env var and get the 20-minute default.
    public static let breakInterval: TimeInterval = {
        if let override = ProcessInfo.processInfo.environment["BB_BREAK_INTERVAL"],
           let value = TimeInterval(override), value > 0 {
            return value
        }
        return 20 * 60  // 20 minutes
    }()

    /// How long the user looks 20 feet away during a break. Defaults to 20 seconds (the
    /// 20-20-20 rule), overridable via `BB_LOOKAWAY_DURATION` for integration tests.
    ///
    /// Evaluated at first access and frozen for the rest of the process.
    public static let lookAwayDuration: TimeInterval = {
        if let override = ProcessInfo.processInfo.environment["BB_LOOKAWAY_DURATION"],
           let value = TimeInterval(override), value > 0 {
            return value
        }
        return 20
    }()

    // MARK: - Alarm sound

    /// Filename (without directory path) of the bundled custom alarm sound used by
    /// AlarmKit. iOS looks for this in the app bundle and truncates at 30 seconds.
    /// Returns nil when running under the XCUITest environment so simulator tests are silent.
    public static let breakSoundFileName: String? = {
        if ProcessInfo.processInfo.environment["BB_BREAK_INTERVAL"] != nil {
            return nil
        }
        return "break-alarm.caf"
    }()

    // MARK: - Persistence keys

    /// UserDefaults key for the persisted session record. Single-key storage; the value is
    /// a JSON-encoded `SessionRecord`.
    public static let sessionRecordKey = "BlinkBreak.SessionRecord"

    /// UserDefaults key for the persisted weekly schedule. Stored separately from
    /// `sessionRecordKey` so existing users upgrade cleanly — a missing schedule key
    /// falls back to `WeeklySchedule.default` without touching the session record.
    public static let weeklyScheduleKey = "BlinkBreak.WeeklySchedule"

    // MARK: - Schedule task identifier

    /// BGTaskScheduler task identifier for schedule checks.
    public static let scheduleTaskId = "com.tytaniumdev.BlinkBreak.scheduleCheck"
}
