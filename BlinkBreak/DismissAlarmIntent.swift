//
//  DismissAlarmIntent.swift
//  BlinkBreak
//
//  LiveActivityIntent attached to the secondary button on both AlarmKit alarms
//  ("Start break" on the break-due alarm, "End break" on the look-away alarm).
//  The visible label comes from `AlarmButton.text` in the AlarmKit presentation;
//  this intent only needs to cancel the alerting alarm. The AlarmKitScheduler's
//  alarmUpdates observer then emits a dismissed event, which SessionController
//  treats as the user acknowledging the alarm.
//
//  Both buttons collapse to the same behavior — cancel-by-UUID — so a single
//  intent type is enough.
//

import AppIntents
import AlarmKit

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
            try? AlarmManager.shared.cancel(id: id)
        }
        return .result()
    }
}
