# BlinkBreak — 20-20-20 Rule iOS + watchOS App — Design

**Date:** 2026-04-10
**Target platforms:** iOS 17+, watchOS 10+
**Repo:** TytaniumDev/BlinkBreak
**Bundle ID root:** `com.tytaniumdev.BlinkBreak`

## 1. Problem

Staring at a screen for long stretches causes eye strain. The 20-20-20 rule is the standard mitigation: every 20 minutes, look at something 20 feet away for 20 seconds. The rule is effective but relies on the user remembering to do it, which defeats the purpose.

BlinkBreak is an iOS + Apple Watch app that enforces the rule via scheduled, attention-grabbing break alerts. Because the user's primary screen is typically a PC monitor or TV (not the phone), the alert surface must be the Apple Watch — specifically an alarm-style repeating haptic on the wrist that is hard to miss while gaming or working.

## 2. Goals and non-goals

### Goals
- Reliable 20-minute break reminders that fire even if the app is closed or the device rebooted.
- Alarm-style repeating wrist haptic on the Watch (30 seconds of buzzing) until the user acknowledges.
- One-tap "Start break" acknowledgment from the Watch.
- Automatic 20-second look-away timing that signals completion with a single soft haptic — no on-screen countdown (defeats the rule).
- Automatic restart of the 20-minute cycle after the look-away completes.
- SwiftUI throughout. Strict separation of UI from business logic so visuals can be iterated without risk of regressing timer behavior.
- Tests cover the full state machine and all reconciliation paths.
- CI/CD following the existing `TytaniumDev` conventions; TestFlight deployment scaffolded for use once the Apple Developer Program account is active.

### Non-goals (V1)
- Pause / resume during a running session.
- Snooze or skip on a break alert.
- Configurable durations. The 20-20-20 rule is hardcoded.
- Scheduled active hours (e.g. only run 9–17). Manual Start/Stop only in V1; the state model is designed so scheduling can be added in V2 without a rewrite.
- Critical Alerts entitlement. Not applying to Apple.
- Watch complications on the watch face. Nice to have in V2.
- Break-history / statistics tracking.
- App Store submission. TestFlight-only distribution for V1.

## 3. User flow

1. User installs the app on iPhone and Watch. Grants notification permission on first launch (required — app is useless without it).
2. User taps **Start** on the iPhone or Watch. State → `running`.
3. App schedules a cascade of six local notifications (1 primary + 5 five-second nudges) to fire at T+20:00 through T+20:25.
4. 20 minutes elapse. App is probably closed or backgrounded; user is working at their PC. The Watch fires the primary notification haptic, then nudges the wrist every 5 seconds for ~30 seconds.
5. User taps **Start break** on the Watch notification. iOS launches the app in the background. App cancels the remaining pending nudges, schedules a `done` notification at `now + 20 s`, and schedules the next cycle's cascade at `now + 20 s + 20 min`. State → `lookAway`.
6. User looks at something 20 feet away. No device screen interaction.
7. 20 seconds later, the Watch buzzes one soft tap. State → `running`. Cycle repeats.
8. User taps **Stop** at the end of their session. State → `idle`, all pending notifications cancelled.

## 4. Architecture overview

Three software units, each with one clear purpose:

### 4.1 `BlinkBreakCore` — local Swift Package

Lives at `Packages/BlinkBreakCore/`. Added as a dependency by both app targets via Xcode "Add Package Dependency → Local…". Contains **all** business logic. No `import SwiftUI`, no `import UIKit`, no `import WatchKit` — only `Foundation`, `UserNotifications`, `WatchConnectivity`, `Combine`. This boundary is enforced by a grep check in `scripts/lint.sh` that fails CI if any forbidden import appears in the package sources.

Contents:
- **`Constants.swift`** — the hardcoded 20 min / 20 sec / 5 sec nudge interval / 6 nudge count. Compile-time only; never read from `UserDefaults`.
- **`SessionState.swift`** — the four-case state enum (`idle`, `running`, `breakActive`, `lookAway`) plus the `Codable` session record that persists to `UserDefaults`.
- **`Persistence.swift`** — protocol + concrete `UserDefaultsPersistence` implementation. Reads/writes `{ sessionActive: Bool, currentCycleId: UUID, cycleStartedAt: Date }`.
- **`NotificationScheduler.swift`** — protocol + concrete `UNNotificationScheduler` implementation wrapping `UNUserNotificationCenter`. Knows how to schedule the six-notification cascade, the done notification, and cancel notifications by identifier prefix.
- **`WatchConnectivityService.swift`** — protocol + concrete `WCSessionConnectivity` implementation wrapping `WCSession`. Publishes `updateApplicationContext` for state broadcasts and handles incoming `sendMessage` commands.
- **`SessionController.swift`** — the brain. Coordinates the three services. Exposes `@Published var state: SessionState` as its only observable output. Methods: `start()`, `stop()`, `handleStartBreakAction(cycleId:)`, `reconcileOnLaunch()`. Takes protocol-typed dependencies via init so tests can inject mocks. Conforms to a `SessionControllerProtocol` so views depend on the protocol, not the class.

All services and the controller accept a `now: () -> Date` closure so tests can advance virtual time without sleeping.

### 4.2 `BlinkBreak` — iOS app target

SwiftUI only. Imports `BlinkBreakCore`. Contents:
- `BlinkBreakApp.swift` — `@main App` struct. Instantiates the singleton `SessionController` and wires up `AppDelegate`.
- `AppDelegate.swift` — conforms to `UNUserNotificationCenterDelegate`. Forwards notification action events to `SessionController.handleStartBreakAction`. Minimal surface area.
- `Views/RootView.swift` — switches on `SessionState` to render one of four child views.
- `Views/IdleView.swift` — idle state. App name + explainer text + Start button. No icon.
- `Views/RunningView.swift` — countdown ring + absolute fire time + Stop button.
- `Views/BreakActiveView.swift` — full-bleed red alert + "Start break" button. Shown only if the app is foregrounded during the cascade.
- `Views/LookAwayView.swift` — calm message, no countdown, Stop button.
- `Views/PermissionDeniedView.swift` — replaces `IdleView` if notification authorization is denied.
- `Views/Components/` — small reusable SwiftUI components: `CountdownRing`, `PrimaryButton`, `DestructiveButton`, `EyebrowLabel`, `CalmBackground`, `AlertBackground`. Each is 20–40 lines, stateless, previewable.
- `Preview/PreviewSessionController.swift` — a mock that conforms to `SessionControllerProtocol` with settable state cases. Used by SwiftUI `#Preview` macros to render each view in each state without running real session logic.

### 4.3 `BlinkBreak Watch App` — watchOS app target

Same pattern as iOS, smaller views, same shared `BlinkBreakCore` dependency:
- `BlinkBreakWatchApp.swift`
- `WatchAppDelegate.swift`
- `Views/WatchRootView.swift`
- `Views/WatchIdleView.swift`
- `Views/WatchRunningView.swift`
- `Views/WatchBreakActiveView.swift`
- `Views/WatchLookAwayView.swift`
- `Views/Components/` — Watch-sized reusable components.

### 4.4 Test target
- `BlinkBreakTests/` — unit tests for `BlinkBreakCore`. Runs via `xcodebuild test` in CI and via `swift test` locally against the package. No SwiftUI, no real notifications, no real `WCSession`.

## 5. State machine

Four states. Four user-triggered or automatic transitions.

```
    ┌──────┐
    │ idle │◄────────────┐
    └──────┘             │
       │                 │
     Start            Stop (from any state)
       │                 │
       ▼                 │
   ┌─────────┐           │
┌─►│ running │───────────┤
│  └─────────┘           │
│     │                  │
│     │ 20-min notification fires
│     ▼                  │
│ ┌──────────────┐       │
│ │ breakActive  │───────┤
│ └──────────────┘       │
│     │                  │
│     │ user taps "Start break"
│     ▼                  │
│ ┌───────────┐          │
│ │ lookAway  │──────────┘
│ └───────────┘
│     │
│     │ 20-sec notification fires
│     ▼
└─────┘
```

- **`idle`** — no session. No pending notifications. Start button visible on both devices.
- **`running`** — 20-minute countdown. Cascade notifications scheduled in advance. Countdown ring visible on both devices, with absolute fire time as reassurance on the phone view.
- **`breakActive`** — the cascade's primary notification has fired and the user has not yet acknowledged. From the controller's perspective this state is derived: if `now >= cycleStartedAt + breakInterval` and there is still at least one pending `break.*.<cycleId>` notification (meaning the user hasn't tapped Start break yet), the controller treats the state as `breakActive`. A foregrounded app shows a full-bleed red alert with a prominent Start break button; a backgrounded app stays backgrounded and lets the notification cascade do the work.
- **`lookAway`** — user has acknowledged. 20-second soft notification pending. A foregrounded app shows a calm "don't look at this screen" view with no countdown. The Watch shows a minimal "look away" message.

Transitions:
- `idle → running` (user: Start)
- `running → breakActive` (automatic: primary cascade notification delivered while app is in foreground — otherwise this state is skipped from the UI's perspective and the user only sees it after tapping the notification, but the controller infers it from `now > cycleStartedAt + 20 min`)
- `breakActive → lookAway` (user: taps Start break on notification or in app)
- `lookAway → running` (automatic: done notification fires — or equivalently, `now > lookAwayStartedAt + 20 s` at reconciliation time)
- `<any> → idle` (user: Stop)

## 6. Notification cascade mechanics

### Scheduling
When `SessionController` enters `running`, it calls `NotificationScheduler.scheduleBreakCascade(cycleId:startAt:)` which creates six `UNNotificationRequest`s sharing a single `UNNotificationCategory` called `BLINKBREAK_BREAK_CATEGORY` with one action: `"START_BREAK"` (title: "Start break"). All six share a common `thread-identifier` equal to the `cycleId.uuidString` so iOS groups them as one item in Notification Center.

| Identifier | Fire time (relative to `running` entry) | Notes |
|---|---|---|
| `break.primary.<cycleId>` | + 20:00 | Primary; triggers the cascade |
| `break.nudge.<cycleId>.1` | + 20:05 | Follow-up haptic |
| `break.nudge.<cycleId>.2` | + 20:10 | Follow-up haptic |
| `break.nudge.<cycleId>.3` | + 20:15 | Follow-up haptic |
| `break.nudge.<cycleId>.4` | + 20:20 | Follow-up haptic |
| `break.nudge.<cycleId>.5` | + 20:25 | Follow-up haptic |

All six notifications set:
- `interruptionLevel = .timeSensitive` — breaks through Focus modes.
- `sound = UNNotificationSound.default` in V1 (custom `break.caf` sound is a V2 polish item).
- `threadIdentifier = cycleId.uuidString` — collapses into one Notification Center entry.
- `categoryIdentifier = "BLINKBREAK_BREAK_CATEGORY"` — exposes the Start break action.
- `relevanceScore = 1.0` — boosts ranking in Notification Summary.

### Acknowledgment flow
When the user taps the Start break action on any of the six, iOS launches the app in the background (~30 seconds of runtime) and calls `userNotificationCenter(_:didReceive:withCompletionHandler:)` on `AppDelegate`. The delegate forwards to `SessionController.handleStartBreakAction(cycleId:)`, which runs this sequence in order before calling `completionHandler()`:

1. **Parse `cycleId`** from the notification identifier. Reject stale acks where `cycleId != currentCycleId` by no-op'ing.
2. **Cancel pending nudges and clear delivered ones** for this `cycleId`. Call `notificationCenter.removePendingNotificationRequests(withIdentifiers: [...5 nudge IDs + primary...])` to cancel scheduled-but-not-yet-fired nudges, then `notificationCenter.removeDeliveredNotifications(withIdentifiers: [...same 6 IDs...])` to clear any already-displayed nudges from Notification Center and the Watch glance list.
3. **Schedule the `done.<cycleId>` notification** at `now + 20 s`. This one has `interruptionLevel = .active` (standard, not time-sensitive), `sound = .default`, no action, a calm message body, and the same thread identifier so it groups with the break it completes.
4. **Generate a new `cycleId = UUID()`** and schedule the next cycle's full cascade at `now + 20 s + 20 min`.
5. **Update persistence** with the new `currentCycleId` and updated `cycleStartedAt`.
6. **Broadcast the new state** via `WCSession.default.updateApplicationContext`.
7. Call `completionHandler()`.

### Reconciliation on launch / foreground
Pre-emptively called from `onAppear` in `RootView` and from `applicationDidBecomeActive` in `AppDelegate`. Never trusts in-memory state:

1. Read `{ sessionActive, currentCycleId, cycleStartedAt }` from `UserDefaults`.
2. Query `UNUserNotificationCenter.getPendingNotificationRequests`.
3. If `!sessionActive` → show `idle`. Also clear any stray pending notifications as a safety net.
4. If `sessionActive` and pending notifications exist → derive UI state from the earliest pending identifier's fire date. If it's a `break.primary.*` and `now < fireDate`, state = `running`. If it's a `break.primary.*` and `now >= fireDate`, state = `breakActive`. If it's a `done.*`, state = `lookAway`. If it's a `break.primary.*` for a *future* cycleId that doesn't match the persisted current one, treat the persisted one as stale and rehydrate to the newer cycle.
5. If `sessionActive` but no pending notifications → the cascade ran out with no acknowledgment. Fall back to `idle`, clear `sessionActive` in persistence.

## 7. WatchConnectivity sync

**The iPhone owns the truth in V1.** All state mutations happen in the iPhone's `SessionController`; the Watch is a client.

Two `WCSession` delivery modes used:

- **`updateApplicationContext(_:)`** — latest-wins state snapshot. Used by the iPhone to broadcast `{ sessionActive, currentCycleId, nextBreakFireDate, state, updatedAt }` to the Watch whenever state changes. On the Watch side, the `WCSessionDelegate` callback (`session(_:didReceiveApplicationContext:)`) updates the Watch's local `SessionController` view model so the UI reflects the latest truth.
- **`sendMessage(_:replyHandler:errorHandler:)`** — live request/response. Used by the Watch to forward user-initiated commands (`start`, `stop`, `startBreak`) to the iPhone. The reply handler tells the Watch whether the command was accepted. If the iPhone is unreachable, the error handler fires and the Watch shows a brief "Not reachable" label.

The Watch has its own `UNUserNotificationCenterDelegate` registered, but in V1 it acts only as a forwarder: when the user taps Start break on the Watch, the delegate's `didReceive` handler calls `WCSession.default.sendMessage` with a `{ command: "startBreak", cycleId }` payload to the iPhone. The iPhone runs the full acknowledgment sequence (cancel pending notifications, schedule done + next cascade, update persistence) and then broadcasts the new state back to the Watch via `updateApplicationContext`. The Watch mutation is a consequence of the broadcast, not of the local tap. This keeps the iPhone as the single source of truth. V2 can add Watch-local handling as a fallback when the iPhone is unreachable.

## 8. Persistence

`UserDefaultsPersistence` stores a single `Codable` struct at key `"BlinkBreak.SessionRecord"`:

```swift
struct SessionRecord: Codable, Equatable {
    var sessionActive: Bool
    var currentCycleId: UUID?
    var cycleStartedAt: Date?
}
```

About 50 bytes encoded. `UserDefaults` is chosen over a full database because: (a) persistence surface is tiny, (b) reads/writes are synchronous and fast, (c) it survives app kills and device reboots, which is all we need. The pending notification queue is the source of truth for "what happens next" — `SessionRecord` is just what lets the UI rehydrate on launch.

## 9. Error handling

Only real failure modes get explicit handling. Speculative cases are omitted.

- **Notification permission denied.** First launch: request `[.alert, .sound, .timeSensitive]`. On every subsequent launch, call `getNotificationSettings` and if `authorizationStatus == .denied`, show `PermissionDeniedView` with a deep link to `UIApplication.openSettingsURLString`. The app does nothing else without permission; the Start button is hidden.
- **Time Sensitive entitlement missing.** On launch, check `UNNotificationSettings.timeSensitiveSetting`. If `.notSupported`, show a one-time alert explaining the missing capability. Proceed with standard-priority notifications (degraded but functional).
- **Watch unpaired or Watch app not installed.** Show a small banner on `IdleView`: "For the best experience, install the BlinkBreak Watch app." iPhone continues to schedule notifications; the user just misses the Watch haptic.
- **`sendMessage` fails from the Watch.** The error handler surfaces a brief "Not reachable" toast on the Watch. The Watch does not mutate local state (iPhone is source of truth). The user retries.
- **Notification scheduling fails.** `UNUserNotificationCenter.add(_:)` completion with an error: log it, roll back to `idle`, show an alert sheet. In practice this only happens at the ~64-pending-notification quota, which we will never hit.
- **App killed mid-cycle / device reboots.** Not an error. Handled by reconciliation.

## 10. Testing strategy

### Unit tests (primary, in `BlinkBreakTests`)
Target: `BlinkBreakCore`. Pure XCTest. No SwiftUI. No real `UNUserNotificationCenter`, no real `WCSession`. ~25 tests across four suites:

- **`SessionControllerTests`** — state machine. For each valid `(state, event)` pair, assert the new state and side effects (scheduler calls, persistence writes, connectivity broadcasts). Also tests reconciliation: persisted-active + matching pending, persisted-active + no pending, persisted-inactive. ~15 tests.
- **`NotificationSchedulerTests`** — cascade math. Given a start time, assert six scheduled requests with the correct IDs, fire times, and thread-identifier. Asserts cancellation-by-cycleId cleans up the right set. ~4 tests.
- **`ReconciliationTests`** — standalone test for the "derive current state from pending notifications + persisted record" logic. ~5 tests covering each branch.
- **`PersistenceTests`** — round-trip a `SessionRecord` via `InMemoryPersistence` (avoids polluting real `UserDefaults`). ~2 tests.

All of `SessionController`'s collaborators are protocol-typed so tests inject `MockNotificationScheduler`, `MockWatchConnectivity`, `MockPersistence`, and a `Clock` closure that returns a fake `Date`. The state machine can be walked through a full simulated session — Start → (advance clock 20 min) → handleStartBreakAction → (advance clock 20 s) → assert state is running again with a new cycleId — in pure Swift with no I/O.

### SwiftUI previews (no production tests; visual verification only)
Every state view has `#Preview` macros that render with the `PreviewSessionController` mock in each of the four states. These are Xcode-side development aids, not automated tests.

### No XCUITest in V1
Views are so thin (`switch state` + draw) that XCUITest adds flakiness without catching logic regressions. Skipped.

### No real-notification integration tests
Scheduling a real notification in CI and waiting 20 minutes for it is impractical. The integration point is covered by the unit-level scheduler mock; real-device smoke tests are manual during implementation.

### Forbidden-import lint
`scripts/lint.sh` greps `Packages/BlinkBreakCore/Sources/` for `import SwiftUI`, `import UIKit`, `import WatchKit` and fails if any match. Structural guarantee that the package stays UI-framework-free.

## 11. Xcode project structure

Repo layout:

```
BlinkBreak/
├── .github/
│   └── workflows/
│       ├── ci.yml
│       ├── ci-shared.yml
│       ├── release.yml
│       ├── deploy-testflight.yml      (disabled initially)
│       ├── claude.yml
│       ├── claude-code-review.yml
│       ├── workflow-lint.yml
│       ├── auto-approve.yml
│       └── automerge-label.yml
├── scripts/
│   ├── lint.sh
│   ├── build.sh
│   └── test.sh
├── project.yml                        (xcodegen spec; generates BlinkBreak.xcodeproj)
├── BlinkBreak/                        (iOS app target sources)
│   ├── BlinkBreakApp.swift
│   ├── AppDelegate.swift
│   ├── Info.plist
│   ├── Assets.xcassets/
│   ├── Preview/
│   │   └── PreviewSessionController.swift
│   └── Views/
│       ├── RootView.swift
│       ├── IdleView.swift
│       ├── RunningView.swift
│       ├── BreakActiveView.swift
│       ├── LookAwayView.swift
│       ├── PermissionDeniedView.swift
│       └── Components/
│           ├── CountdownRing.swift
│           ├── PrimaryButton.swift
│           ├── DestructiveButton.swift
│           ├── EyebrowLabel.swift
│           ├── CalmBackground.swift
│           └── AlertBackground.swift
├── BlinkBreak Watch App/              (watchOS app target sources)
│   ├── BlinkBreakWatchApp.swift
│   ├── WatchAppDelegate.swift
│   ├── Info.plist
│   ├── Assets.xcassets/
│   └── Views/
│       ├── WatchRootView.swift
│       ├── WatchIdleView.swift
│       ├── WatchRunningView.swift
│       ├── WatchBreakActiveView.swift
│       └── WatchLookAwayView.swift
├── BlinkBreakTests/                   (unit tests against BlinkBreakCore)
│   ├── SessionControllerTests.swift
│   ├── NotificationSchedulerTests.swift
│   ├── ReconciliationTests.swift
│   ├── PersistenceTests.swift
│   └── Mocks/
│       ├── MockNotificationScheduler.swift
│       ├── MockWatchConnectivity.swift
│       └── InMemoryPersistence.swift
├── Packages/
│   └── BlinkBreakCore/
│       ├── Package.swift
│       └── Sources/BlinkBreakCore/
│           ├── Constants.swift
│           ├── SessionState.swift
│           ├── SessionRecord.swift
│           ├── Persistence.swift
│           ├── NotificationScheduler.swift
│           ├── WatchConnectivityService.swift
│           ├── SessionController.swift
│           └── SessionControllerProtocol.swift
├── .swiftlint.yml
├── .gitignore
├── LICENSE
├── README.md
└── CLAUDE.md
```

`project.yml` is an xcodegen spec that describes all three targets (iOS app, Watch app, tests) and their dependency on the local `BlinkBreakCore` package. `BlinkBreak.xcodeproj` is **not** committed — it's generated at setup time by running `xcodegen generate`. This keeps the repo clean of the giant generated project file and makes the target wiring diffable via `project.yml`.

## 12. CI/CD

### Scripts
- **`scripts/lint.sh`** — runs SwiftLint if installed, plus a grep check forbidding `import SwiftUI` / `import UIKit` / `import WatchKit` anywhere under `Packages/BlinkBreakCore/Sources/`.
- **`scripts/build.sh`** — runs `xcodegen generate` (idempotent) then `xcodebuild build` for both iOS and Watch schemes using the generated `.xcodeproj`.
- **`scripts/test.sh`** — runs `swift test` against the `BlinkBreakCore` package (pure Swift, no iOS SDK). Optionally runs `xcodebuild test` on the iOS test scheme if the iOS SDK is available.

### GitHub Actions
Matches the `TytaniumDev` convention established in Wheelson, HeadsUpCDM, and MythicPlusDiscordBot:

- **`.github/workflows/ci.yml`** — `pull_request` trigger. One calling job with ID `CI` that uses `./.github/workflows/ci-shared.yml`. This keeps the required check names `CI / Lint`, `CI / Build`, `CI / Test` stable for branch protection.
- **`.github/workflows/ci-shared.yml`** — reusable `workflow_call`. Three jobs: `Lint`, `Build`, `Test`, all on `macos-15` (needs Xcode for iOS SDK; cannot be ubuntu). Each shells out to the corresponding `scripts/*.sh`.
- **`.github/workflows/claude.yml`** / **`claude-code-review.yml`** — reuse shared workflows from `TytaniumDev/.github` repo.
- **`.github/workflows/workflow-lint.yml`**, **`auto-approve.yml`**, **`automerge-label.yml`** — copied from Wheelson's conventions.
- **`.github/workflows/release.yml`** — triggers on push to `main`. Runs CI, then invokes `deploy-testflight.yml` via `gh workflow run`. Matches Wheelson's release pattern.
- **`.github/workflows/deploy-testflight.yml`** — TestFlight upload workflow. Disabled in V1: only the `workflow_dispatch` trigger is enabled (no automatic `workflow_run` chaining) so it cannot run until the user manually flips it on. Archives the app with `xcodebuild archive`, exports an `.ipa` with `-exportOptionsPlist`, and uploads via `xcrun altool --upload-app`. Reads four repo secrets: `APPSTORE_API_KEY_ID`, `APPSTORE_API_ISSUER_ID`, `APPSTORE_API_KEY_P8` (base64-encoded), `BUILD_CERTIFICATE_P12` + `BUILD_CERTIFICATE_PASSWORD`. All secret references scaffolded; the user populates them after enrolling in the Apple Developer Program.

### Prerequisite for the user
The machine running this project needs **full Xcode.app installed** (not just Command Line Tools). Install from the Mac App Store, then run `sudo xcode-select -s /Applications/Xcode.app` to switch the active developer directory. Documented in `README.md`.

## 13. Autonomous implementation decisions

Recorded so the user can review them when back:

1. **Xcode project generation via `xcodegen`.** Alternatives considered: hand-writing the `.xcodeproj` plist (too error-prone), Tuist (more complex, smaller community). `xcodegen` was picked because it's the lightest-weight and has a declarative YAML spec that reads cleanly for a Flutter dev familiar with `pubspec.yaml`.
2. **`SessionControllerProtocol` introduced as a hard boundary.** Views never depend on the concrete class — only the protocol. This allows `PreviewSessionController` for SwiftUI previews without mocking real notification/connectivity services, and reinforces the UI/logic separation rule.
3. **`swift test` on the local package as the primary test runner.** Runs without needing full Xcode — the local CLT toolchain is sufficient for `BlinkBreakCore`. `xcodebuild test` still runs in GitHub Actions for the iOS test scheme.
4. **`deploy-testflight.yml` disabled at creation time.** Scaffolded with all secret references in place, but only `workflow_dispatch` triggers it. No automatic push-to-main uploads until the user explicitly flips it on. Prevents broken CI while enrollment is pending.
5. **No custom break sound file in V1.** Uses `UNNotificationSound.default`. Custom sound is a polish item for V2; requires generating a CAF file and adding it to the app bundle.
6. **SwiftLint installation blocked by missing full Xcode.** Replaced with a minimal custom-script linter (the forbidden-import grep) plus `swift format` once full Xcode is installed. CI workflow conditionally runs SwiftLint if the binary is present.
7. **Removed the eye icon from `IdleView`** per late feedback. App name + explainer text + Start button only.
8. **No Pause/Resume.** Removed per user feedback during Section 1 review. Only Start and Stop.
9. **30-second cascade (6 notifications at 5-second intervals).** Picked over 60s / 120s alternatives during brainstorming.

## 14. Open questions for the user (resolved before spec was written)

All resolved during brainstorming. Recording them here for history:

1. "TestFlight without paying the developer fee?" — **Paid + TestFlight** chosen after explaining the $99/yr requirement.
2. "What level of obvious?" — **Time Sensitive + Watch haptic + custom sound** chosen over standard and Critical Alerts.
3. "How deep Watch integration?" — **Full paired Watch app** chosen over mirror-only or Watch-only.
4. "Pause, skip, snooze, stop?" — **Pause + Stop** initially, then Pause removed in Section 1 review. **Stop only.**
5. "Session mode?" — **Manual start/stop** for V1; scheduling deferred to V2.
6. "Configurable durations?" — **Hardcoded 20-20-20.**
7. "End-of-20s behavior?" — **Gentle haptic + auto-restart** over require-ack.
8. "Buzz duration?" — **30 seconds** (6 notifications × 5 s) over 60s / 120s.
9. "Look-away UI countdown?" — **No UI** over Watch-only countdown or phone countdown (defeats 20-20-20).
10. "Project name?" — **BlinkBreak.**
