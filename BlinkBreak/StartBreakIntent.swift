//
//  StartBreakIntent.swift
//  BlinkBreak
//
//  LiveActivityIntent attached to the "Start break" secondary button on the AlarmKit
//  break-due alarm. When the user taps the button, the system launches the app in the
//  background, runs perform(), and we cancel the alerting alarm. The AlarmKitScheduler's
//  alarmUpdates observer then emits a dismissed event, which SessionController treats
//  as the user acknowledging the break — it schedules the look-away alarm.
//
//  The slide-to-stop system control already produces the same dismissed event, so both
//  controls converge on the same "proceed to look-away" behavior.
//

import AppIntents
import AlarmKit

@available(iOS 26.1, *)
struct StartBreakIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "Start break"
    static var description = IntentDescription("Acknowledge the break reminder and start the 20-second look-away.")

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
