//
//  SkipBreakIntent.swift
//  BlinkBreak
//
//  LiveActivityIntent attached to the system Stop control on every BlinkBreak
//  AlarmKit alarm. Apple removed `stopButton` customization in iOS 26.1, so the
//  label stays "Stop" — we change its behavior: tapping Stop *skips this
//  reminder* and resumes the normal 20-minute cadence with a fresh breakDue
//  alarm, instead of acknowledging the break and rolling through a look-away.
//
//  Mechanics: this intent has nothing to write. It just cancels the alerting
//  alarm. `SessionController.handleDismissed` treats absence of the acknowledge
//  marker (which only the secondary "Start break" / "End break" button writes
//  via `DismissAlarmIntent`) as the default skip path — schedule the next
//  breakDue, no look-away. That makes BLINKBREAK-6 impossible: any dismissed
//  event without an explicit acknowledge falls into skip, so the AlarmKit race
//  where `alarmUpdates` emits before the intent runs no longer surfaces a
//  surprise 20-second look-away alarm.
//
//  Continuing the cycle "the normal way" (take the break, then roll) is the
//  secondary "Start break" / "End break" button, wired to `DismissAlarmIntent`.
//

import AppIntents
import AlarmKit
import BlinkBreakCore
import Foundation
import os

/// `LogBuffer.shared` is per-process and silently drops messages when the intent
/// runs outside the main app, so use `os.Logger` for unified logging that's
/// reachable from any process (Console.app, `log show`). The intent also
/// appends a structured entry via `appendIntentExecutionLog` so the main app
/// can drain it and mirror it into `LogBuffer` (and therefore Sentry
/// breadcrumbs) the next time `handleDismissed` runs.
private let intentLogger = Logger(
    subsystem: "com.tytaniumdev.BlinkBreak",
    category: "SkipBreakIntent"
)

struct SkipBreakIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "Skip this break"
    static var description = IntentDescription(
        "Skip this BlinkBreak reminder. Reminders continue on their normal cadence."
    )

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
            intentLogger.info("skip requested for alarm \(id.uuidString, privacy: .public)")
            persistence.appendIntentExecutionLog(
                IntentExecutionLogEntry(
                    timestamp: Date(),
                    intent: "SkipBreakIntent",
                    message: "cancel alarm=\(shortId) (system Stop)"
                )
            )
            try? AlarmManager.shared.cancel(id: id)
        } else {
            intentLogger.error("perform: alarmID parameter not a valid UUID")
            persistence.appendIntentExecutionLog(
                IntentExecutionLogEntry(
                    timestamp: Date(),
                    intent: "SkipBreakIntent",
                    message: "invalid alarmID parameter, no cancel issued"
                )
            )
        }
        return .result()
    }
}
