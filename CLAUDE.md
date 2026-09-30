# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BlinkBreak is an iOS app that enforces the 20-20-20 rule for eye strain: every 20 minutes, the user is alerted to look at something 20 feet away for 20 seconds. The alert is delivered via **AlarmKit** (iOS 26.1+) — a full-screen alarm takeover with a "Start break" button. Plays at alarm volume regardless of silent switch / Focus / DND. Supports an optional weekly schedule for automatic start/stop.

It runs on iPhone (portrait + landscape), iPad (fully resizable), and Apple silicon Macs as the iPad app ("Designed for iPad").

Tyler is a Flutter expert new to iOS/Swift — code comments frame SwiftUI concepts in terms of Flutter analogues where helpful.

## Commands

### Test (fast — use during iteration)
```bash
./scripts/test.sh
```
Runs the BlinkBreakCore unit suite via `swift test`. Sub-second runtime (~125 tests). All business logic lives in `BlinkBreakCore` and is covered by these unit tests with injected mocks. Works on macOS (Xcode or Command Line Tools) and on Linux with a Swift 6 toolchain.

### Test — integration (slow — final verification only)
```bash
./scripts/test-integration.sh
```
Runs the XCUITest integration suite — end-to-end tests that drive the iOS app through a real simulator. Takes ~4 minutes. **Do not run during iteration.** Run only as a final verification step before committing or creating a PR, and when you suspect a change might have broken end-to-end behavior that the unit tests can't catch.

The suite covers: app launch, idle state, start/stop transitions, full break cycle (running → breakPending → breakActive → running), state reconciliation across app terminate + relaunch, rapid start/stop stress testing, and landscape layout. `launchForIntegrationTest` sets `BB_UI_TESTING=1`, `BB_BREAK_INTERVAL=3` and `BB_LOOKAWAY_DURATION=3` so a full cycle runs in ~6 seconds of wall-clock time instead of 20 minutes + 20 seconds.

**What the integration suite does NOT cover** (requires on-device manual verification):
- Tapping the buttons on the system alarm UI (the App Intents path), especially with the app killed
- Focus Mode break-through semantics
- Actual custom alarm sound playback through the speaker

The script automatically runs `xcrun simctl erase all` before each invocation to avoid the intermittent "Application failed preflight checks" flake where stale runner bundles fail to launch.

### Lint
```bash
./scripts/lint.sh
```
Two checks: (1) a grep-based forbidden-import scan that fails if any file under `Packages/BlinkBreakCore/Sources/` imports `SwiftUI`, `UIKit`, `WatchKit`, `AlarmKit`, `ActivityKit`, `AppIntents`, or `Sentry`; (2) `swiftlint` if installed.

### Build
```bash
./scripts/build.sh
```
Runs `swift build` on BlinkBreakCore, then `xcodegen generate` + `xcodebuild build` on the iOS scheme. Skips the xcodebuild phase if only Command Line Tools are installed.

### Generate Xcode project
```bash
xcodegen generate
```
`BlinkBreak.xcodeproj` is gitignored and generated from `project.yml`. Edit `project.yml`, not the generated xcodeproj.

## Architecture

### UI / business-logic separation is non-negotiable

All business logic lives in `Packages/BlinkBreakCore/`, a local Swift Package. The package imports nothing platform-specific — no `SwiftUI`, `UIKit`, `WatchKit`, `AlarmKit`, `AppIntents`, or third-party SDKs. This is enforced by `scripts/lint.sh` and is the fundamental architectural rule.

- **Views** depend on `SessionControllerProtocol`, not on the concrete `SessionController` class. Views read `state` / `canPause` and call protocol methods (`start()`, `stop()`, `pause()`, `startBreak()`, `takeBreakNow()`, `reconcile()`, `updateSchedule(_:)`, `updateAlarmSound(muted:)`). Views contain no conditional business logic beyond a `switch` on `SessionState`.
- **A visual-iteration PR should only touch files under `BlinkBreak/Views/`.** Colors and layout constants live in `Views/Theme.swift`. If such a PR touches `BlinkBreakCore`, something is wrong and the PR should be split.
- **SwiftUI previews use `PreviewSessionController`**, a mock that conforms to `SessionControllerProtocol`. Every view has a `#Preview` for each applicable state.
- **Every screen uses `AdaptiveScreen`** (`Views/Components/`), which caps content at a readable width, scrolls when the window is short, and pins the action buttons at the bottom. New screens must use it so they work at every iPhone/iPad/Mac window size.

### The two software units

1. **`BlinkBreakCore` (local Swift Package, Swift 6 language mode)** — `SessionController` (the `@Observable` state machine), `SessionState` (derived UI state), `SessionRecord` (persisted phase + owned alarm), `AlarmSchedulerProtocol`, `PersistenceProtocol` + `UserDefaultsPersistence`, `WeeklySchedule` + its evaluation math, `SerialTaskQueue`, `AppLogger`, `BlinkBreakConstants`.
2. **`BlinkBreak` (iOS app target, Swift 6 language mode)** — `@main BlinkBreakApp`, `AppEnvironment` (composition root that owns the one shared `SessionController`), `AlarmKitScheduler` (concrete `AlarmManager.shared` wrapper), `AlarmIntents.swift` (the alarm-button App Intents), `Feedback/` (Sentry feedback via an environment-injected `FeedbackReporting`), SwiftUI views in `Views/`, small reusable components in `Views/Components/`.

### State machine

`SessionRecord.Phase` is persisted: `idle`, `scheduled` (weekly schedule pre-booked the next window's first break), `running`, `lookingAway`. `SessionState` is derived from the record plus the clock: `idle`, `running(breakAt:)`, `breakPending`, `breakActive(endsAt:)`, `paused(until:)`.

- The break alarm fires → `breakPending`. "Start break" (alarm button or in-app) → look-away alarm booked → `breakActive`. Stop on the break alarm skips straight to the next cycle.
- The look-away alarm fires → next cycle → `running`.

### Weekly schedule, pause, and manual sessions

- **Schedule-started sessions** (`SessionRecord.wasAutoStarted`) follow the live schedule and stop when `WeeklySchedule.isActive` turns false.
- **Manually started sessions** (including Resume) capture `SessionRecord.scheduledStopAt` = the end of the schedule window open at start, or the next one to open (`WeeklySchedule.currentOrNextWindowEnd`). They stop there; if a new window is already open by then, the schedule takes over. With the schedule off they have no stop time.
- **Pause** (`SessionController.pause()`, gated by `canPause`: session active + a schedule window open now) cancels the session's alarms and stops with `pausedUntil` = window end and `manualStopDate` = now; the next window is pre-booked as usual. The UI shows `.paused(until:)` until `pausedUntil`, then the pause lapses to `.idle`. `start()` doubles as Resume.
- A manual stop or pause is carried on the pre-booked record, so editing the schedule can't restart the session in the same window.

### How the cycle advances (important)

- **Alarm buttons run App Intents** (`BreakButtonIntent`, `StopButtonIntent`). iOS runs them even when the app isn't open; they call `SessionController.respond(to:alarmId:)` through `AppEnvironment`, which books the next alarm. This is what keeps the cycle going when the app has been killed.
- **While the app is alive**, `AlarmKitScheduler` turns `alarmUpdates` into `.alerting` / `.removed` events. The look-away alarm ringing rolls the cycle on. An alarm removed with no intent response is treated as skipped after `BlinkBreakConstants.missingAlarmGrace`.
- **`reconcile()`** runs when the app becomes active (`RootView`, `onChange(of: scenePhase, initial: true)`). It catches up on missed transitions, cancels alarms the session doesn't own, and applies the schedule.
- **The weekly schedule pre-books** the first break of the next window as a normal AlarmKit alarm. There is no background task.
- **Every transition runs on `SessionController`'s serial queue.** Transitions are `private` methods that assume they're on the queue; public methods enqueue them. Never call a public controller method from inside a transition (it would wait on itself).

### Persistence + reconciliation

`SessionRecord` (phase, alarmId, alarmFiresAt, wasAutoStarted, manualStopDate) is persisted to `UserDefaults` under `BlinkBreak.Session.v2`. AlarmKit is the source of truth for what is actually scheduled or ringing (`AlarmManager.shared.alarms`); the record says which of those alarms the session owns and what it means. Nothing else caches alarm state.

## Test structure

Two layers. **Run unit tests during iteration; run integration tests only as final verification.**

### Unit tests (fast — milliseconds)

- **Location:** `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/` using the Swift Testing framework (`import Testing`, `@Test`, `#expect`).
- **Runner:** `./scripts/test.sh` → `swift test`.
- **Design:** Protocol-based dependency injection. `SessionControllerFixture` (in `TestFixtures.swift`) wires the controller to `MockAlarmScheduler`, `InMemoryPersistence`, a `NowBox` virtual clock, a GMT calendar, and a `ManualSleeper` that holds grace periods and timed wake-ups until the test calls `releaseSleepsAndSettle()`. Public controller methods are `async` and awaited directly; alarm events use `settle()`.
- **When to add a unit test:** Always, for any new state-machine transition, alarm path, or reconciliation case. Write the failing test first, watch it fail, make it pass.

### Integration tests (slow — minutes)

- **Location:** `BlinkBreakUITests/` — XCUITest target that builds alongside the iOS app. Stays in the Swift 5 language mode until migrated to `@MainActor` test methods.
- **Runner:** `./scripts/test-integration.sh` → `xcodebuild test -scheme BlinkBreakUITests`.
- **Do NOT run during iteration.**
- **Run integration tests when:** (a) your change touches view ↔ controller wiring or persistence, (b) you changed reconciliation or any state-transition logic, (c) you're about to commit or create a PR as a final sanity check.
- **Launch hooks (DEBUG builds only):** `BB_UI_TESTING=1` skips the AlarmKit permission check and uses the silent sound (`UITestSupport.swift`); `BB_BREAK_INTERVAL` / `BB_LOOKAWAY_DURATION` shorten the cycle (`BlinkBreakConstants`); `-BB_RESET_DEFAULTS` wipes all stored data at launch. `launchForIntegrationTest` sets all of these.
- **Accessibility identifiers:** every state-bearing UI element carries an `accessibilityIdentifier` like `button.idle.start`, `button.running.stop`, `button.running.takeBreakNow`, `button.breakPending.startBreak`, `button.breakPending.stop`, `button.breakActive.stop`, `button.running.pause`, `button.paused.resume`, `label.running.countdown`. Tests query for these via the `A11y` enum in `BlinkBreakUITestsBase.swift`. Adding a new view state? Add its identifier to `A11y` and to the view.

### What neither layer covers (manual verification only)

- **Alarm buttons with the app killed.** Tap Start break / End break / Stop on the system alarm after swiping the app away; the next alarm must still be booked.
- **Focus Mode break-through.** No Focus Mode in the simulator.
- **Custom alarm sound playback.**
- **Mac ("Designed for iPad") alarm behavior.**

Any PR that affects alarm behavior must exercise on-device manual verification before merging.

## Platform constraints

- **iOS 26.1+.** Required for AlarmKit (and its fixed Stop-button behavior). (Pre-AlarmKit history: app shipped on iOS 17+ via UNNotification banners through PR #24; PR #25 migrated to AlarmKit and bumped the floor.)
- **Command Line Tools swift test workaround:** If only CLT is installed (no full Xcode.app), tests are run with `-Xswiftc -F /Library/Developer/CommandLineTools/Library/Developer/Frameworks` plus the matching `-Xlinker -F` and `-Xlinker -rpath` flags to locate Apple's Swift Testing framework. `scripts/test.sh` handles this automatically. Also, a `FoundationReExport.swift` file in BlinkBreakCore has `@_exported import Foundation` to work around a `_Testing_Foundation` cross-import issue in CLT-only environments.

## CI/CD conventions

Matches the `TytaniumDev` repo pattern established by Wheelson / HeadsUpCDM / MythicPlusDiscordBot:

- `.github/workflows/ci.yml` (`pull_request` trigger) calls `.github/workflows/ci-shared.yml` (reusable `workflow_call`).
- `ci-shared.yml` has three jobs: `Lint`, `Build`, `Test` — all on `macos-15` because iOS SDK requires macOS + Xcode. Branch protection requires check names `CI / Lint`, `CI / Build`, `CI / Test`. **Do not rename the calling job ID (`CI`) in `ci.yml` or the reusable job IDs (`Lint`, `Build`, `Test`) in `ci-shared.yml`, and do not add extra triggers to `ci.yml`.**
- `.github/workflows/claude.yml` and `claude-code-review.yml` call the shared workflows in `TytaniumDev/.github/.github/workflows/` (same pattern as Wheelson).
- `.github/workflows/deploy-testflight.yml` runs on push to `main`. Secrets come from Doppler; the only GitHub secret is `DOPPLER_TOKEN` — see `README.md → TestFlight deployment`.

## Git workflow

- Never push directly to `main`.
- Every change goes through a feature branch + PR.
- Branch protection requires CI green before merge.
- PRs labeled `automerge` will auto-merge once CI passes and reviews are satisfied.

## Key conventions

- Swift 6 language mode for BlinkBreakCore and the app target; iOS 26.1+ deployment target.
- All `BlinkBreakCore` types are `public` for the API surface the app target needs, `internal` for helpers.
- Every file in `BlinkBreakCore` has a file-level comment explaining its role and (where helpful) a Flutter analogue for Tyler.
- Components in `Views/Components/` are stateless, take everything as parameters, and have `#Preview` macros. Keep them small.
- Every SwiftUI view file has a `#Preview` for each state it can render.
- `SessionController` methods are the only place state mutations happen. Views never mutate state directly.
- Third-party SDKs (Sentry) stay out of views; views get services from the SwiftUI environment (see `Feedback/FeedbackReporting.swift`).
- When adding a new state-machine transition or alarm path: write the unit test first, watch it fail, make it pass. All existing unit tests must stay green after any `BlinkBreakCore` change. For cross-target changes (view wiring, persistence round-trips, reconciliation), also run `./scripts/test-integration.sh` before committing.
- iOS app target is `BlinkBreak`; bundle ID `com.tytaniumdev.BlinkBreak`.

## Apple Developer Program prerequisites

BlinkBreak's TestFlight workflow requires a paid Apple Developer Program account. The $99/year enrollment:
- Enables 1-year provisioning profiles (vs. free personal-team's 7-day expiry)
- Grants access to TestFlight for beta distribution
- Is required for any real device deployment beyond a single developer's phone

Until enrolled, development still works via Xcode's free personal-team signing, but the user will need to re-open Xcode and re-build to the device every 7 days.
