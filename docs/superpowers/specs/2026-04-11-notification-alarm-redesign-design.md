# BlinkBreak Notification Alarm Redesign — Design Spec

**Date:** 2026-04-11
**Status:** Approved for implementation planning
**Scope:** Replace the 6-notification iPhone cascade with a Watch-owned extended runtime session + repeating haptic, plus a single iPhone fallback notification with a custom 30-second alarm sound. Also fixes the Watch "Start break" action visibility bug.

---

## Problem

The current V1 design schedules six local notifications per break cycle on iOS (1 primary + 5 nudges) with a shared `thread-identifier`, intending to create a 25-second alarm-like wrist buzz. In practice:

1. **Too many notifications to clean up.** On Apple Watch, the six forwarded notifications don't collapse the way the iPhone Notification Center groups them. The user ends up with a stack of notification entries to manually dismiss after every break.
2. **Only "Dismiss" on the Watch.** The `BLINKBREAK_BREAK_CATEGORY` is registered on both iPhone and Watch, but in practice the "Start break" action only appears via long-press on the iPhone banner. On the wrist, the user sees only Dismiss and has to open the app to start a break.
3. **Not actually alarm-like.** Each of the six notifications produces one standard notification haptic. The user wanted "buzzes in a distinct pattern until I tap Start break" — true alarm-style behavior. The cascade approximates this but only loosely.

The original design choice was made under the false premise that iOS has no API for "repeat haptic until acknowledged." That was wrong. `WKExtendedRuntimeSession` together with `notifyUser(hapticType:repeatHandler:)` is designed for exactly this pattern — third-party alarm/wake apps use it to hold the Watch app alive in the background and pulse haptics on a custom schedule until the user dismisses.

## Goals

1. **One notification per break cycle on each device.** Single Notification Center entry, single thing to dismiss.
2. **Real alarm-like behavior.** A persistent wrist buzz that repeats on a custom pattern for ~30 seconds or until the user acknowledges, whichever comes first.
3. **"Start break" action visible on the Watch notification without long-press.** Tap the action directly from the wrist.
4. **Acknowledge on either device dismisses both.** Tapping "Start break" on the iPhone or Watch instantly cancels the corresponding notification on the other device and stops any in-progress haptic loop.
5. **Graceful fallback.** If the Watch extended runtime session can't run (Watch dead, app killed, OS reclaimed session), iPhone still fires an alarming single notification with a ~30-second custom alarm sound.
6. **No cascade, ever.** `buildBreakCascade` and all its associated constants and tests are deleted.

## Non-goals

- Critical alerts (`.critical` interruption level). Requires a special entitlement from Apple, and the use case doesn't justify requesting it. Time-sensitive is sufficient.
- Background audio sessions on iOS. The iPhone fallback uses a custom 30-second notification sound, not an audio session, avoiding the need for the background-audio entitlement.
- Configurable break interval or duration. V1 remains hardcoded to 20 minutes / 20 seconds.
- A new SwiftUI view for the break-active state. The existing `BreakActiveView` is unchanged.
- Changes to the watch-to-phone command forwarding path (`WatchCommand`). That stays exactly as it is.

## Architecture overview

Two devices, each independently responsible for alarming the user, with WCSession used for acknowledgment sync.

### iPhone side

- **One `.timeSensitive` notification per cycle**, scheduled at `cycleStartedAt + breakInterval` (T+20:00). Replaces the 6-notification cascade.
- **Custom notification sound**: `break-alarm.caf`, a ~29-second pulsing beep pattern added to the iOS app bundle. When the notification fires, iOS plays the custom sound for its full duration unless dismissed earlier.
- **Attached category**: `BLINKBREAK_BREAK_CATEGORY` with the existing "Start break" action. Unchanged.
- **No more cascade.** One Notification Center entry. One thing to dismiss.

### Watch side

- When the user taps Start (on iPhone or Watch), the Watch begins a `WKExtendedRuntimeSession`. The exact `SessionType` is TBD at implementation time — the candidates are `.selfCare`, `.mindfulness`, and `.physicalTherapy`. `.selfCare` is the preferred choice (20-20-20 eye rest is clearly a self-care activity) but the final pick depends on verifying the API surface against Apple's current watchOS 11 documentation. Extended runtime sessions run up to ~1 hour for these session types, well beyond a 20-minute cycle.
- The session keeps the Watch app alive in the background for the duration of the cycle. An indicator appears on the watch face showing BlinkBreak is running. The user can still use the Watch normally.
- Inside the session, a `DispatchSourceTimer` is scheduled for the cycle's break fire date.
- **At T+20:00**, three things happen atomically:
  1. Watch calls `session.notifyUser(hapticType: .notification, repeatHandler: ...)`. The system repeatedly invokes the repeat handler at a cadence it controls; on each invocation the handler returns the next haptic type and a continuation flag. Our handler counts invocations or elapsed time and returns `stop: true` after ~30 seconds of pulses, or immediately if a `disarmed` flag has been set by an incoming acknowledgment. The exact cadence between haptics is system-controlled — we control total duration and early termination, not pace.
  2. Watch posts a `.timeSensitive` Watch-local notification via `UNUserNotificationCenter.current().add(...)` carrying the `BLINKBREAK_BREAK_CATEGORY` category. This is what gives the user a tappable notification entry with the "Start break" action directly on the wrist.
  3. Watch transitions its `SessionController.state` to `.breakActive`.
- When the user taps "Start break" (notification action or the in-app button), the Watch's `handleStartBreakAction(cycleId:)` runs, which calls `alarm.disarm(cycleId:)`, cancels the Watch's delivered notification, persists the new SessionRecord, broadcasts the new snapshot via WCSession, and re-arms the alarm for the next cycle.

### Acknowledgment sync

- When either device runs `handleStartBreakAction`, it broadcasts the new `SessionSnapshot` via `connectivity.broadcast(_:)` as it does today.
- **New:** the other device processes incoming snapshots via a new `SessionController.handleRemoteSnapshot(_:)` method, wired via `connectivity.onSnapshotReceived`. When a snapshot represents a "break just got acknowledged remotely" transition (incoming `lookAwayStartedAt != nil` while the local record had `lookAwayStartedAt == nil`), the local device:
  1. Cancels delivered notifications for the acknowledged `cycleId` via `scheduler.cancel(identifiers:)`.
  2. Calls `alarm.disarm(cycleId:)` to stop any in-progress haptic loop (no-op on iPhone because iPhone uses `NoopSessionAlarm`).
  3. Saves the new `SessionRecord` from the snapshot.
  4. Calls `reconcileOnLaunch()` to recompute local state.

The general rule: **the device that receives the user's tap runs `handleStartBreakAction` locally. The other device processes the incoming snapshot as a "somebody else acknowledged, clean up your local state" event.** No single source of truth; both are authoritative for the cycle, and they reconcile idempotently.

## Components

### New: `SessionAlarmProtocol` (in `BlinkBreakCore`)

```swift
/// Abstracts "hold an extended runtime session and fire a repeating haptic at a specific time."
/// Injected into SessionController so the iPhone target can use a Noop implementation while
/// the Watch target uses WKExtendedRuntimeSessionAlarm.
public protocol SessionAlarmProtocol: Sendable {
    /// Called when a new cycle begins. The implementation should prepare its alarm machinery
    /// to fire a repeating haptic at `fireDate`, continuing until `disarm(cycleId:)` is called
    /// for the matching cycleId or until an internal maximum duration is reached.
    func arm(cycleId: UUID, fireDate: Date)

    /// Called when the user acknowledges a break (on either device) or stops the session.
    /// Must be idempotent; calling disarm for a cycleId that isn't armed is a no-op.
    func disarm(cycleId: UUID)
}
```

### New: `NoopSessionAlarm` (in `BlinkBreakCore`)

Used on iPhone (iOS doesn't host the extended runtime session — that's the Watch's job) and in tests that don't care about the alarm path. Arm and disarm are no-ops. ~15 lines.

### New: `WKExtendedRuntimeSessionAlarm` (in `BlinkBreak Watch App/`)

Conforms to `SessionAlarmProtocol`. Lives in the Watch target, not in `BlinkBreakCore`, because it imports `WatchKit` and `UserNotifications`. Holds three pieces of mutable state: the current `cycleId`, the current `WKExtendedRuntimeSession` instance, and a `DispatchSourceTimer` for the delay until `fireDate`. Also holds a `disarmed: Bool` flag and an iteration counter used by the repeat handler closure.

- `arm(cycleId:fireDate:)`:
  1. Disarms any previously-armed cycle (defensive).
  2. Creates a new `WKExtendedRuntimeSession`, sets itself as delegate, calls `start()`.
  3. Creates a `DispatchSourceTimer` scheduled for `fireDate`. When the timer fires:
     - Calls `session.notifyUser(hapticType: .notification, repeatHandler: { [weak self] elapsed in self?.nextRepeat(elapsed) ?? (.notification, true) })`. The repeat handler signals stop when `elapsed >= 30` seconds or `disarmed == true`. System controls invocation cadence; we control when to terminate.
     - Posts a `.timeSensitive` Watch-local notification with identifier `break.primary.<cycleId>` and category `BLINKBREAK_BREAK_CATEGORY`.
- `disarm(cycleId:)`:
  1. If `cycleId` doesn't match the currently-armed cycle, return.
  2. Set `disarmed = true` so the next repeat handler invocation exits the loop.
  3. Cancel the `DispatchSourceTimer`.
  4. Call `session.invalidate()`.
  5. Remove delivered Watch-local notifications for that `cycleId`.
- `WKExtendedRuntimeSessionDelegate` handling:
  - `extendedRuntimeSessionDidStart`: logged.
  - `extendedRuntimeSessionWillExpire`: logged, no renewal attempt (20-minute cycle is well under the ~1 hour limit; if this fires, something is wrong and iPhone fallback will still alert the user).
  - `extendedRuntimeSession(_:didInvalidateWith:error:)`: clears local references.

### New: `MockSessionAlarm` (in `Tests/BlinkBreakCoreTests/Mocks/`)

Records every `arm(cycleId:fireDate:)` and `disarm(cycleId:)` call. Exposes `armedCalls: [(UUID, Date)]` and `disarmedCycleIds: [UUID]` for test assertions. Same shape and style as `MockNotificationScheduler`.

### Modified: `SessionController`

- Gains a new injected dependency: `alarm: SessionAlarmProtocol`.
- `start()`: after scheduling the break notification, calls `alarm.arm(cycleId: cycleId, fireDate: cycleStartedAt + breakInterval)`.
- `handleStartBreakAction(cycleId:)`: calls `alarm.disarm(cycleId:)` before scheduling the next cycle's notification, then `alarm.arm(cycleId: nextCycleId, fireDate: nextCycleStartedAt + breakInterval)` for the new cycle.
- `stop()`: calls `alarm.disarm(cycleId: currentCycleId)` if a cycle was active.
- `reconcileOnLaunch()`: when the reconciliation result is `.running`, also calls `alarm.arm(cycleId: currentCycleId, fireDate: cycleStartedAt + breakInterval)` so re-opening the Watch app mid-cycle restores the alarm. On iPhone this is a no-op because `alarm` is `NoopSessionAlarm`.
- **New method `handleRemoteSnapshot(_:)`**: called from `connectivity.onSnapshotReceived`. Implements the acknowledgment-sync rule described above. Idempotent: handling the same snapshot twice produces the same end state.
- **Renamed `wireUpWatchCommands()` → `wireUpConnectivity()`**: now wires both `onCommandReceived` (unchanged from today) and `onSnapshotReceived` (new) on the connectivity object.

### Modified: `NotificationScheduler` / `ScheduledNotification`

- `ScheduledNotification` gains one new field: `soundName: String?`. When non-nil, `UNNotificationScheduler.schedule(_:)` sets `content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))`; otherwise it sets `content.sound = .default`.
- No other changes to the scheduler protocol or implementation.

### Modified: `CascadeBuilder` → break + done builders

- **Deleted**: `CascadeBuilder.buildBreakCascade(cycleId:cycleStartedAt:)`.
- **Added**: `CascadeBuilder.buildBreakNotification(cycleId:cycleStartedAt:)` — returns one `ScheduledNotification` with `identifier = "break.primary.<cycleId>"`, `soundName = "break-alarm.caf"`, `isTimeSensitive = true`, `threadIdentifier = cycleId.uuidString`, `categoryIdentifier = BLINKBREAK_BREAK_CATEGORY`.
- `CascadeBuilder.buildDoneNotification(cycleId:lookAwayStartedAt:)` unchanged.
- `CascadeBuilder.identifiers(for:)` collapses to `[breakPrimaryId, doneId]` — two identifiers instead of seven.
- `CascadeBuilder` is no longer strictly a "cascade" builder. Keeping the name to minimize churn in tests and call sites; it now just builds individual notifications for a cycle.

### Modified: `SessionRecord`

- Gains one new field: `lastUpdatedAt: Date?`. Defaults to `nil` in the Codable decoder so existing persisted records remain readable without migration. Updated to the current clock on every local mutation that saves the record, and copied from `snapshot.updatedAt` when `handleRemoteSnapshot` saves an incoming snapshot. Used by the staleness guard in `handleRemoteSnapshot` to drop out-of-order snapshot deliveries: `guard snapshot.updatedAt > (local.lastUpdatedAt ?? .distantPast) else { return }`.
- Gains a convenience initializer: `init(from snapshot: SessionSnapshot)` that maps the snapshot fields directly and sets `lastUpdatedAt = snapshot.updatedAt`. ~10 lines.

### Modified: `BlinkBreakConstants`

- **Deleted**: `nudgeInterval`, `nudgeCount`, `breakNudgeIdPrefix`.
- **Unchanged**: everything else. The notification category ID, action ID, break interval, look-away duration, and persistence key all stay the same.

### Modified: `BlinkBreakApp` (iPhone target)

- Injects `NoopSessionAlarm()` into `SessionController`'s new `alarm:` parameter.
- Calls `controller.wireUpConnectivity()` instead of `wireUpWatchCommands()` on first appear.

### Modified: `BlinkBreakWatchApp` (Watch target)

- Injects `WKExtendedRuntimeSessionAlarm()` into `SessionController`'s `alarm:` parameter.
- Calls `controller.wireUpConnectivity()` on first appear. Deletes the placeholder `wireUpSnapshotReceiver()` helper, which is currently a no-op.

## Data flow — a typical cycle

### Happy path (Watch connected, user acks on Watch)

1. User taps Start on iPhone `RootView`.
2. iPhone `SessionController.start()` runs:
   - `scheduler.cancelAll()` clears stale state.
   - Creates `cycleId` and `cycleStartedAt`.
   - Persists `SessionRecord`.
   - `scheduler.schedule(CascadeBuilder.buildBreakNotification(...))` — one notification at T+20:00 with custom alarm sound.
   - `alarm.arm(cycleId: cycleId, fireDate: T+20:00)` — no-op on iPhone (NoopSessionAlarm).
   - `state = .running(...)`.
   - `connectivity.broadcast(snapshot)`.
3. Watch receives the snapshot via `onSnapshotReceived` → `handleRemoteSnapshot`. Local record is updated, state becomes `.running`, `reconcileOnLaunch` runs.
4. Inside reconciliation on Watch, state is `.running` → `alarm.arm(cycleId, fireDate)` runs. `WKExtendedRuntimeSessionAlarm` starts a session and schedules a `DispatchSourceTimer` for T+20:00.
5. 20 minutes pass. iPhone notification fires at T+20:00 with the 30-second alarm sound. Watch's `DispatchSourceTimer` fires simultaneously, which (a) calls `session.notifyUser(hapticType:repeatHandler:)` kicking off the repeating haptic loop, (b) posts the Watch-local break notification, (c) transitions Watch state to `.breakActive`.
6. User taps "Start break" on the Watch notification (directly from the wrist — no long-press needed).
7. `WatchAppDelegate.didReceive` fires → `controller.handleStartBreakAction(cycleId:)`:
   - `alarm.disarm(cycleId:)` flips the `disarmed` flag; next repeat handler call returns `keepGoing: false` (sub-second). Session is invalidated. Watch-local delivered notification is removed.
   - `scheduler.cancel(identifiers: [break.primary.<cycleId>, done.<cycleId>])` for this cycle.
   - Schedules `doneNotification` for the new look-away window.
   - Schedules the next cycle's break notification.
   - `alarm.arm(nextCycleId, nextFireDate)` re-arms a fresh session for the next cycle.
   - Persists new `SessionRecord`.
   - `state = .lookAway(...)`.
   - `connectivity.broadcast(snapshot)`.
8. iPhone receives the new snapshot via `handleRemoteSnapshot`:
   - Detects that `lookAwayStartedAt` is newly set → "break was acked remotely."
   - Calls `scheduler.cancel(identifiers:)` for the completed cycle's break notification — this removes the iPhone's *delivered* notification from Notification Center, which is what makes "tap on Watch = iPhone notification disappears" work.
   - `alarm.disarm(cycleId:)` — no-op (NoopSessionAlarm).
   - Saves the incoming record, calls `reconcileOnLaunch`.

### Fallback path (Watch not connected)

1. User taps Start on iPhone. iPhone does exactly the same things; the `connectivity.broadcast(snapshot)` call goes into the void because the Watch isn't reachable. `alarm.arm(...)` is a no-op as always on iPhone.
2. Watch never receives the snapshot; Watch never arms its alarm; Watch is silent.
3. At T+20:00, iPhone's scheduled notification fires with the 30-second custom alarm sound. User hears the alarm from the iPhone speaker.
4. User taps "Start break" on the iPhone notification (or opens the app and taps the in-app button).
5. `AppDelegate.didReceive` fires → `controller.handleStartBreakAction(cycleId:)`. Same as steps 7 and 8 from the happy path, minus the Watch-side effects.

### Edge case: both devices alarming concurrently (Watch connected, user hasn't tapped yet)

At T+20:00, both the iPhone speaker alarm and the Watch haptic loop fire simultaneously. User taps Start break on whichever they notice first. The acknowledgment-sync path (handleRemoteSnapshot receiving the new snapshot) cancels the delivered notification on the other device and stops the haptic loop. Both devices land in `.lookAway` with no dangling state.

## Edge cases

| Scenario | Behavior |
|---|---|
| Watch app killed by OS mid-cycle | Extended runtime session dies. iPhone notification still fires at T+20:00 (iPhone fallback covers it). On next Watch app launch, `reconcileOnLaunch()` re-arms a fresh session for the remaining time in the cycle. |
| Watch rebooted | Same as above — iPhone fallback covers the missed alarm, Watch re-arms on next launch. |
| Watch in airplane mode | WCSession state sync is dropped, but Watch's local alarm + notification still fire correctly. iPhone operates independently. When connectivity returns, the snapshots reconcile. |
| User stops session during the haptic loop | `stop()` → `alarm.disarm(cycleId:)` → haptic loop exits sub-second, session invalidated, notification removed. |
| Low Power Mode on Watch | Haptics may be muted per Apple's rules. Acceptable degradation — iPhone audio fallback still fires. |
| User takes >30 seconds to acknowledge | Haptic loop auto-stops after ~30 seconds of elapsed time. Watch-local notification stays visible in Notification Center until tapped or dismissed. State stays `.breakActive` until reconciliation figures out the cycle lapsed — uses the same "pending notifications for cycleId" check as today's Case 5 in `reconcileOnLaunch()`, adjusted to check for the single break notification instead of the cascade. |
| `handleRemoteSnapshot` called twice with the same snapshot | Idempotent: second call's `scheduler.cancel(...)` and `alarm.disarm(...)` are both no-ops (the notification is already gone, the alarm is already disarmed). |
| iPhone ack happens concurrently with Watch ack | Whichever broadcasts its snapshot first wins. The second broadcast is either a duplicate (same cycleId, same lookAwayStartedAt) — idempotent — or a newer cycle that supersedes. Because the snapshot has `updatedAt`, the receiving side can skip stale snapshots via a `snapshot.updatedAt > local.lastUpdatedAt` guard. |

## Assets & build configuration

### `break-alarm.caf`

- ~29 seconds (just under iOS's 30-second max for custom notification sounds).
- Pulsing 2-tone beep pattern at a moderate volume — "soft alarm clock" feel, not a fire alarm.
- Generated deterministically by `scripts/sound/generate-alarm.sh`, which produces `BlinkBreak/Resources/Sounds/break-alarm.caf`. The generation script uses a command-line audio tool (`sox` or equivalent) to synthesize the beeps and convert to CAF format. The script lives alongside `scripts/icon/` as a sibling pattern.
- Committed to the repo as a binary blob. Regeneratable from the script.

### `project.yml` changes

- Add `BlinkBreak/Resources/Sounds/` as a resource directory on the iOS target. The Watch target does not need this file — Watch uses the default notification sound (the haptic is doing the work, not audio).
- Run `xcodegen generate` to refresh `BlinkBreak.xcodeproj`.

### Entitlements & Info.plist

- **No changes.** Extended runtime sessions of type `.selfCare` don't require any special entitlement. The existing `.timeSensitive` + alert + sound notification permissions cover the iPhone side. `.critical` interruption level (which requires Apple approval) is explicitly not used.

## Testing strategy

### Existing test groups and how they shift

- **`NotificationSchedulerTests.swift`**: assertions against `buildBreakCascade` → rewritten against `buildBreakNotification`. Assertions of "6 notifications with shared thread" → "1 notification with thread, identifier, category, soundName, time-sensitive flag." `identifiers(for:)` returning 7 ids → returning 2. ~5–6 test cases updated.
- **`SessionControllerTests.swift`**: tests asserting "after `start()`, 6 notifications scheduled" → "after `start()`, 1 notification scheduled **and** `alarm.arm(cycleId, fireDate)` called once with correct args." Tests asserting `handleStartBreakAction` cancels 6 ids → cancels 2 and calls `alarm.disarm(cycleId)` once. ~15 test cases updated, 3–4 new test cases added for `handleRemoteSnapshot`.
- **`ReconciliationTests.swift`**: Case 4 (running → still running) gains an assertion that `alarm.arm(...)` was called exactly once with the remaining fire date. New test: "reconcile-on-launch re-arms a fresh alarm after a simulated Watch kill." ~2–3 test cases touched, 1–2 added.
- **`PersistenceTests.swift`** and **`MockWatchConnectivity.swift`**: unchanged.

### New test-only mock

- **`MockSessionAlarm`** in `Tests/BlinkBreakCoreTests/Mocks/`. Records `arm` and `disarm` calls. Same style as `MockNotificationScheduler`. Injected into `SessionController` in every test that constructs one.

### New tests

- `SessionControllerTests.test_handleRemoteSnapshot_remoteAckCancelsDeliveredNotifications` — incoming snapshot with fresh `lookAwayStartedAt` triggers `scheduler.cancel(identifiers:)` for the acked cycleId.
- `SessionControllerTests.test_handleRemoteSnapshot_remoteAckDisarmsAlarm` — same incoming snapshot triggers `alarm.disarm(cycleId:)`.
- `SessionControllerTests.test_handleRemoteSnapshot_idempotentDoubleDelivery` — calling `handleRemoteSnapshot` twice with the same snapshot produces the same end state and doesn't duplicate work.
- `SessionControllerTests.test_handleRemoteSnapshot_staleSnapshotIgnored` — snapshot with `updatedAt` older than local record is ignored.
- `ReconciliationTests.test_reconcile_reArmsAlarmMidCycle` — simulated "Watch app relaunched mid-cycle" flow re-arms the alarm for the remaining time.

### Updated test helper

- If no shared factory exists, add `makeTestController(...)` in a new helper file so that adding the `alarm:` parameter doesn't require touching every `SessionController(...)` construction. If one exists, update it.

### What's not unit-tested (and why that's acceptable)

- `WKExtendedRuntimeSessionAlarm` itself, because it imports `WatchKit` and can't live in `BlinkBreakCore`. Its logic is thin: arm → start session + schedule timer + post notification + start haptic loop on fire; disarm → invalidate + cancel + remove. Interesting behavior is exercised at the `SessionController` level via `MockSessionAlarm`. Hand-verified on-device, consistent with how `UNNotificationScheduler` is treated today.
- The 30-haptic repeat handler closure. Its *contract* ("haptics eventually stop, and stop immediately on disarm") is validated via `MockSessionAlarm` observing `disarm` calls during ack tests.

### Lint compliance

- `SessionAlarmProtocol`, `NoopSessionAlarm`, and `MockSessionAlarm` all live in or reference `BlinkBreakCore` and import only `Foundation`. Zero `WatchKit` / `UIKit` / `SwiftUI` imports inside the core package. `scripts/lint.sh`'s forbidden-import scan stays green.

## Migration

- `SessionRecord` schema gains one new **optional** field (`lastUpdatedAt: Date?`), which is backwards-compatible with the existing Codable encoding: old records decode cleanly with `lastUpdatedAt = nil`, and the staleness guard handles `nil` by treating it as `.distantPast` so the first incoming snapshot is always applied. Existing users with a live session when they update will have their record read as-is, `reconcileOnLaunch` will figure out the state, and the next `handleStartBreakAction` will start using the new single-notification format. No migration code needed.

## Risks

- **`handleRemoteSnapshot` interleaving with local reconciliation.** The new remote-ack code path mutates persistence and calls `reconcileOnLaunch`. There's a risk it races with a concurrent local `reconcileOnLaunch` triggered from a foreground event and produces double-cancels or inconsistent state. Mitigation: idempotency of `cancel`/`disarm`, the `snapshot.updatedAt > local.lastUpdatedAt` staleness guard, and the "double-delivery" test case. Since `SessionController` is `@MainActor`, all mutations serialize on the main actor — no true concurrency, just interleaving, which is covered by idempotency.
- **`WKExtendedRuntimeSession` quirks.** The API has known sharp edges (sessions dying on low battery, not running while the Watch is on the charger, etc.). The iPhone fallback exists specifically to insulate users from these quirks. Device testing across iPhone + Watch is required before this can be shipped.
- **Custom alarm sound volume.** A 30-second alarm sound will be annoying if set too loud or too shrill. The generated `.caf` file needs to be auditioned before shipping and tweaked for tone/volume. This is a judgment call rather than a technical risk, but it's worth a pre-merge audition step.
- **PR size.** This touches `BlinkBreakCore` (against the usual "visual iteration PRs don't touch core" rule), the iPhone target, the Watch target, and the test suite. Splitting the PR would leave intermediate states where the cascade is partially removed or the alarm protocol exists but isn't injected anywhere. One coherent PR is the right call despite the size.

## Open questions

None at design-approval time. Implementation will surface smaller decisions (exact haptic cadence timing, exact sound envelope for `break-alarm.caf`) that will be handled inside the implementation plan or during PR review.

## Suggested PR shape

One PR touching:
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/` (SessionAlarmProtocol, NoopSessionAlarm, SessionController, CascadeBuilder, Constants, ScheduledNotification, SessionRecord convenience init)
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/` (MockSessionAlarm, updated + new test cases)
- `BlinkBreak/` (BlinkBreakApp injection, AppDelegate unchanged, Resources/Sounds/break-alarm.caf added)
- `BlinkBreak Watch App/` (WKExtendedRuntimeSessionAlarm, BlinkBreakWatchApp injection + wireUpConnectivity rename)
- `project.yml` (resource directory)
- `scripts/sound/generate-alarm.sh` (new generator)

Estimated diff: ~400 lines added, ~150 lines removed, ~40 test cases updated.
