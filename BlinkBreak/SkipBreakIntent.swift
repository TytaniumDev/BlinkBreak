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
//  Mechanics:
//  1. Write a "skip" marker to UserDefaults keyed to the alarm being dismissed.
//     `SessionController.handleDismissed` consumes the marker (load + clear) at
//     the top of its dispatch and, if it matches the alarm being dismissed,
//     skips the look-away step and schedules the next breakDue immediately.
//  2. Cancel the firing alarm. AlarmKit propagates this through `alarmUpdates`,
//     reaching `handleDismissed` in the running app — where step 1's marker
//     drives the routing.
//
//  Continuing the cycle "the normal way" (take the break, then roll) is the
//  secondary "Start break" / "End break" button, wired to `DismissAlarmIntent`.
//  That path doesn't touch the skip marker.
//

import AppIntents
import AlarmKit
import BlinkBreakCore
import os

/// `LogBuffer.shared` is per-process and silently drops messages when the intent
/// runs outside the main app, so use `os.Logger` for unified logging that's
/// reachable from any process (Console.app, `log show`).
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
        // Order matters: write the marker *before* cancelling the alarm so that
        // by the time the cancellation propagates as a `.dismissed` event and
        // `SessionController.handleDismissed` runs, the marker is already
        // visible to it.
        if let id = UUID(uuidString: alarmID) {
            UserDefaultsPersistence().saveSkipRequestedAlarmId(id)
            try? AlarmManager.shared.cancel(id: id)
            intentLogger.info("skip requested for alarm \(id.uuidString, privacy: .public)")
        } else {
            intentLogger.error("perform: alarmID parameter not a valid UUID")
        }
        return .result()
    }
}
