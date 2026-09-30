//
//  Constants.swift
//  BlinkBreakCore
//
//  Durations for the 20-20-20 rule and a couple of timing tunables.
//
//  In DEBUG builds the two cycle durations can be overridden with environment
//  variables so XCUITest integration tests can shrink real wall-clock waits from
//  minutes to seconds. Release builds always use the real values.
//
//  Flutter analogue: a `class Constants` with only `static const` members.
//

import Foundation

/// Namespaced constants for BlinkBreak. Never instantiated.
public enum BlinkBreakConstants {

    /// How long the user works between breaks: 20 minutes.
    /// DEBUG override: `BB_BREAK_INTERVAL` (seconds).
    public static let breakInterval: TimeInterval = override("BB_BREAK_INTERVAL") ?? 20 * 60

    /// How long the user looks 20 feet away: 20 seconds.
    /// DEBUG override: `BB_LOOKAWAY_DURATION` (seconds).
    public static let lookAwayDuration: TimeInterval = override("BB_LOOKAWAY_DURATION") ?? 20

    /// How long to wait, after an alarm disappears without a button intent
    /// reporting what the user tapped, before assuming "no response" and
    /// skipping to the next cycle. The system removes the alarm slightly before
    /// it runs the intent, so acting immediately would race the intent.
    public static let missingAlarmGrace: Duration = .seconds(5)

    /// Slack after the look-away alarm's fire time before the app rolls to the
    /// next cycle on its own, so a slightly late alarm isn't cancelled early.
    public static let lookAwayCompletionMargin: TimeInterval = 1

    private static func override(_ name: String) -> TimeInterval? {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment[name],
           let value = TimeInterval(raw), value > 0 {
            return value
        }
        #endif
        return nil
    }
}
