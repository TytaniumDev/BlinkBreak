# Audit Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the code smells that remain on `main` after #287 so BlinkBreak uses documented Apple APIs with no silent error-swallowing, stub targets, or control hacks.

**Architecture:** Five independent tasks on one branch (`chore/audit-followups`), shipped as one PR. Task 1 changes the Core `AlarmSchedulerProtocol` so a failed read of the system alarm list is an error instead of "no alarms", and makes `AlarmKitScheduler` stop ringing alarms with `stop(id:)`. Tasks 2–5 are project, test-target, privacy, and view cleanups that don't touch Core logic.

**Tech Stack:** Swift 6, SwiftUI, AlarmKit, App Intents, Swift Testing (Core unit tests), XCTest/XCUITest (integration), XcodeGen 2.45, Sentry 8.58.

**Spec:** The re-audit of `main` at 769ba75 (after #287/#288), summarized in "Findings" below. There is no separate spec doc.

## Findings this plan implements

1. `AlarmKitScheduler.currentAlarms()` turns a failed `AlarmManager.shared.alarms` read into `[]`. `SessionController` then treats the session's alarm as vanished and can stop the session ("vanished before firing; stopping") or skip cancelling alarms. A failed authorization request is reported as "denied".
2. Ringing alarms are removed with `AlarmManager.cancel(id:)`; Apple's documented call for an alerting alarm is `stop(id:)`.
3. `BlinkBreakTests/RehostedCoreTests.swift` is a stub target with one trivial test. Verified on 2026-10-07: XcodeGen 2.45 can put the package's own test target in the iOS scheme (`- package: BlinkBreakCore/BlinkBreakCoreTests`), and `xcodebuild test -scheme BlinkBreak` then runs all 123 Core tests on the simulator.
4. The UI test target is still in the Swift 5 language mode (`project.yml`, `SWIFT_VERSION: "5.0"`).
5. The feedback sheet collects free text and an optional email, but `PrivacyInfo.xcprivacy` declares no collected data, and the sheet says "No personal data is shared."
6. `DayRow` shrinks its `Toggle` with `.scaleEffect(0.8)` (visual size and hit area disagree; violates the "stock controls" rule).
7. `RunningView` hand-formats the countdown with `String(format:)` and a `DateComponentsFormatter`; `Duration.formatted(_:)` is the built-in API.

**Deliberately not changed:** `FoundationReExport.swift` (`@_exported import Foundation`) and the Command Line Tools branch in `scripts/test.sh` stay. CLAUDE.md documents Core tests running with CLT only and on Linux, and those need them. The 5-second `missingAlarmGrace` stays (documented AlarmKit ordering workaround).

## Global Constraints

- iOS deployment target 26.1; Swift 6 language mode everywhere after Task 3.
- `Packages/BlinkBreakCore/Sources/` must not import SwiftUI, UIKit, WatchKit, AlarmKit, AppIntents, or Sentry (`./scripts/lint.sh` enforces this).
- Do not modify anything under `.github/workflows/`.
- Edit `project.yml`, never the generated `BlinkBreak.xcodeproj`; run `xcodegen generate` after editing it.
- Every Swift file keeps its header comment (role, plus a Flutter analogue where helpful). Match the surrounding comment density and naming.
- Fast loop: `./scripts/test.sh` (Core, under a second). The integration suite (`./scripts/test-integration.sh`, ~4 min) runs only where a task says so.
- `./scripts/lint.sh` must pass with zero SwiftLint warnings after every task.
- Commit messages end with a blank line, then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. The system alarm list can't be read during `reconcile()` while the session's alarm is actually fine → the session keeps running, and nothing is cancelled or stopped. (Task 1, test `reconcileWithUnreadableAlarmList`.)
2. The list can't be read when the vanished-alarm grace period ends → the session is left alone instead of being stopped as "vanished before firing". (Task 1, test `missingAlarmCheckWithUnreadableList`.)
3. The user taps Stop while the list can't be read → the session's own alarm is still cancelled, so it doesn't ring later. (Task 1, test `stopWithUnreadableAlarmList`.)
4. The user taps Start over a running session while the list can't be read → the old break alarm is cancelled, so two alarms aren't left booked. (Task 1, test `restartWithUnreadableAlarmList`.)

Not unit-testable (app target only); the PR description must list them for on-device checks: tapping Stop in the app while the break alarm is ringing silences it (`stop(id:)` path), and the alarm permission prompt still appears on first Start.

---

### Task 1: Alarm-list read failures never stop or orphan a session

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/AlarmScheduler.swift` (error enum + `currentAlarms()` signature)
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift` (`handleMissingAlarm`, `reconcileWithSystem`, `cancelAlarms`)
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockAlarmScheduler.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift` (new section)
- Modify: `BlinkBreak/AlarmKitScheduler.swift`

**Interfaces:**
- Produces: `AlarmSchedulerError.listingFailed(reason: String)`; `AlarmSchedulerProtocol.currentAlarms() async throws -> [ScheduledAlarm]`; `MockAlarmScheduler.failCurrentAlarms(with: AlarmSchedulerError?)`.

- [ ] **Step 1: Add the error case and make the protocol method throw**

In `AlarmScheduler.swift`, add the case to `AlarmSchedulerError`:

```swift
    /// Reading the system's alarm list failed. Not the same as "no alarms".
    case listingFailed(reason: String)
```

and change the protocol requirement to:

```swift
    /// Every alarm the system currently holds for this app, including ones
    /// scheduled by earlier app launches.
    /// - Throws: `AlarmSchedulerError.listingFailed` when the system can't be
    ///   read. Callers must not treat a failed read as an empty list.
    func currentAlarms() async throws -> [ScheduledAlarm]
```

- [ ] **Step 2: Let the mock fail on demand**

In `MockAlarmScheduler.swift`, add `var listingError: AlarmSchedulerError?` to `Storage`, add this stubbing helper under `// MARK: - Stubbing`:

```swift
    /// Make every `currentAlarms()` call throw `error` until called again with nil.
    func failCurrentAlarms(with error: AlarmSchedulerError?) {
        storage.withLock { $0.listingError = error }
    }
```

and replace `currentAlarms()` with:

```swift
    func currentAlarms() async throws -> [ScheduledAlarm] {
        try storage.withLock { storage in
            if let error = storage.listingError { throw error }
            return storage.system
        }
    }
```

Also update the mock's header comment bullet list to mention stubbing list failures.

- [ ] **Step 3: Write the failing tests**

In `SessionControllerTests.swift`, add this section directly after the `// MARK: - Alarm removed with no button response` section (before `// MARK: - takeBreakNow()`):

```swift
    // MARK: - System alarm list unavailable

    @Test("reconcile keeps a running session when the alarm list can't be read")
    func reconcileWithUnreadableAlarmList() async {
        let f = Fixture()
        let alarm = await f.startRunning()
        let breakAt = f.now.value.addingTimeInterval(interval)
        f.alarms.failCurrentAlarms(with: .listingFailed(reason: "boom"))

        await f.controller.reconcile()
        await f.releaseSleepsAndSettle()

        #expect(f.controller.state == .running(breakAt: breakAt))
        #expect(f.record.alarmId == alarm)
        #expect(f.alarms.cancelled.isEmpty)
    }

    @Test("a vanished-alarm check that can't read the alarm list leaves the session alone")
    func missingAlarmCheckWithUnreadableList() async {
        let f = Fixture()
        let alarm = await f.startRunning()

        f.alarms.simulateRemoval(alarm)
        await f.settle()
        f.alarms.failCurrentAlarms(with: .listingFailed(reason: "boom"))
        await f.releaseSleepsAndSettle()

        #expect(f.controller.state != .idle)
        #expect(f.record.alarmId == alarm)
    }

    @Test("Stop still cancels the session's alarm when the alarm list can't be read")
    func stopWithUnreadableAlarmList() async {
        let f = Fixture()
        let alarm = await f.startRunning()
        f.alarms.failCurrentAlarms(with: .listingFailed(reason: "boom"))

        await f.controller.stop()

        #expect(f.controller.state == .idle)
        #expect(f.alarms.cancelled.contains(alarm))
    }

    @Test("Start over a running session cancels the old alarm when the alarm list can't be read")
    func restartWithUnreadableAlarmList() async {
        let f = Fixture()
        let first = await f.startRunning()
        f.alarms.failCurrentAlarms(with: .listingFailed(reason: "boom"))

        await f.controller.start()

        #expect(f.alarms.cancelled.contains(first))
        #expect(f.record.alarmId != first)
        #expect(f.record.phase == .running)
    }
```

(`interval` and `Fixture` already exist in this suite.)

- [ ] **Step 4: Run tests to verify they fail**

Run: `./scripts/test.sh`
Expected: build FAILS in `SessionController.swift` with "call can throw but is not marked with 'try'" at the three `alarms.currentAlarms()` call sites. That compile failure is this task's red state: the old code assumes the read can't fail.

- [ ] **Step 5: Handle the error at each call site in `SessionController.swift`**

Replace the `currentAlarms()` check in `handleMissingAlarm(_:)` (the line `guard !(await alarms.currentAlarms().contains { $0.alarmId == id }) else { return }`) with:

```swift
        let stillScheduled: Bool
        do {
            stillScheduled = try await alarms.currentAlarms().contains { $0.alarmId == id }
        } catch {
            // Can't tell whether the alarm is really gone. Leave the session
            // alone; the next reconcile checks again.
            log.log(.warning, "alarm \(id.short) check skipped: \(error)")
            return
        }
        guard !stillScheduled else { return }
```

In `reconcileWithSystem()`, replace `let systemAlarms = await alarms.currentAlarms()` and its two uses with:

```swift
        let systemAlarms: [ScheduledAlarm]?
        do {
            systemAlarms = try await alarms.currentAlarms()
        } catch {
            // A failed read isn't "no alarms": skip the orphan and missing-alarm
            // checks this time rather than act on a wrong picture.
            log.log(.warning, "reconcile: alarm list unavailable: \(error)")
            systemAlarms = nil
        }

        // Alarms we don't own come from older builds or interrupted operations.
        for alarm in systemAlarms ?? [] where alarm.alarmId != record.alarmId && !alarm.isAlerting {
            log.log(.info, "reconcile: cancelling orphaned alarm \(alarm.alarmId.short)")
            await alarms.cancel(alarmId: alarm.alarmId)
        }
```

and, at the end of the same function:

```swift
        if let systemAlarms, let id = record.alarmId, !systemAlarms.contains(where: { $0.alarmId == id }) {
            checkMissingAlarmAfterGrace(id)
        }
```

Replace `cancelAlarms(keepingAlerting:)` with:

```swift
    private func cancelAlarms(keepingAlerting: Bool) async {
        let systemAlarms: [ScheduledAlarm]
        do {
            systemAlarms = try await alarms.currentAlarms()
        } catch {
            // Fall back to the one alarm the session knows it owns. Its ringing
            // state is unknown; cutting a ring short beats leaving a duplicate
            // alarm booked. Reconcile cancels any other leftovers later.
            log.log(.warning, "cancel: alarm list unavailable, cancelling the session's alarm: \(error)")
            if let id = persistence.loadSession().alarmId {
                await alarms.cancel(alarmId: id)
            }
            return
        }
        for alarm in systemAlarms where !(keepingAlerting && alarm.isAlerting) {
            await alarms.cancel(alarmId: alarm.alarmId)
        }
    }
```

If `swift build` reports any other `currentAlarms()` call site (for example in another test file), mark it `try` and handle it the same way.

- [ ] **Step 6: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: PASS, 127 tests (123 existing + 4 new).

- [ ] **Step 7: Update `AlarmKitScheduler`**

In `BlinkBreak/AlarmKitScheduler.swift` replace `cancel(alarmId:)` and `currentAlarms()` with:

```swift
    func cancel(alarmId: UUID) async {
        // Apple's call for silencing a ringing alarm is `stop(id:)`; `cancel(id:)`
        // removes one that hasn't fired yet. Both throw for an alarm that's
        // already gone, which is fine.
        let isAlerting = (try? AlarmManager.shared.alarms)?
            .contains { $0.id == alarmId && $0.state == .alerting } ?? false
        if isAlerting {
            try? AlarmManager.shared.stop(id: alarmId)
        } else {
            try? AlarmManager.shared.cancel(id: alarmId)
        }
    }

    func currentAlarms() async throws -> [ScheduledAlarm] {
        do {
            return try AlarmManager.shared.alarms.map {
                ScheduledAlarm(alarmId: $0.id, isAlerting: $0.state == .alerting)
            }
        } catch {
            throw AlarmSchedulerError.listingFailed(reason: String(describing: error))
        }
    }
```

and replace the `.notDetermined` branch of `requestAuthorizationIfNeeded()` with:

```swift
        case .notDetermined:
            let state: AlarmManager.AuthorizationState
            do {
                state = try await AlarmManager.shared.requestAuthorization()
            } catch {
                // The request itself failed; that isn't the user saying no.
                throw AlarmSchedulerError.schedulingFailed(reason: "authorization request failed: \(error)")
            }
            guard state == .authorized else { throw AlarmSchedulerError.authorizationDenied }
```

- [ ] **Step 8: Build the app and lint**

Run: `./scripts/build.sh && ./scripts/lint.sh`
Expected: both succeed; lint reports no warnings.

- [ ] **Step 9: Commit**

```bash
git add Packages/BlinkBreakCore BlinkBreak/AlarmKitScheduler.swift
git commit -m "fix: don't treat an unreadable alarm list as no alarms; stop ringing alarms with stop(id:)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Run the real Core tests through the iOS scheme

**Files:**
- Modify: `project.yml`
- Delete: `BlinkBreakTests/RehostedCoreTests.swift` (and the `BlinkBreakTests/` directory)
- Modify: `scripts/test.sh` (header comment only)
- Modify: `README.md` (two tree diagrams that list `BlinkBreakTests/`)

- [ ] **Step 1: Edit `project.yml`**

1. In the `BlinkBreak` target, delete the target-level `scheme:` block:

```yaml
    scheme:
      testTargets:
        - BlinkBreakTests
      gatherCoverageData: true
```

2. Delete the whole `BlinkBreakTests:` target, including its `# ===` banner comment block above it.
3. In `schemes: BlinkBreak: test: targets:`, replace `- BlinkBreakTests` with:

```yaml
        # The Core package's own Swift Testing suite, run on the iOS simulator.
        - package: BlinkBreakCore/BlinkBreakCoreTests
```

- [ ] **Step 2: Delete the stub**

```bash
git rm -r BlinkBreakTests
```

- [ ] **Step 3: Regenerate and run the scheme's tests**

Run: `xcodegen generate && BLINKBREAK_FULL_TESTS=1 ./scripts/test.sh`
Expected: `swift test` passes, then `xcodebuild test` passes. To confirm the Core suite really runs on the simulator (`-quiet` hides it), run once without `-quiet`:

```bash
xcodebuild test -project BlinkBreak.xcodeproj -scheme BlinkBreak -destination "platform=iOS Simulator,name=iPhone 17 Pro" 2>&1 | grep -E "Test run with|TEST SUCCEEDED"
```

Expected: `✔ Test run with 127 tests in 10 suites passed` (or 123 if Task 1 isn't merged into this branch yet) and `** TEST SUCCEEDED **`.

- [ ] **Step 4: Update the docs**

In `scripts/test.sh`, change the header comment's CI paragraph to say `xcodebuild test -scheme BlinkBreak` runs the BlinkBreakCore test suite on an iOS simulator. In `README.md`, remove the two `BlinkBreakTests/` lines from the directory trees (around lines 32 and 230). Run `grep -rn "BlinkBreakTests\b\|RehostedCore" --include=*.md --include=*.sh --include=*.yml .` and fix any remaining reference outside `docs/superpowers/` (old plans stay as history).

- [ ] **Step 5: Lint and commit**

Run: `./scripts/lint.sh` (expected: pass).

```bash
git add -A project.yml scripts/test.sh README.md BlinkBreakTests
git commit -m "chore: run BlinkBreakCore tests in the iOS scheme instead of a stub target

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Move the UI test target to the Swift 6 language mode

**Files:**
- Modify: `project.yml` (`BlinkBreakUITests` settings)
- Modify: every file in `BlinkBreakUITests/` that the compiler flags
- Modify: `CLAUDE.md` (the integration-test "Location" bullet)

XCUITest's element APIs (`XCUIApplication`, `XCUIElement`) are `@MainActor` in the current SDK. The standard Swift 6 pattern is to isolate each test class to the main actor and use the async `setUp`:

```swift
@MainActor
final class ScheduleTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForIntegrationTest()
    }
```

Test methods in a `@MainActor` class are main-actor isolated; XCTest runs them on the main thread. Helpers in `extension XCUIApplication` inherit its main-actor isolation. Free functions or static helpers that touch XCUI types need `@MainActor`.

- [ ] **Step 1: Switch the mode**

In `project.yml`, delete these lines from `BlinkBreakUITests.settings.base`:

```yaml
        # XCUITest's element APIs are main-actor isolated; the suite stays in the
        # Swift 5 language mode until it's migrated to @MainActor test methods.
        SWIFT_VERSION: "5.0"
```

Run: `xcodegen generate`

- [ ] **Step 2: Build to list the errors**

Run: `xcodebuild build-for-testing -project BlinkBreak.xcodeproj -scheme BlinkBreakUITests -destination "platform=iOS Simulator,name=iPhone 17 Pro" 2>&1 | grep -E "error:|warning:" | sort -u`
Expected: concurrency errors in `BlinkBreakUITests/*.swift` (main-actor isolation of XCUI APIs and `setUp` overrides).

- [ ] **Step 3: Fix each file with the pattern above**

For every `XCTestCase` subclass: add `@MainActor`, and convert `override func setUp()` / `setUpWithError()` to `override func setUp() async throws` calling `try await super.setUp()` first. Do the same for `tearDown` if present. Don't change what any test asserts or its timing values.

- [ ] **Step 4: Rebuild until clean**

Re-run the Step 2 command. Expected: no output (zero errors and zero warnings).

- [ ] **Step 5: Run the integration suite**

Run: `./scripts/test-integration.sh`
Expected: all tests pass (~4 minutes). If a test fails, re-run it once by itself before debugging, to rule out the known simulator flake. If it still fails, compare against a run on `main` to check whether it fails there too, and report which.

- [ ] **Step 6: Update CLAUDE.md**

In CLAUDE.md's integration-tests "Location" bullet, delete the sentence "Stays in the Swift 5 language mode until migrated to `@MainActor` test methods." Add: "Swift 6 language mode; test classes are `@MainActor` and use `setUp() async throws`."

- [ ] **Step 7: Lint and commit**

Run: `./scripts/lint.sh` (expected: pass).

```bash
git add project.yml BlinkBreakUITests CLAUDE.md
git commit -m "test: move the UI test target to the Swift 6 language mode

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Declare the feedback data BlinkBreak collects

**Files:**
- Modify: `BlinkBreak/PrivacyInfo.xcprivacy`
- Modify: `BlinkBreak/Views/FeedbackSheetView.swift` (footer copy)
- Modify: `docs/privacy.html` (only if it doesn't already cover feedback)

- [ ] **Step 1: Declare the collected data types**

In `PrivacyInfo.xcprivacy`, replace `<key>NSPrivacyCollectedDataTypes</key>\n\t<array/>` with:

```xml
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<!-- The optional reply-to email on the feedback sheet. -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeEmailAddress</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- The feedback message itself. -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeOtherUserContent</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>
```

Run `plutil -lint BlinkBreak/PrivacyInfo.xcprivacy`. Expected: `OK`.

- [ ] **Step 2: Make the sheet's footer accurate**

In `FeedbackSheetView.swift`, replace the footer text

```swift
                    Text("Diagnostic data and recent app logs are attached automatically to help us "
                         + "understand any issues. No personal data is shared.")
```

with

```swift
                    Text("Recent app logs are attached to help us understand any issues. "
                         + "If you add an email, it's only used to reply to you.")
```

- [ ] **Step 3: Check the public privacy policy**

Read `docs/privacy.html`. If it doesn't say that feedback messages (and an optional email) are sent to the developer through Sentry, add one short paragraph next to its existing data or crash-reporting section, matching the page's markup:

> **Feedback.** If you send feedback from the app, your message, any email address you choose to include, and recent app logs are sent to the developer through Sentry. The email is used only to reply to you.

If the page already covers this, leave it unchanged.

- [ ] **Step 4: Build, lint, commit**

Run: `./scripts/build.sh && ./scripts/lint.sh` (expected: both pass).

```bash
git add BlinkBreak/PrivacyInfo.xcprivacy BlinkBreak/Views/FeedbackSheetView.swift docs/privacy.html
git commit -m "fix: declare feedback email and message in the privacy manifest

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Stock day toggles and built-in countdown formatting

**Files:**
- Modify: `BlinkBreak/Views/Components/DayRow.swift`
- Modify: `BlinkBreak/Views/RunningView.swift`

- [ ] **Step 1: Use the stock toggle size in `DayRow`**

Delete these two modifiers from the day `Toggle` (keep `.labelsHidden()` and `.tint(.green)`):

```swift
                    .scaleEffect(0.8)
                    .frame(width: 40)
```

- [ ] **Step 2: Use `Duration` formatting in `RunningView`**

Delete the file-level `a11yDurationFormatter` and its comment. Replace `countdown(at:)` with:

```swift
    private func countdown(at date: Date) -> some View {
        let interval = BlinkBreakConstants.breakInterval
        let remaining = max(0, breakAt.timeIntervalSince(date))
        let shown = Duration.seconds(remaining.rounded(.up))
        return CountdownRing(
            progress: (interval - remaining) / interval,
            label: shown.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(shown.formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
        .accessibilityIdentifier("label.running.countdown")
    }
```

The visible label stays `MM:SS` (for example `06:00`), and VoiceOver reads "6 minutes" or "5 minutes, 59 seconds".

- [ ] **Step 3: Build and check the previews render**

Run: `./scripts/build.sh` (expected: success). Then boot a simulator, install and launch the app, enable the schedule on the idle screen, and take a screenshot. Check that the day toggles are full-size, aligned in one column, and not clipped. Use the iOS Simulator tool or `xcrun simctl io booted screenshot`. Then tap Start and take a screenshot of the running screen to check the countdown reads `MM:SS`.

- [ ] **Step 4: Lint and commit**

Run: `./scripts/lint.sh` (expected: pass).

```bash
git add BlinkBreak/Views/Components/DayRow.swift BlinkBreak/Views/RunningView.swift
git commit -m "refactor: stock-size day toggles; format the countdown with Duration

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Final verification (controller, after all tasks)

- [ ] `./scripts/test.sh`, `./scripts/lint.sh`, `./scripts/build.sh` all pass.
- [ ] `./scripts/test-integration.sh` passes.
- [ ] Open the PR with a "Needs checking on a device" list: (1) tapping Stop in the app while the break alarm rings silences it; (2) the alarm permission prompt still appears on first Start of a fresh install; (3) App Store Connect's privacy "nutrition label" lists Email Address and Other User Content, matching the new manifest (manual, outside the repo).
