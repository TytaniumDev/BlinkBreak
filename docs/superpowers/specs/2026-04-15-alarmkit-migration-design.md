# AlarmKit Migration — Design Spec

**Date:** 2026-04-15
**Status:** Approved (brainstormed 2026-04-15, Tyler delegated autonomous execution)

## Context

TestFlight deploys have been broken since build 16 (2026-04-14). Builds 17–20 all failed App Store Connect validation or signing because the `WKExtendedRuntimeSession.smartAlarm` approach introduced in PR #17 can't be enabled on the multi-platform "Universal" App ID that Xcode auto-generated for BlinkBreak. The entitlement `com.apple.developer.watchkit.extended-runtime-session` is not exposed in Apple's developer portal for this App ID type.

After investigation (see `project_alarmkit_migration.md` memory), the right answer is to pivot to Apple's **AlarmKit** (iOS 26+, WWDC 2025), a purpose-built API for scheduled alarm-clock-style alerts: full-screen takeover, plays at alarm volume regardless of silent/DND/Focus, built-in action buttons. Since BlinkBreak is primarily for Tyler personally and he's on iOS 26, bumping the deployment target is acceptable.

## Goals

1. Unblock TestFlight deploys (stuck on build 16 for 24+ hours).
2. Replace the unreliable WKExtendedRuntimeSession haptic-loop approach with AlarmKit's native alarm experience.
3. Simplify the codebase by dropping the watchOS companion app entirely — its primary value (wrist haptic at break time) is now subsumed by AlarmKit firing an iOS alarm that also triggers mirrored Watch delivery via the system.
4. Preserve the existing weekly-schedule auto-start/stop feature.

## Non-Goals

- Critical Alerts entitlement. AlarmKit's alarm-volume behavior makes it unnecessary for now.
- Cross-platform support beyond iOS 26. Dropping iPadOS, macOS, tvOS, visionOS from the app's target matrix is fine — the App ID can stay multi-platform since that's cosmetic.
- Backwards compatibility with iOS 17–25. App is primarily personal-use; Tyler's on iOS 26.

## Delivery Shape

Two sequential PRs:

### PR 1 — Watch removal + UNNotification unblock

Goal: green TestFlight deploys with current iOS break-reminder behavior (UNNotification banner).

Changes:
- Delete `BlinkBreak Watch App/` directory entirely.
- Remove the `BlinkBreak Watch App` target from `project.yml`.
- Remove the `SessionAlarmProtocol` abstraction from `BlinkBreakCore` along with its Noop implementation and `alarm:` parameter in `SessionController.init`.
- Remove `WatchConnectivityProtocol` + `WCSessionConnectivity` + `NoopConnectivity` — no Watch to communicate with.
- Remove `SessionController.broadcastSnapshot(for:)` and related WCSession plumbing.
- Update `AppDelegate` / app-level wiring to drop Watch-connectivity initialization.
- Update CI workflows (`ci-shared.yml`) to drop the watchOS scheme from build/test steps.
- Update integration tests: drop Watch-specific tests. iOS state-machine tests keep passing.
- Update unit tests: drop `MockSessionAlarm` and `MockWatchConnectivity` references; any test that only existed to verify Watch wiring goes.
- Update `CLAUDE.md` to remove all Watch references.

This PR ships current iOS behavior (UNNotification break at T+20:00 with "Start break" action button) — not alarm-style yet, but functional. TestFlight unblocked.

### PR 2 — AlarmKit migration (Approach A)

Goal: replace UNNotification break-trigger with AlarmKit full-screen alarms for both beats of the cycle.

Changes:
- Bump iOS deployment target 17.0 → 26.0 in `project.yml`.
- Add `NSAlarmKitUsageDescription` to iOS `Info.plist` with a short user-facing description.
- Add a new `AlarmSchedulerProtocol` in `BlinkBreakCore` (see Architecture below).
- Implement `AlarmKitScheduler` in the iOS target as the real wrapper around `AlarmManager.shared`.
- Implement `MockAlarmScheduler` for tests.
- Rewire `SessionController`: replace `scheduler.schedule(breakNotification)` / `scheduler.schedule(doneNotification)` with `alarmScheduler.scheduleCountdown(duration:cycleId:kind:)`. Subscribe to `alarmScheduler.events` in `init` to react to alarm fires/acknowledgments.
- Remove `NotificationSchedulerProtocol` + `UNNotificationScheduler` + `CascadeBuilder` — no more notifications.
- Remove notification-category / action-button registration from `AppDelegate`.
- Update `SessionRecord` if needed to support reconciliation against AlarmKit's alarm list.
- Update tests: swap notification-mock assertions for alarm-mock assertions; keep the state-machine test suite's shape.

## Architecture (PR 2)

### `AlarmSchedulerProtocol`

Narrow protocol. Exactly the surface `SessionController` needs:

```swift
public enum AlarmKind: Sendable {
    case breakDue     // 20-minute break alarm
    case lookAwayDone // 20-second look-away completion
}

public enum AlarmEvent: Sendable {
    case fired(cycleId: UUID, kind: AlarmKind)
    case acknowledged(cycleId: UUID, kind: AlarmKind)
    case cancelled(cycleId: UUID, kind: AlarmKind)
}

public protocol AlarmSchedulerProtocol: Sendable {
    func scheduleCountdown(duration: TimeInterval, cycleId: UUID, kind: AlarmKind) async
    func cancel(cycleId: UUID) async
    func cancelAll() async
    var events: AsyncStream<AlarmEvent> { get }
    /// Query used by reconcileOnLaunch to rebuild state after app kill.
    func scheduledAlarms() async -> [ScheduledAlarm]
}

public struct ScheduledAlarm: Sendable {
    public let cycleId: UUID
    public let kind: AlarmKind
    public let fireDate: Date
}
```

`SessionController` remains ignorant of `AlarmKit` types. All framework coupling lives in `AlarmKitScheduler` in the iOS target.

### State machine

Unchanged: `idle`, `running(cycleStartedAt:)`, `breakActive(cycleId, cycleStartedAt, lookAwayStartedAt?)`, `lookAway(cycleId, lookAwayStartedAt)`. All four states retain their current meaning.

### Cycle chaining

Event-driven. `SessionController.init` calls `Task { for await event in alarmScheduler.events { handle(event) } }`. Event handlers:

- `.fired(cycleId, .breakDue)` → transition `running` → `breakActive`. AlarmKit's system UI shows the full-screen alarm with a "Start break" button.
- `.acknowledged(cycleId, .breakDue)` → user tapped "Start break". Transition `breakActive` → `lookAway`. Schedule a new `scheduleCountdown(duration: 20, kind: .lookAwayDone)`.
- `.fired(cycleId, .lookAwayDone)` → transition `lookAway` → `running`. Schedule the next 20-minute `scheduleCountdown(kind: .breakDue)` for the next cycle.
- `.acknowledged(cycleId, .lookAwayDone)` → no state change (alarm auto-dismissed). Defensive.

### Reconciliation on launch

`reconcileOnLaunch()` logic:

1. Load `SessionRecord` from persistence. If `sessionActive == false`, state = `.idle`, done.
2. Query `alarmScheduler.scheduledAlarms()` for alarms tagged with the session's `currentCycleId`.
3. Cross-reference with `SessionRecord.cycleStartedAt`, `breakActiveStartedAt`, clock:
   - Alarm scheduled for the future with `kind == .breakDue` → state = `.running`.
   - No alarm scheduled but record says `breakActiveStartedAt` is set and within last hour → state = `.breakActive`.
   - Alarm scheduled with `kind == .lookAwayDone` → state = `.lookAway`.
   - Otherwise → stale record; stop the session.

Mirrors existing reconciliation structure; just queries AlarmKit instead of the UN pending-notification queue.

### Authorization

On first `start()` attempt, call `AlarmManager.shared.requestAuthorization()`. If denied, surface a "Grant alarm permission in Settings" UI prompt; block session start until granted. No other code path requires authorization.

## Testing

- Unit tests (`swift test`): 110 existing tests. Most stay green untouched. Notification-mock-based tests rewrite against `MockAlarmScheduler`. Virtual-clock pattern unchanged.
- Integration tests: keep fast-mode env vars (`BB_BREAK_INTERVAL`, `BB_LOOKAWAY_DURATION`). Watch-specific integration tests removed in PR 1. iOS state-machine integration tests pass after PR 2 with AlarmKit driving alarms in simulator.
- Manual verification post-PR-2: install on real iPhone (Tyler's, iOS 26), observe full-screen alarm takeover at break time, tap "Start break", observe look-away countdown alarm fires 20s later, verify audio plays at alarm volume.

## Open Risks

1. **AlarmKit simulator support.** AlarmKit on the iOS simulator may not faithfully simulate full-screen alarm UI (sound/haptic limitations). Integration tests may need to verify state transitions via `MockAlarmScheduler` event injection rather than observing actual alarm UI. Mitigation: rely on unit tests for state logic; use integration tests for UI wiring only.
2. **AlarmKit API shape.** This is a new framework — some API details may differ from the spec above. Implementation may need to adapt the protocol shape to match what `AlarmManager` actually exposes (e.g., authorization flow, event stream shape). Mitigation: the protocol is a contract *we* define; we adapt the wrapper to bridge AlarmKit's actual surface.
3. **Bot review feedback on PR 2.** Gemini flagged legitimate-sounding concerns on PR 20 that turned out to be wrong (the "WKBackgroundModes is required" claim). For PR 2, I'll weigh each comment on evidence, push back where wrong, accept where right.

## Migration Sequence

1. PR 1 opens, reviewed by Gemini + Claude, feedback addressed, merged to `main`.
2. TestFlight deploy for PR 1 verified green (build 17 or higher on TestFlight).
3. PR 2 opens, reviewed, feedback addressed, merged to `main`.
4. TestFlight deploy for PR 2 verified green.
5. Tyler installs on his iPhone and manually verifies the AlarmKit break experience.
