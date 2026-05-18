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
//  1. Write an "acknowledge" marker keyed to the alarm UUID. This is what
//     distinguishes the secondary button from the system Stop button at
//     dismiss time — without the marker, `SessionController.handleDismissed`
//     defaults to the skip path (no follow-up look-away). The default-skip
//     fallback makes the AlarmKit race where the dismissed event lands
//     before the intent finishes running harmless (BLINKBREAK-6: previously
//     fell through to the acknowledge path, queueing a 20-second look-away
//     alarm even when the user tapped Stop).
//  2. Cancel the alerting alarm so AlarmKit's `alarmUpdates` emits a
//     dismissed event the controller can consume.
//

import AppIntents
import AlarmKit
import BlinkBreakCore

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
        if let id = UUID(uuidString: alarmID) {
            // Order matters: write the marker *before* cancelling so it's
            // visible to `handleDismissed` by the time the dismissed event
            // propagates.
            UserDefaultsPersistence().saveAcknowledgeRequestedAlarmId(id)
            try? AlarmManager.shared.cancel(id: id)
        }
        return .result()
    }
}
