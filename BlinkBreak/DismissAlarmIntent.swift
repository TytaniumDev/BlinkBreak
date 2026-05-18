//
//  DismissAlarmIntent.swift
//  BlinkBreak
//
//  LiveActivityIntent attached to the secondary button on both AlarmKit alarms
//  ("Start break" on the break-due alarm, "End break" on the look-away alarm).
//  The visible label comes from `AlarmButton.text` in the AlarmKit presentation;
//  this intent acknowledges the alarm: the user wants to take the break (on
//  break-due) or finish it (on look-away).
//
//  Mechanics:
//  1. Write an "acknowledge" marker keyed to the alarm UUID. For break-due
//     dismissals this distinguishes the secondary button from the system
//     Stop button — without the marker, `SessionController.handleDismissed`
//     defaults to the skip path (no follow-up look-away). The default-skip
//     fallback makes the AlarmKit race where the dismissed event lands
//     before the intent finishes running harmless (BLINKBREAK-6: previously
//     fell through to the acknowledge path, queueing a 20-second look-away
//     alarm even when the user tapped Stop). For look-away dismissals the
//     marker has no behavioral effect — `handleDismissed` rolls the cycle
//     regardless of `isAcknowledgeRequested` for `.lookAwayDone` — but
//     writing it unconditionally keeps this intent simple and parallel
//     across kinds.
//  2. Cancel the alerting alarm so AlarmKit's `alarmUpdates` emits a
//     dismissed event the controller can consume.
//
//  Both the marker write and the intent-execution log entry are persisted
//  *before* the cancel call so they're visible to `handleDismissed` by the
//  time the dismissed event propagates — including across the intent-host
//  process boundary, where `LogBuffer.shared` would otherwise leave the main
//  app blind to whether this intent ever ran.
//

import AppIntents
import AlarmKit
import BlinkBreakCore
import Foundation
import os

/// Cross-process logger reachable via `log show --predicate 'subsystem == "com.tytaniumdev.BlinkBreak"'`.
/// `LogBuffer.shared` would only capture this when the intent runs in the
/// main app process, but bug-report breadcrumbs need to survive the
/// intent-host case too — see `appendIntentExecutionLog` below.
private let intentLogger = Logger(
    subsystem: "com.tytaniumdev.BlinkBreak",
    category: "DismissAlarmIntent"
)

struct DismissAlarmIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "Dismiss alarm"
    static var description = IntentDescription("Acknowledge the BlinkBreak alarm and continue the 20-20-20 cycle.")

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        let persistence = UserDefaultsPersistence()
        if let id = UUID(uuidString: alarmID) {
            let shortId = id.uuidString.prefix(8)
            // Order matters: write the marker and the log entry *before*
            // cancelling so both are visible to `handleDismissed` by the
            // time the dismissed event propagates.
            persistence.saveAcknowledgeRequestedAlarmId(id)
            persistence.appendIntentExecutionLog(
                IntentExecutionLogEntry(
                    timestamp: Date(),
                    intent: "DismissAlarmIntent",
                    message: "ack alarm=\(shortId) (secondary button)"
                )
            )
            intentLogger.info("ack requested for alarm \(id.uuidString, privacy: .public)")
            try? AlarmManager.shared.cancel(id: id)
        } else {
            intentLogger.error("perform: alarmID parameter not a valid UUID")
            persistence.appendIntentExecutionLog(
                IntentExecutionLogEntry(
                    timestamp: Date(),
                    intent: "DismissAlarmIntent",
                    message: "invalid alarmID parameter, no cancel issued"
                )
            )
        }
        return .result()
    }
}
