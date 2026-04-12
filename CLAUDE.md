# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BlinkBreak is an iOS + watchOS app that enforces the 20-20-20 rule for eye strain: every 20 minutes, the user is alerted to look at something 20 feet away for 20 seconds. The alert is delivered as a 30-second alarm-style Watch haptic cascade so it's hard to miss while the user is on a PC or gaming. Hardcoded 20/20/20 durations; no scheduling; manual Start/Stop only in V1.

Tyler is a Flutter expert new to iOS/Swift — code comments frame SwiftUI concepts in terms of Flutter analogues where helpful.

## Commands

### Test (fast — use during iteration)
```bash
./scripts/test.sh
```
Runs the BlinkBreakCore unit suite via `swift test`. Sub-second runtime (~46 tests). All business logic lives in `BlinkBreakCore` and is covered by these unit tests with injected mocks (`MockNotificationScheduler`, `MockSessionAlarm`, `MockWatchConnectivity`, `InMemoryPersistence`). This is what you run during iteration.

### Test — integration (slow — final verification only)
```bash
./scripts/test-integration.sh
```
Runs the full XCUITest integration suite — 21 end-to-end tests that drive the iOS app through a real simulator. Takes ~4 minutes. **Do not run during iteration.** Run only as a final verification step before committing or creating a PR, and when you suspect a change might have broken end-to-end behavior that the unit tests can't catch.

The suite covers: app launch, idle state, start/stop transitions, full break cycle (running → breakActive → lookAway → running), state reconciliation across app terminate + relaunch, and rapid start/stop stress testing. It uses `BB_BREAK_INTERVAL=3` and `BB_LOOKAWAY_DURATION=3` environment variables (set by the `BlinkBreakUITests` scheme) so a full cycle runs in ~6 seconds of wall-clock time instead of 20 minutes + 20 seconds.

**What the integration suite does NOT cover** (requires on-device manual verification, kept in the PR checklist):
- Watch haptic feedback — Taptic Engine is a no-op in the watchOS simulator
- Real iPhone ↔ Watch notification forwarding
- Focus Mode break-through semantics
- Actual custom alarm sound playback through the speaker
- WatchOS UI tests (Apple's XCUITest support on watchOS is limited; iOS-only coverage in this suite)

The script automatically runs `xcrun simctl erase all` before each invocation to avoid the intermittent "Application failed preflight checks" flake where stale runner bundles fail to launch. Costs a few seconds, much cheaper than debugging false positives.

### Lint
```bash
./scripts/lint.sh
```
Two checks: (1) a grep-based forbidden-import scan that fails if any file under `Packages/BlinkBreakCore/Sources/` imports `SwiftUI`, `UIKit`, or `WatchKit`; (2) `swiftlint` if installed.

### Build
```bash
./scripts/build.sh
```
Runs `swift build` on BlinkBreakCore, then `xcodegen generate` + `xcodebuild build` on the iOS + Watch schemes. Skips the xcodebuild phase if only Command Line Tools are installed.

### Generate Xcode project
```bash
xcodegen generate
```
`BlinkBreak.xcodeproj` is gitignored and generated from `project.yml`. Edit `project.yml`, not the generated xcodeproj.

## Architecture

### UI / business-logic separation is non-negotiable

All business logic lives in `Packages/BlinkBreakCore/`, a local Swift Package. The package has **zero UI framework imports** — no `SwiftUI`, no `UIKit`, no `WatchKit`. This is enforced by `scripts/lint.sh` and is the fundamental architectural rule.

- **Views** depend on `SessionControllerProtocol`, not on the concrete `SessionController` class. Views read `@Published state` and call protocol methods (`start()`, `stop()`, `handleStartBreakAction()`, `acknowledgeCurrentBreak()`, `reconcileOnLaunch()`). Views contain no conditional business logic beyond a `switch` on `SessionState`.
- **A visual-iteration PR should only touch files under `BlinkBreak/Views/` or `BlinkBreak Watch App/Views/`.** If such a PR touches `BlinkBreakCore`, something is wrong and the PR should be split.
- **SwiftUI previews use `PreviewSessionController`**, a mock that conforms to `SessionControllerProtocol`. Every view has a `#Preview` for each applicable state.

### The three software units

1. **`BlinkBreakCore` (local Swift Package)** — state machine (`SessionController`), `SessionState` enum, `SessionRecord` Codable struct, `NotificationSchedulerProtocol` + `UNNotificationScheduler`, `WatchConnectivityProtocol` + `WCSessionConnectivity` + `NoopConnectivity`, `PersistenceProtocol` + `UserDefaultsPersistence` + `InMemoryPersistence`, `CascadeBuilder`, `Constants`.
2. **`BlinkBreak` (iOS app target)** — `@main BlinkBreakApp`, `AppDelegate` (notification delegate), SwiftUI views in `Views/`, small reusable components in `Views/Components/`.
3. **`BlinkBreak Watch App` (watchOS app target)** — mirror of the iOS target with Watch-sized views.

### State machine

Four states: `idle`, `running`, `breakActive`, `lookAway`. Two user transitions: `Start` and `Stop`. Two automatic transitions driven by scheduled notifications: `running → breakActive` when the 20-minute primary fires, `lookAway → running` when the 20-second done notification fires.

The iPhone is the source of truth in V1. The Watch forwards user commands (`Start`, `Stop`, `startBreak`) via `WCSession.sendMessage` and receives state snapshots via `WCSession.updateApplicationContext`.

### Notification cascade

When entering `running`, `SessionController` schedules **six local notifications** for the current cycle: 1 primary at T+20:00 plus 5 nudges at T+20:05 through T+20:25, all sharing a `thread-identifier = cycleId.uuidString` so Notification Center collapses them into a single visual entry. The cascade creates ~30 seconds of repeated Watch haptic until the user acknowledges. Tapping "Start break" on any of the six cancels the remaining pending ones, schedules a soft `done` notification at `now + 20 s`, and schedules the next cycle's full cascade.

This cascade approach is necessary because **iOS has no "keep retrying haptic until acknowledged" API** — scheduled notifications are the only tool for reliable alerts when the app is backgrounded. From the user's perspective it feels like one alarm; under the hood it's six scheduled notifications.

### Persistence + reconciliation

A tiny `SessionRecord` struct (sessionActive, currentCycleId, cycleStartedAt, lookAwayStartedAt) is persisted to `UserDefaults`. On launch / foreground / periodic ticks, `SessionController.reconcileOnLaunch()` rebuilds the in-memory `state` from: the persisted record + the pending notification queue + the current clock. Never trusts in-memory state. This makes the app robust against crashes, kills, and device reboots.

## Test structure

Two layers. **Run unit tests during iteration; run integration tests only as final verification.**

### Unit tests (fast — milliseconds)

- **Location:** `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/` using the Swift Testing framework (`import Testing`, `@Test`, `#expect`).
- **Runner:** `./scripts/test.sh` → `swift test`. ~46 tests in <1 second total.
- **Design:** Protocol-based dependency injection lets tests substitute mocks for every collaborator and drive virtual time via a closure-backed clock. Every `SessionController` collaborator has a matching mock: `MockNotificationScheduler`, `MockSessionAlarm`, `MockWatchConnectivity`, `InMemoryPersistence`. A mutable `NowBox` drives the injected `clock` closure so tests advance virtual time with zero real sleeping.
- **When to add a unit test:** Always, for any new state-machine transition, notification path, reconciliation case, or remote-snapshot handling. Write the failing test first, watch it fail, make it pass.

### Integration tests (slow — minutes)

- **Location:** `BlinkBreakUITests/` — XCUITest target that builds alongside the iOS app.
- **Runner:** `./scripts/test-integration.sh` → `xcodebuild test -scheme BlinkBreakUITests`. 21 tests in ~4 minutes.
- **Do NOT run during iteration.** The unit suite covers business logic with instant feedback. Integration tests are for catching regressions the unit suite can't see: real `UNUserNotificationCenter` delivery, real `UserDefaultsPersistence` round-trips, real SwiftUI view rendering, real state transitions through the full app lifecycle.
- **Run integration tests when:** (a) your change touches cross-target wiring (iOS ↔ Watch, view ↔ controller, persistence), (b) you changed `SessionController.reconcileOnLaunch` or any state-transition logic, (c) you're about to commit or create a PR as a final sanity check.
- **Environment variables:** the `BlinkBreakUITests` scheme sets `BB_BREAK_INTERVAL=3` and `BB_LOOKAWAY_DURATION=3`. `BlinkBreakConstants` reads these at first access so tests exercise a full 20-20-20 cycle in ~6 seconds of wall-clock time. Production builds don't set the vars and get the unmodified 20-minute default. The `-BB_RESET_DEFAULTS` launch arg wipes `UserDefaults` at `BlinkBreakApp.init()` so each test starts from a clean idle state.
- **Accessibility identifiers:** every state-bearing UI element (buttons and key labels) carries an `accessibilityIdentifier` like `button.idle.start`, `button.running.stop`, `button.breakActive.startBreak`, `button.lookAway.stop`, `label.running.countdown`, `label.lookAway.message`. Tests query for these via the `A11y` enum in `BlinkBreakUITestsBase.swift`. Adding a new view state? Add its identifier to `A11y` and to the view.
- **Simulator flakes:** `test-integration.sh` runs `xcrun simctl erase all` before each invocation. Without this reset, the iOS runner bundle sometimes fails with "Application failed preflight checks" on the second back-to-back run. The erase + shutdown sequence adds ~3 seconds but eliminates the false positive.

### What neither layer covers (manual verification only)

- **Watch haptics.** The Taptic Engine is a no-op in the watchOS simulator. `WKExtendedRuntimeSessionAlarm`'s `notifyUser(hapticType:repeatHandler:)` loop is verified by construction (calling into the real API) but the actual wrist buzz requires a paired hardware Apple Watch.
- **iPhone → Watch notification forwarding.** Forwarding is based on physical wrist detection and pairing; simulators don't model it.
- **Focus Mode break-through.** No Focus Mode in the simulator.
- **Custom alarm sound playback.** The simulator speaker plays sounds but not in the same way a real iPhone does with silent mode, ringer, or background audio.

All four of these are in the **on-device manual verification checklist** in `docs/superpowers/plans/2026-04-11-notification-alarm-redesign.md` (Task 13, Step 5). Any PR that affects alarm behavior must exercise the manual checklist before merging.

### watchOS integration tests — deliberately not included in V1

Apple's XCUITest support on watchOS is limited and flaky. The watchOS views are thin mirrors of the iOS views that share the same `SessionControllerProtocol`, so the iOS integration tests provide transitive coverage of the state machine logic the watchOS target depends on. Adding a `BlinkBreakWatchUITests` target was evaluated and deferred — the cost/benefit didn't justify it for V1.

## Platform constraints

- **iOS 17+ / watchOS 10+.** Required for Time Sensitive notifications and modern SwiftUI.
- **Command Line Tools swift test workaround:** If only CLT is installed (no full Xcode.app), tests are run with `-Xswiftc -F /Library/Developer/CommandLineTools/Library/Developer/Frameworks` plus the matching `-Xlinker -F` and `-Xlinker -rpath` flags to locate Apple's Swift Testing framework. `scripts/test.sh` handles this automatically. Also, a `FoundationReExport.swift` file in BlinkBreakCore has `@_exported import Foundation` to work around a `_Testing_Foundation` cross-import issue in CLT-only environments.

## CI/CD conventions

Matches the `TytaniumDev` repo pattern established by Wheelson / HeadsUpCDM / MythicPlusDiscordBot:

- `.github/workflows/ci.yml` (`pull_request` trigger) calls `.github/workflows/ci-shared.yml` (reusable `workflow_call`).
- `ci-shared.yml` has three jobs: `Lint`, `Build`, `Test` — all on `macos-15` because iOS SDK requires macOS + Xcode. Branch protection requires check names `CI / Lint`, `CI / Build`, `CI / Test`. **Do not rename the calling job ID (`CI`) in `ci.yml` or the reusable job IDs (`Lint`, `Build`, `Test`) in `ci-shared.yml`, and do not add extra triggers to `ci.yml`.**
- `.github/workflows/claude.yml` and `claude-code-review.yml` call the shared workflows in `TytaniumDev/.github/.github/workflows/` (same pattern as Wheelson).
- `.github/workflows/deploy-testflight.yml` is `workflow_dispatch`-only in V1. Enable automatic deploys only after enrolling in the Apple Developer Program and populating the `APPSTORE_API_KEY_*` + `BUILD_CERTIFICATE_*` repo secrets — see `README.md → TestFlight deployment`.

## Git workflow

- Never push directly to `main`.
- Every change goes through a feature branch + PR.
- Branch protection requires CI green before merge.
- PRs labeled `automerge` will auto-merge once CI passes and reviews are satisfied.

## Key conventions

- Swift 5.9+, iOS 17+, watchOS 10+.
- All `BlinkBreakCore` types are `public` for the API surface the app targets need, `internal` for helpers.
- Every file in `BlinkBreakCore` has a file-level comment explaining its role and (where helpful) a Flutter analogue for Tyler.
- Components in `Views/Components/` are stateless, take everything as parameters, and have `#Preview` macros. They should be under 50 lines each.
- Every SwiftUI view file has a `#Preview` for each state it can render.
- `SessionController` methods are the only place state mutations happen. Views never mutate state directly.
- When adding a new state-machine transition or notification path: write the unit test first, watch it fail, make it pass. All ~46 existing unit tests must stay green after any `BlinkBreakCore` change. For cross-target changes (view wiring, persistence round-trips, reconciliation), also run `./scripts/test-integration.sh` before committing.
- iOS app target is `BlinkBreak`; bundle ID `com.tytaniumdev.BlinkBreak`. Watch app target is `BlinkBreak Watch App`; bundle ID `com.tytaniumdev.BlinkBreak.watchkitapp` (must remain a child of the iOS bundle ID).

## Apple Developer Program prerequisites

BlinkBreak's TestFlight workflow requires a paid Apple Developer Program account. The $99/year enrollment:
- Enables 1-year provisioning profiles (vs. free personal-team's 7-day expiry)
- Grants access to TestFlight for beta distribution
- Is required for any real device deployment beyond a single developer's phone

Until enrolled, development still works via Xcode's free personal-team signing, but the user will need to re-open Xcode and re-build to the device every 7 days.
