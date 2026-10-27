//
//  AlarmIntents.swift
//  BlinkBreak
//
//  The App Intents behind the two buttons on every BlinkBreak alarm. iOS runs
//  these when the user taps a button — launching the app process in the
//  background if it isn't running — so the next alarm gets booked right away,
//  whether or not the app is open.
//
//  - The system Stop button (label fixed by AlarmKit since iOS 26.1) →
//    `BreakButtonIntent`: start the break on the break alarm, end it on the
//    look-away alarm. Stop is the main action because the system dismisses
//    a stopped alarm everywhere it rings, including a paired Apple Watch.
//  - The custom "Skip break" button (break alarm only) → `StopButtonIntent`:
//    skip this break and carry on with the normal 20-minute cadence.
//
//  Both hand the decision to `SessionController.respond(to:alarmId:)`, after
//  stopping their own alarm: the custom button doesn't dismiss the alarm by
//  itself, and the alert on a paired Apple Watch keeps ringing until the
//  alarm is stopped. Stopping an alarm the system already stopped is harmless.
//
//  The type names date from when the buttons were the other way round. They
//  stay as they are because alarms booked by an older build refer to these
//  intents by type name.
//
//  Flutter analogue: a notification-action callback that runs in a background
//  isolate and calls straight into your state class.
//

import AppIntents
import BlinkBreakCore
import Foundation

struct BreakButtonIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start or end a break"
    static let description: IntentDescription? = IntentDescription(
        "Starts the 20-second break, or ends it and continues the 20-20-20 cycle."
    )
    /// Only meaningful from an alarm's button, so keep it out of Shortcuts and Spotlight.
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            AlarmKitScheduler.stopRinging(alarmId: id)
        }
        await AppEnvironment.respond(.confirm, alarmID: alarmID)
        return .result()
    }
}

struct StopButtonIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip this break"
    static let description: IntentDescription? = IntentDescription(
        "Skips this BlinkBreak reminder. Reminders continue on their normal cadence."
    )
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            AlarmKitScheduler.stopRinging(alarmId: id)
        }
        await AppEnvironment.respond(.skip, alarmID: alarmID)
        return .result()
    }
}
