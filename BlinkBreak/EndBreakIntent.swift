//
//  EndBreakIntent.swift
//  BlinkBreak
//
//  LiveActivityIntent attached to the "End break" secondary button on the AlarmKit
//  look-away alarm. When the user taps the button, the system launches the app in the
//  background, runs perform(), and we cancel the alerting alarm. The AlarmKitScheduler's
//  alarmUpdates observer then emits a dismissed event, which SessionController treats
//  as the user acknowledging the break is over — it rolls to a new cycle and schedules
//  the next break alarm.
//
//  The slide-to-stop system control already produces the same dismissed event, so both
//  controls converge on the same "proceed to next cycle" behavior.
//

import AppIntents
import AlarmKit

@available(iOS 26.1, *)
struct EndBreakIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "End break"
    static var description = IntentDescription("Acknowledge the break is over.")

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
