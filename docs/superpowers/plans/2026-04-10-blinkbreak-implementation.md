# BlinkBreak — Implementation Plan

**Spec:** [2026-04-10-blinkbreak-design.md](../specs/2026-04-10-blinkbreak-design.md)
**Mode:** Autonomous (user approved, handed off)
**Environment constraint:** Only Command Line Tools installed — no full Xcode.app. `BlinkBreakCore` is verifiable via `swift test`; iOS/Watch app targets are compile-only until the user installs Xcode.app.

## Execution order

### Phase 1 — Repo scaffolding
1. Create `/Users/tylerholland/Dev/BlinkBreak/` with full directory tree (if not already done).
2. `git init` + set up `.gitignore` (Swift/Xcode/macOS standard + `.superpowers/` + `BlinkBreak.xcodeproj`).
3. Write `LICENSE` (MIT, matching Wheelson pattern).
4. Write stub `README.md` (full version comes in Phase 9).
5. Write `CLAUDE.md` with project conventions.

### Phase 2 — BlinkBreakCore Swift Package
Write these files, each with Flutter-analogue comments where helpful:
1. `Packages/BlinkBreakCore/Package.swift` — declares iOS 17 / watchOS 10 minimums, exports library + test target.
2. `Sources/BlinkBreakCore/Constants.swift` — durations, counts, notification identifiers.
3. `Sources/BlinkBreakCore/SessionState.swift` — the four-case enum.
4. `Sources/BlinkBreakCore/SessionRecord.swift` — the `Codable` persistence struct.
5. `Sources/BlinkBreakCore/Persistence.swift` — `PersistenceProtocol` + `UserDefaultsPersistence` + `InMemoryPersistence` (for tests).
6. `Sources/BlinkBreakCore/NotificationScheduler.swift` — `NotificationSchedulerProtocol` + `UNNotificationScheduler` + helpers for building cascade requests.
7. `Sources/BlinkBreakCore/WatchConnectivityService.swift` — `WatchConnectivityProtocol` + `WCSessionConnectivity` + `NoopConnectivity` (for tests).
8. `Sources/BlinkBreakCore/SessionControllerProtocol.swift` — the view-facing protocol.
9. `Sources/BlinkBreakCore/SessionController.swift` — the orchestrator. All state transitions live here.

### Phase 3 — Unit tests
1. `Tests/BlinkBreakCoreTests/Mocks/MockNotificationScheduler.swift`
2. `Tests/BlinkBreakCoreTests/Mocks/MockWatchConnectivity.swift`
3. `Tests/BlinkBreakCoreTests/SessionControllerTests.swift` — state transitions, handleStartBreakAction, stale cycleId rejection.
4. `Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift` — cascade math, cancellation.
5. `Tests/BlinkBreakCoreTests/ReconciliationTests.swift` — launch reconciliation branches.
6. `Tests/BlinkBreakCoreTests/PersistenceTests.swift` — InMemoryPersistence round-trip.

### Phase 4 — Verify BlinkBreakCore
1. `cd Packages/BlinkBreakCore && swift test`
2. Fix any failures before moving on.
3. This is the hard gate: no iOS app work begins until tests pass.

### Phase 5 — iOS app target
Write SwiftUI views. Each view is 30–80 lines, has a `#Preview`, and depends on `SessionControllerProtocol`.
1. `BlinkBreak/BlinkBreakApp.swift`
2. `BlinkBreak/AppDelegate.swift`
3. `BlinkBreak/Info.plist` (or declared in project.yml)
4. `BlinkBreak/Preview/PreviewSessionController.swift`
5. `BlinkBreak/Views/RootView.swift`
6. `BlinkBreak/Views/Components/EyebrowLabel.swift`
7. `BlinkBreak/Views/Components/PrimaryButton.swift`
8. `BlinkBreak/Views/Components/DestructiveButton.swift`
9. `BlinkBreak/Views/Components/CountdownRing.swift`
10. `BlinkBreak/Views/Components/CalmBackground.swift`
11. `BlinkBreak/Views/Components/AlertBackground.swift`
12. `BlinkBreak/Views/IdleView.swift` (no eye icon)
13. `BlinkBreak/Views/RunningView.swift`
14. `BlinkBreak/Views/BreakActiveView.swift`
15. `BlinkBreak/Views/LookAwayView.swift`
16. `BlinkBreak/Views/PermissionDeniedView.swift`

### Phase 6 — Watch app target
Mirror of the iOS views, smaller surface:
1. `BlinkBreak Watch App/BlinkBreakWatchApp.swift`
2. `BlinkBreak Watch App/WatchAppDelegate.swift`
3. `BlinkBreak Watch App/Views/WatchRootView.swift`
4. `BlinkBreak Watch App/Views/WatchIdleView.swift`
5. `BlinkBreak Watch App/Views/WatchRunningView.swift`
6. `BlinkBreak Watch App/Views/WatchBreakActiveView.swift`
7. `BlinkBreak Watch App/Views/WatchLookAwayView.swift`

### Phase 7 — xcodegen project.yml
1. Write `project.yml` declaring: iOS app, Watch app, test target, `BlinkBreakCore` local package dependency, entitlements, Info.plist values, schemes, deployment targets.
2. Run `xcodegen generate`. Fix any errors in the yml.
3. Add `BlinkBreak.xcodeproj/` to `.gitignore` (generated artifact).

### Phase 8 — Scripts + CI workflows
1. `scripts/lint.sh` — SwiftLint if present + import-guard grep.
2. `scripts/build.sh` — xcodegen generate + xcodebuild build (both schemes).
3. `scripts/test.sh` — swift test on BlinkBreakCore + xcodebuild test on iOS scheme.
4. `.github/workflows/ci.yml`
5. `.github/workflows/ci-shared.yml` (macos-15 runners)
6. `.github/workflows/release.yml`
7. `.github/workflows/deploy-testflight.yml` (workflow_dispatch only)
8. `.github/workflows/claude.yml` (calls TytaniumDev/.github shared workflow)
9. `.github/workflows/claude-code-review.yml` (calls TytaniumDev/.github shared)
10. `.github/workflows/workflow-lint.yml`
11. `.github/workflows/auto-approve.yml`
12. `.github/workflows/automerge-label.yml`
13. `.swiftlint.yml` — config matching project style.

### Phase 9 — Documentation
1. Full `README.md` — Flutter-dev framing, architecture diagram, setup (install Xcode.app), run instructions, testing, contribution rules.
2. `CLAUDE.md` — project overview, commands, architecture, conventions, UI/logic separation rule.
3. `BlinkBreak Watch App/BLINKBREAK_WATCH_README.md` — short developer note on Watch-specific quirks (optional, skip if not needed).

### Phase 10 — Git + GitHub
1. Stage all files.
2. Initial commit with descriptive message.
3. Create `TytaniumDev/BlinkBreak` repo via `gh repo create`.
4. Push `main`.
5. Report the PR-or-branch state to the user.

## Success criteria
- `cd Packages/BlinkBreakCore && swift test` passes with all ~25 tests green.
- `scripts/lint.sh` passes locally.
- `xcodegen generate` produces a valid `BlinkBreak.xcodeproj` without errors.
- All Swift files compile under `swift build` where possible (i.e. `BlinkBreakCore`).
- Repo pushed to `TytaniumDev/BlinkBreak` with CI workflows in place.
- Documentation is complete enough for the user to run the project after installing Xcode.app.

## Deferred to user after handoff
- Install full Xcode.app from Mac App Store.
- `sudo xcode-select -s /Applications/Xcode.app`
- Open `BlinkBreak.xcodeproj` in Xcode, build the iOS scheme to a simulator or device.
- Grant notification permission on first launch.
- Pair the Watch in Xcode's device list and deploy the Watch target.
- Enroll in Apple Developer Program when ready, populate TestFlight secrets in GitHub repo settings, enable `deploy-testflight.yml`'s push trigger.
