//
//  TurnOffBlinkBreakIntent.swift
//  BlinkBreak
//
//  LiveActivityIntent attached to the system Stop control on every BlinkBreak
//  AlarmKit alarm. Apple no longer lets apps relabel the stop button (iOS 26.1+
//  removed `stopButton`), so we change its behavior instead: tapping Stop here
//  ends the BlinkBreak session entirely — equivalent to the user opening the
//  app and tapping Stop — instead of acknowledging the break and rolling to
//  the next cycle.
//
//  Mechanics:
//  1. Write an idle SessionRecord to UserDefaults *before* cancelling alarms.
//     The session-active guard inside `SessionController.handleDismissed` then
//     short-circuits when the cancellation propagates as a `.dismissed` event,
//     so no look-away or next-cycle alarm is queued behind the user's back.
//  2. Set `manualStopDate = now` so `ScheduleEvaluator.shouldBeActive` will
//     suppress an auto-restart inside today's scheduled window. (Outside the
//     window the evaluator ignores the stop date, so it's safe to set always.)
//  3. Cancel every known BlinkBreak alarm and clear the alarm-id → kind
//     mapping so reconcile on next foreground sees a clean slate.
//
//  Continuing to the next cycle is handled by `DismissAlarmIntent` on the
//  secondary "Start break" / "End break" button — that path is unchanged.
//

import AppIntents
import AlarmKit
import BlinkBreakCore

struct TurnOffBlinkBreakIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "Turn off BlinkBreak"
    static var description = IntentDescription(
        "Stop BlinkBreak reminders. Reminders resume when you tap Start in the app."
    )

    init() {}

    func perform() async throws -> some IntentResult {
        // Order matters: idle record before alarm cancellation. See file header.
        var idleRecord = SessionRecord.idle
        let now = Date()
        idleRecord.lastUpdatedAt = now
        idleRecord.manualStopDate = now
        UserDefaultsPersistence().save(idleRecord)

        AlarmKitScheduler.cancelAllAlarmsAndClearMapping()

        LogBuffer.shared.log(.info, "TurnOffBlinkBreakIntent: session stopped from alarm UI")

        return .result()
    }
}
