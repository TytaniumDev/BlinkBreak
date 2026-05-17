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
import os

/// Unified logging — `LogBuffer.shared` is a per-process singleton, so it would
/// silently drop messages when the intent runs in a separate process (the system
/// can route LiveActivityIntents to an intent host while the app is suspended or
/// killed). `os.Logger` writes to the system log and is reachable from any
/// process, including via `log show --predicate 'subsystem == "..."'`.
private let intentLogger = Logger(
    subsystem: "com.tytaniumdev.BlinkBreak",
    category: "TurnOffBlinkBreakIntent"
)

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
        // Set unconditionally even though `SessionController.stop()` only sets it
        // inside the schedule window. `ScheduleEvaluator.shouldBeActive` only
        // honours the stop date when it falls inside today's window, so the
        // extra timestamp outside the window is a harmless no-op — and the
        // in-window case is exactly the one we need to suppress auto-restart for.
        // We don't load WeeklySchedule here because the evaluator's gate makes
        // a conditional write redundant.
        idleRecord.manualStopDate = now
        UserDefaultsPersistence().save(idleRecord)

        AlarmKitScheduler.cancelAllAlarmsAndClearMapping()

        intentLogger.info("session stopped from alarm UI")

        return .result()
    }
}
