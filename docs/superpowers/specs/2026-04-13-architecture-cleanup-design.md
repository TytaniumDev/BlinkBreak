# Architecture Cleanup Design

**Date:** 2026-04-13
**Goal:** Simplify the codebase for readability, clean API surfaces, and proper separation of concerns. A human should be able to easily read the code and figure out what is happening.

---

## Change 1: State rename — `breakActive` → `breakPending`, `lookAway` → `breakActive`

The current state names are misleading. `breakActive` currently means "notification fired, waiting for user acknowledgment" — the break isn't actually active yet. `lookAway` means "user is actively taking the break" — which is when the break IS active.

### Rename mapping

| Current | New | Meaning |
|---------|-----|---------|
| `.breakActive(cycleStartedAt:)` | `.breakPending(cycleStartedAt:)` | Notification fired, awaiting user confirmation |
| `.lookAway(lookAwayStartedAt:)` | `.breakActive(startedAt:)` | User confirmed, actively looking away |

### Scope

- `SessionState` enum cases and associated value labels
- `SessionRecord.lookAwayStartedAt` → `SessionRecord.breakActiveStartedAt` (with `CodingKeys` mapping to `"lookAwayStartedAt"` for backwards compatibility with existing persisted data)
- `SessionSnapshot.lookAwayStartedAt` → `SessionSnapshot.breakActiveStartedAt` (with `CodingKeys` mapping to `"lookAwayStartedAt"` for wire compatibility — an old Watch may send/receive the old key name)
- All `switch` sites in `SessionController`, views, tests, and previews
- Accessibility identifiers: `button.lookAway.stop` → `button.breakActive.stop`, `label.lookAway.message` → `label.breakActive.message`, `button.breakActive.startBreak` → `button.breakPending.startBreak`, etc.
- View file names: `LookAwayView` → `BreakActiveView` (current `BreakActiveView` → `BreakPendingView`), same for Watch views
- `SessionState.description` / `CustomStringConvertible` strings

### Behavior change

None. This is a mechanical rename.

---

## Change 2: Eliminate the 1-second polling timer from RootView / WatchRootView

The current design has `Timer.publish(every: 1)` in both `RootView` and `WatchRootView` that calls `reconcileOnLaunch()` every second, in every state — even `idle`. This is wasteful and architecturally wrong: state transitions should be event-driven, not discovered by polling.

### New approach — notification-driven transitions

1. **Remove the timer** from both `RootView` and `WatchRootView` entirely.
2. **`AppDelegate.willPresent`** (called by iOS when a notification fires while the app is foregrounded) calls `controller.reconcile()`. This flips the UI from `running → breakPending` at the exact moment the notification fires.
3. **`WatchAppDelegate.willPresent`** does the same on Watch.
4. **`onAppear`** still calls `reconcile()` once — handles app launch, foregrounding, and the case where the notification fired while the app was backgrounded.
5. **`scenePhase` change** (`.background → .active`) also calls `reconcile()` once — handles the user switching back to the app.

### Countdown UI

Replace `Timer.publish` + `@State private var now` in `RunningView` and `WatchRunningView` with `TimelineView(.periodic(every: 1))`. This is the SwiftUI-native primitive for periodic view redraws — it integrates with SwiftUI's rendering pipeline and automatically pauses when the view isn't visible.

### `breakActive → running` transition (was `lookAway → running`)

Same pattern. The "done" notification fires at `breakActiveStartedAt + 20s`. `willPresent` (foreground) or `onAppear` (relaunch) triggers `reconcile()`.

### Net result

Zero timers at the root level. One `TimelineView` scoped to the countdown view, only active when `running`. Notification delivery is the single event source for state transitions.

---

## Change 3: Rename `reconcileOnLaunch()` → `reconcile()`

With the polling timer gone, this method is called from notification callbacks, `onAppear`, and `scenePhase` changes — not "on launch." Rename to `reconcile()` everywhere: protocol, implementation, call sites.

Updated doc comment:

> Rebuilds in-memory state from persistence + clock. Called on app launch, foregrounding, and notification delivery. Never trusts in-memory state.

---

## Change 4: Eliminate the double-write in `evaluateSchedule()`

`evaluateSchedule()` currently calls `start()` (which saves a `SessionRecord`), then immediately loads it back, patches `wasAutoStarted = true`, and saves again. Two persistence writes to accomplish one thing.

### Fix

Extract `private func startSession(wasAutoStarted: Bool = false)` containing the core start logic. The public `start()` calls `startSession(wasAutoStarted: false)`. `evaluateSchedule()` calls `startSession(wasAutoStarted: true)`. Single write, clear intent.

---

## Change 5: Move schedule status text logic into BlinkBreakCore

`ScheduleStatusLabel` (a view component at `BlinkBreak/Views/Components/ScheduleStatusLabel.swift`) contains 35 lines of business logic: computing "Starts at 9:00 AM" / "Active until 5:00 PM" / "Next: Mon 9:00 AM" by manually inspecting the schedule's day windows and scanning forward 7 days. This duplicates logic in `ScheduleEvaluator` and is only testable via SwiftUI previews.

### Fix

Add `func statusText(at date: Date, calendar: Calendar) -> String?` to `ScheduleEvaluator`. It uses the existing schedule closure internally, plus day-window inspection for the specific label text. `ScheduleStatusLabel` becomes a thin view that renders whatever the evaluator returns. The logic gets unit-tested alongside the rest of the schedule code.

The `formatScheduleTime(hour:minute:)` helper currently in `TimeFormatting.swift` (view layer) will need to be available in BlinkBreakCore. Either move it into the evaluator or add a small formatting helper in Core.

---

## Change 6: Remove `SessionState.name`, simplify `DiagnosticCollector`

### 6a: Delete `SessionState.name`

`SessionState` has both `.name` and `.description` returning identical strings. Delete `.name`. Callers use `.description` or string interpolation.

### 6b: `DiagnosticCollector` takes `SessionState` instead of `String`

Change the init parameter from `sessionState: String` to `sessionState: SessionState`. The collector calls `.description` internally. The call site simplifies from `sessionState: controller.state.description` to `sessionState: controller.state`.

---

## Change 7: Move schedule category registration into `UNNotificationScheduler.registerCategories()`

`BlinkBreakApp.onAppear` has 15 lines of boilerplate registering the schedule notification category (`BLINKBREAK_SCHEDULE_CATEGORY`). This belongs alongside the break category registration in `UNNotificationScheduler.registerCategories()`.

### Fix

Move the schedule category creation into `registerCategories()`. Both categories get registered in one place, one call, at launch. The `onAppear` block shrinks to just wiring: hand controller to AppDelegate, activate connectivity, reconcile, create ScheduleTaskManager.

---

## Change 8: Rename `ScheduleEvaluating` → `ScheduleEvaluatorProtocol`

Every other protocol in BlinkBreakCore uses the `...Protocol` suffix: `NotificationSchedulerProtocol`, `WatchConnectivityProtocol`, `PersistenceProtocol`, `SessionControllerProtocol`, `BugReporterProtocol`, `SessionAlarmProtocol`. `ScheduleEvaluating` is the outlier. Rename for consistency.

Updates: protocol declaration, `NoopScheduleEvaluator` conformance, `ScheduleEvaluator` conformance, `SessionController` dependency type, and all test usage.

---

## Out of scope (no changes)

- **`handleStartBreakAction` method length**: The 8-step numbered sequence is readable with its comments. Extracting sub-methods would move complexity without reducing it.
- **`SessionSnapshot` / `SessionRecord` overlap**: They serve different purposes (persistence vs. wire format). Merging them would couple persistence to the Watch sync protocol.
- **`WCSessionConnectivity` caching `JSONEncoder`/`JSONDecoder`**: Recently optimized intentionally. No change.

---

## Test strategy

- **Unit tests**: All existing ~46 unit tests must pass after every change. New unit tests for:
  - `ScheduleEvaluator.statusText(at:calendar:)` — the moved schedule status logic
  - Any tests that reference old state names get renamed mechanically
- **Integration tests**: Run `./scripts/test-integration.sh` after all changes are complete as final verification. Accessibility identifier renames will require updating `BlinkBreakUITestsBase.swift` (`A11y` enum).
- **Manual verification**: The timer removal (Change 2) should be tested manually in the simulator — verify the UI transitions from `running → breakPending` when the notification fires, both in foreground and after backgrounding/foregrounding.
