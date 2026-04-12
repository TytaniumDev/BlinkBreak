# Weekly Schedule Feature — Design Spec

## Overview

Add a weekly schedule to BlinkBreak that automatically starts and stops break timer sessions based on per-day-of-week time windows. The user configures which days are active and sets independent start/end times for each day. A master toggle enables/disables the entire schedule without losing the per-day configuration.

## Requirements

### Core behavior

- Each day of the week has an independently configurable start time and end time (5-minute granularity).
- Each day can be individually toggled on or off.
- A master enable/disable toggle preserves all per-day configuration when disabled.
- Default schedule on first enable: Mon–Fri 9:00 AM – 5:00 PM enabled, Sat–Sun disabled.
- End time must be after start time within the same day (no midnight-crossing windows in V1).

### Auto-start

- When the current time enters a scheduled window and the session is idle, auto-start the session.
- Auto-start must work when the app is in the background or hasn't been recently opened. Exact timing is not required — best-effort via `BGAppRefreshTask`, with a local notification at start time as a reliable fallback.
- On any foreground entry, `reconcileOnLaunch()` checks the schedule and auto-starts immediately if within a window.

### Auto-stop

- When the current time exits a scheduled window, immediately stop the session. No graceful finish — cancel pending notifications and transition to idle.
- Auto-stop is driven by the 1-second `reconcileOnLaunch()` ticker when foregrounded. If backgrounded at end time, the next reconciliation (on foreground or BGTask) cleans up.

### Manual override

- If the user manually taps Stop during a scheduled window, the session stays stopped for the rest of that day's window. The app does not auto-restart until the next day's scheduled start.
- Manual Start always works regardless of schedule state.

### Watch

- iPhone-only feature. The Watch has no schedule UI and no schedule awareness.
- The Watch continues to mirror session state via `WCSession` as it does today — it receives start/stop state changes triggered by the schedule, same as manual start/stop.

## Architecture

### Data model

Two new types in `BlinkBreakCore`:

```swift
public struct DaySchedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var startTime: DateComponents   // .hour + .minute only
    public var endTime: DateComponents     // .hour + .minute only
}

public struct WeeklySchedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool             // master toggle
    public var days: [Int: DaySchedule]    // keyed by Foundation weekday (1=Sun ... 7=Sat)
}
```

`DateComponents` is used for time-of-day representation — it's already `Codable`, `Equatable`, and `Sendable`, and Foundation's `Calendar` APIs speak in terms of weekday integers 1–7. The 5-minute granularity constraint is enforced at the UI layer (picker step), not in the model.

A new optional field on `SessionRecord`:

```swift
public var manualStopDate: Date?
```

Set when the user taps Stop during a scheduled window. The `ScheduleEvaluator` checks this: if `manualStopDate` falls within today's scheduled window, `shouldBeActive` returns false. The field is implicitly cleared by the next day's window (the evaluator ignores it when it's outside the current window). Since the field is optional, existing persisted `SessionRecord` values decode cleanly with nil — no migration needed.

### ScheduleEvaluator

A pure logic type in `BlinkBreakCore` with no dependencies on UIKit, notifications, or `SessionController`. Protocol-backed for testability:

```swift
public protocol ScheduleEvaluating: Sendable {
    func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool
    func nextTransitionDate(from date: Date, calendar: Calendar) -> Date?
}

public final class ScheduleEvaluator: ScheduleEvaluating {
    private let schedule: () -> WeeklySchedule
}
```

The `schedule` parameter is a closure so it always reads the latest persisted value.

**`shouldBeActive` logic:**

1. If `schedule.isEnabled` is false → return false.
2. Get today's weekday from `calendar` → look up `days[weekday]`.
3. If that day is nil or `isEnabled` is false → return false.
4. If current time is between `startTime` and `endTime` → candidate for active.
5. If `manualStopDate` is non-nil and falls within today's window → return false.
6. Otherwise → return true.

**`nextTransitionDate` logic:**

Scans forward from `date` to find the next time the `shouldBeActive` answer flips (entering or exiting a window). Used to schedule the next `BGAppRefreshTask` and start-time notification. Scans up to 7 days ahead; returns nil if no days are enabled.

The `Calendar` parameter is injected rather than using `Calendar.current` so tests can use a fixed calendar with a known first-weekday and timezone.

### SessionController integration

Minimal changes to `SessionController`:

**New dependency:** `ScheduleEvaluating` added to `SessionController`'s init, defaulting to a no-op evaluator that always returns false (preserves existing behavior for tests that don't care about scheduling).

**Changes to `reconcileOnLaunch()`:** After the existing reconciliation logic runs, a new block:

```
let shouldBeActive = evaluator.shouldBeActive(at: now, manualStopDate: record.manualStopDate, calendar: calendar)

if shouldBeActive && state == .idle {
    start()
} else if !shouldBeActive && state.isActive {
    stop()
}
```

**Changes to `stop()`:** If the evaluator says the current time is within a scheduled window, set `manualStopDate = now` on the record before persisting. Otherwise leave it nil.

No changes to `start()`, `handleStartBreakAction()`, `acknowledgeCurrentBreak()`, `SessionState`, the notification cascade, or Watch connectivity. The schedule is purely additive.

### Background task + notification fallback

Lives in the **iOS app target** (not `BlinkBreakCore`) since `BGTaskScheduler` and `UNUserNotificationCenter` are UIKit/UserNotifications APIs.

**`ScheduleTaskManager`** — a new class in the app target:

- Registers task identifier `com.tytaniumdev.BlinkBreak.scheduleCheck` in `AppDelegate.didFinishLaunching`. Also registered in `Info.plist` via `project.yml` under `BGTaskSchedulerPermittedIdentifiers`.
- When the schedule changes, or after any auto-start/auto-stop, calls `evaluator.nextTransitionDate()` and submits a `BGAppRefreshTask` for that date.
- When the task fires: creates a `SessionController` with real dependencies, calls `reconcileOnLaunch()`, then schedules the next BGTask before completing.

**Start-time notification fallback:**

- When the schedule changes or after each day's session ends, schedule a local notification for the next enabled day's start time.
- New category: `BLINKBREAK_SCHEDULE_CATEGORY` with a "Start" action.
- If the BGTask already started the session, cancel this notification.
- If the BGTask didn't fire, the notification arrives on time. User taps → app opens → `reconcileOnLaunch()` auto-starts.

**Lifecycle hooks:**

- `scenePhase .active`: `reconcileOnLaunch()` already runs via the 1-second ticker; an immediate call on foreground ensures no delay.
- Schedule changes from the UI trigger both BGTask reschedule and notification reschedule.

### Persistence

**Schedule config** gets its own `UserDefaults` key, separate from `SessionRecord`:

- Key: `BlinkBreak.WeeklySchedule`
- Stored as JSON-encoded `WeeklySchedule`
- Added to `PersistenceProtocol`:
  - `func loadSchedule() -> WeeklySchedule?`
  - `func saveSchedule(_ schedule: WeeklySchedule)`
- `InMemoryPersistence` gets matching in-memory storage for tests.

Keeping it separate avoids migration. Existing users upgrade cleanly — `loadSchedule()` returns nil, app behaves as today (manual only).

### UI

Schedule controls live directly on **IdleView**, filling the space between the header text and Start button:

- **Master toggle** at top of the schedule section ("Schedule" label + toggle).
- **7 day rows**, each showing: day name, time range (tappable), per-day toggle.
- **Tapping a time range** expands an inline `DatePicker` below that row with 5-minute increments.
- **Disabled days** show "Off" with dimmed styling; times are not tappable.
- **Start button** always visible and functional. A **status line** above the button shows schedule context: "Scheduled: starts at 9:00 AM" when outside a window, "Active until 5:00 PM" when inside one, or nothing when the schedule is disabled.
- **iPhone only** — Watch has no schedule UI, continues to mirror session state as today.

New SwiftUI views (all under `BlinkBreak/Views/`):
- `ScheduleSection.swift` — the schedule control block (master toggle + day list)
- `DayRow.swift` — individual day row component (under `Views/Components/`)
- `ScheduleStatusLabel.swift` — the status line above Start (under `Views/Components/`)

## Testing

### Unit tests (fast — run during iteration)

**ScheduleEvaluator tests:**
- `shouldBeActive` returns false when master toggle off
- `shouldBeActive` returns false for disabled day
- `shouldBeActive` returns true within a day's window
- `shouldBeActive` returns false outside the window
- `shouldBeActive` returns false when `manualStopDate` is within today's window
- `manualStopDate` from yesterday is ignored
- Boundary edge cases (exactly at start time, exactly at end time)
- `nextTransitionDate` finds next start when outside a window
- `nextTransitionDate` finds next end when inside a window
- `nextTransitionDate` wraps around to next week
- `nextTransitionDate` returns nil when no days enabled

**SessionController schedule integration:**
- `reconcileOnLaunch` auto-starts when evaluator says active and state is idle
- `reconcileOnLaunch` auto-stops when evaluator says inactive and state is running
- `reconcileOnLaunch` does not auto-start when `manualStopDate` is set for today
- `stop()` sets `manualStopDate` within a scheduled window
- `stop()` does not set `manualStopDate` outside a scheduled window

**Persistence:**
- `WeeklySchedule` JSON round-trip
- Missing schedule key returns nil
- `SessionRecord` without `manualStopDate` decodes cleanly (backward compat)

All use the existing mock/clock injection pattern.

### Integration tests (slow — final verification only)

2–3 new XCUITest tests:
- Configure schedule, verify session auto-starts within window
- Verify auto-stop when window ends
- Verify manual stop prevents auto-restart within same window

Use existing `BB_BREAK_INTERVAL` env var pattern. Add a `BB_SCHEDULE_TEST` env var to inject a test schedule so tests don't depend on real wall-clock time.

### Manual verification only

- `BGAppRefreshTask` actual firing (no simulator support)
- Schedule start-time notification delivery timing
- Watch receiving state changes triggered by auto-start/stop

## Scope boundaries

### In scope (V1)
- Per-day start/end times, per-day toggles, master toggle
- Auto-start (BGTask + notification fallback + foreground check)
- Auto-stop (immediate, via reconciliation)
- Manual stop override for current day
- iPhone UI only
- 5-minute time granularity

### Out of scope
- Midnight-crossing windows (end time must be after start time within same day)
- Multiple windows per day
- Watch schedule UI or editing
- Server-side push notifications for more reliable background start
- Siri/Shortcuts integration
- Schedule sync across devices via iCloud
