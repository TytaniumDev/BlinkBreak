# PR 1 — Watch Removal & TestFlight Unblock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the watchOS companion app + WKExtendedRuntimeSession + WCSession plumbing + SessionAlarmProtocol abstractions, leaving the iOS app intact with current UNNotification break behavior. Unblocks TestFlight deploys (currently stuck on build 16).

**Architecture:** Pure deletion + API simplification. `SessionController.init` loses two parameters (`connectivity:`, `alarm:`). `BlinkBreakCore` loses two protocol files and two mocks. Watch target and Watch app source directory are deleted whole. App-level wiring in `BlinkBreakApp.swift` and `AppDelegate.swift` loses the WC activation/wireup calls.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Package Manager, xcodegen, Swift Testing framework.

---

## File Map

**Delete entirely:**
- `BlinkBreak Watch App/` (whole directory: `BlinkBreakWatchApp.swift`, `WatchAppDelegate.swift`, `WKExtendedRuntimeSessionAlarm.swift`, `Views/`, `Assets.xcassets/`, `BlinkBreakWatch.entitlements`, `Info.plist`)
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionAlarm.swift`
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/WatchConnectivityService.swift`
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockSessionAlarm.swift`
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockWatchConnectivity.swift`

**Modify:**
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift` — drop `alarm`, `connectivity` params + all callsites (`broadcastSnapshot`, `handleRemoteSnapshot`, `wireUpConnectivity`, `activateConnectivity`, every `alarm.arm` / `alarm.disarm` call)
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift` — drop `alarm:` / `connectivity:` parameters from all `makeController()` calls and any test that asserts on alarm/WC behavior
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift` — same
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleIntegrationTests.swift` — same
- `BlinkBreak/BlinkBreakApp.swift` — drop `import WatchConnectivity`, `connectivity:` arg, `activateConnectivity()` call, `wireUpConnectivity()` call, `watchIsPaired` / `watchIsReachable` props on ShakeDetectorView
- `BlinkBreak/Views/` — anywhere that displays Watch reachability/pairing badges in the iOS UI
- `project.yml` — delete the `BlinkBreak Watch App` target stanza, the `target: "BlinkBreak Watch App"` dependency from the iOS target, the watchOS deploymentTarget option line
- `scripts/build.sh` — drop the `→ Building Watch app target...` xcodebuild stanza
- `CLAUDE.md` — strip Watch references, simplify "three software units" → two

**Leave alone:**
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift`, `CascadeBuilder.swift` — still used for the iOS UNNotification path. PR 2 deletes them.
- `BlinkBreakUITests/` — these test iOS state transitions which are unaffected. May need minor adjustment if any test was Watch-specific (none should be — XCUITest doesn't drive the Watch).

---

## Task 1: Create feature branch

**Files:** none

- [ ] **Step 1: Branch from current main**

```bash
git checkout main
git pull --ff-only origin main
git checkout -b watch-removal
git status
```

Expected: `On branch watch-removal`, working tree clean.

---

## Task 2: Strip `connectivity` param + WC code from SessionController

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`

- [ ] **Step 1: Remove the `connectivity` instance var + init param**

In `SessionController.swift`, remove the line:
```swift
private let connectivity: WatchConnectivityProtocol
```

In the `init`, remove the `connectivity: WatchConnectivityProtocol,` parameter and the `self.connectivity = connectivity` assignment in the body. Update the docstring above the `init` to drop the connectivity bullet.

- [ ] **Step 2: Remove `wireUpConnectivity()`, `activateConnectivity()`, `handleRemoteSnapshot()`, `broadcastSnapshot()`**

Delete those four methods entirely. They live in the `// MARK: - Incoming Watch commands` and `// MARK: - Helpers` sections.

- [ ] **Step 3: Remove every `broadcastSnapshot(for: ...)` callsite**

Search for `broadcastSnapshot` in this file. Five callsites currently — `start`, `stop`, `handleStartBreakAction`, `reconcileState` (the cleared-record branch), and the helper definition. Delete all calls (the helper definition is gone from step 2).

- [ ] **Step 4: Remove the now-unused `// MARK: - Incoming Watch commands` section header**

After deleting the WC-related methods the header has nothing under it. Delete the header line.

- [ ] **Step 5: Verify the file compiles standalone**

```bash
cd Packages/BlinkBreakCore && swift build 2>&1 | tail -20
```

Expected: build fails because tests still reference the deleted `connectivity:` parameter and `MockWatchConnectivity` import — that's fine for now, will be fixed in Task 5. The Sources should compile clean — look for compile errors in `Sources/`, not `Tests/`. If only Test errors remain, proceed.

---

## Task 3: Strip `alarm` param + alarm code from SessionController

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`

- [ ] **Step 1: Remove the `alarm` instance var + init param**

Remove:
```swift
private let alarm: SessionAlarmProtocol
```

In the `init`, remove `alarm: SessionAlarmProtocol,` parameter and `self.alarm = alarm` assignment. Update docstring.

- [ ] **Step 2: Remove every `alarm.arm(...)` and `alarm.disarm(...)` callsite**

Search for `alarm.` in the file. There are six callsites: in `startSession`, `stop`, `handleStartBreakAction`, and two in `reconcileState`. Delete each call. Where comments above the call mention "arm the alarm" or "Watch haptic loop," delete those comments too — they're now lying.

- [ ] **Step 3: Verify Sources still compile**

```bash
cd Packages/BlinkBreakCore && swift build 2>&1 | grep -E "error:" | grep -v Tests | head
```

Expected: zero errors from `Sources/` (Tests will still error — fixed later).

---

## Task 4: Delete the protocol + mock files

**Files:**
- Delete: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionAlarm.swift`
- Delete: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/WatchConnectivityService.swift`
- Delete: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockSessionAlarm.swift`
- Delete: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockWatchConnectivity.swift`

- [ ] **Step 1: Delete the four files**

```bash
git rm Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionAlarm.swift
git rm Packages/BlinkBreakCore/Sources/BlinkBreakCore/WatchConnectivityService.swift
git rm Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockSessionAlarm.swift
git rm Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockWatchConnectivity.swift
```

- [ ] **Step 2: Verify no remaining references in Sources**

```bash
grep -rn "SessionAlarmProtocol\|WatchConnectivityProtocol\|NoopSessionAlarm\|NoopConnectivity\|WCSessionConnectivity\|SessionSnapshot\|WatchCommand" Packages/BlinkBreakCore/Sources/ || echo "clean"
```

Expected: prints `clean`.

---

## Task 5: Update unit tests to drop alarm/connectivity references

**Files:**
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleIntegrationTests.swift`

- [ ] **Step 1: Find the `makeController` helper(s) in each file**

```bash
grep -rn "func makeController\|SessionController(" Packages/BlinkBreakCore/Tests/
```

- [ ] **Step 2: For each `SessionController(...)` call site, drop `alarm:` and `connectivity:` arguments**

In each test file, every `SessionController(scheduler: ..., connectivity: ..., persistence: ..., alarm: ...)` becomes `SessionController(scheduler: ..., persistence: ...)`. Drop both arguments. Drop any imports / parameter declarations of `WatchConnectivityProtocol`, `SessionAlarmProtocol`, `MockSessionAlarm`, `MockWatchConnectivity`, `NoopConnectivity`, `NoopSessionAlarm` from the test file.

- [ ] **Step 3: Delete tests that exclusively asserted on alarm/WC behavior**

Search each test file for `alarm.armed`, `alarm.disarmed`, `connectivity.broadcasts`, `connectivity.lastBroadcast`, `handleRemoteSnapshot`, `wireUpConnectivity`, `activateConnectivity`. Tests whose only assertions are against these removed surfaces should be deleted entirely (not just stripped to nothing). Tests that incidentally constructed mocks but assert on state/persistence/scheduler keep their state/persistence/scheduler assertions and lose the alarm/WC bits.

- [ ] **Step 4: Run unit tests**

```bash
./scripts/test.sh 2>&1 | tail -5
```

Expected: `Test run with N tests in M suites passed`. N is lower than 110 (some tests were deleted). All remaining tests pass.

- [ ] **Step 5: Commit progress**

```bash
git add -A
git commit -m "refactor(core): strip SessionAlarmProtocol and WatchConnectivityProtocol from SessionController

The Watch app and its WKExtendedRuntimeSession-based alarm path are being removed;
SessionController no longer needs to abstract over either. Drops two init parameters,
deletes the two protocol definitions and their mocks, and removes broadcastSnapshot,
handleRemoteSnapshot, wireUpConnectivity, activateConnectivity from the public surface.

iOS UNNotification break behavior is unchanged.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Delete the Watch app source directory

**Files:**
- Delete: `BlinkBreak Watch App/` (entire directory)

- [ ] **Step 1: Delete the directory**

```bash
git rm -r "BlinkBreak Watch App/"
```

- [ ] **Step 2: Verify no remaining references in the iOS source tree**

```bash
grep -rn "BlinkBreak Watch App\|watchkitapp\|WatchOS\|import WatchConnectivity\|import WatchKit" BlinkBreak/ Packages/BlinkBreakCore/Sources/ 2>&1 | grep -v "// "
```

Expected: zero matches (or only matches in comments / docs that are obviously dead).

---

## Task 7: Remove Watch target from project.yml

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Delete the `BlinkBreak Watch App` target stanza**

Remove the entire block from the `# watchOS app target` comment through (and including) the empty line before the next target. Roughly lines 100–144 in the current file.

- [ ] **Step 2: Remove the target dependency from the iOS target**

In the `BlinkBreak:` target's `dependencies:` list, remove:
```yaml
      - target: "BlinkBreak Watch App"
```
and the surrounding comment about embedding the watchOS companion.

- [ ] **Step 3: Remove the watchOS deploymentTarget**

In `options.deploymentTarget`, remove the `watchOS: "10.0"` line. Leave `iOS: "17.0"` alone (PR 2 bumps it to 26).

- [ ] **Step 4: Regenerate the Xcode project + verify**

```bash
xcodegen generate 2>&1 | tail -5
```

Expected: succeeds, no warnings about missing Watch sources.

---

## Task 8: Strip Watch wiring from BlinkBreakApp.swift

**Files:**
- Modify: `BlinkBreak/BlinkBreakApp.swift`

- [ ] **Step 1: Remove `import WatchConnectivity`**

Top of file. Delete the line.

- [ ] **Step 2: Update SessionController construction**

Change:
```swift
return SessionController(
    scheduler: sharedScheduler,
    connectivity: WCSessionConnectivity(),
    persistence: sharedPersistence,
    alarm: NoopSessionAlarm(),
    scheduleEvaluator: sharedEvaluator
)
```
to:
```swift
return SessionController(
    scheduler: sharedScheduler,
    persistence: sharedPersistence,
    scheduleEvaluator: sharedEvaluator
)
```

- [ ] **Step 3: Remove WC activation calls in `.onAppear`**

Delete:
```swift
controller.activateConnectivity()
controller.wireUpConnectivity()
```

The comment block above these lines (the "Activate WatchConnectivity..." paragraph) goes too.

- [ ] **Step 4: Remove `watchIsPaired` and `watchIsReachable` props on `ShakeDetectorView`**

Delete the two arguments:
```swift
watchIsPaired: WCSession.isSupported() ? WCSession.default.isPaired : false,
watchIsReachable: WCSession.isSupported() ? WCSession.default.isReachable : false
```

- [ ] **Step 5: Build the iOS app**

```bash
xcodegen generate && xcodebuild build -project BlinkBreak.xcodeproj -scheme BlinkBreak -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -10
```

Expected: build succeeds. If `ShakeDetectorView` fails because it required those two args, drop them from `ShakeDetectorView` itself in step 6.

- [ ] **Step 6: Update ShakeDetectorView signature if needed**

Open the file (search):
```bash
grep -rn "ShakeDetectorView" BlinkBreak/Views/
```

If it has `watchIsPaired:` / `watchIsReachable:` parameters, delete them and any field that uses them (e.g. a "Watch reachable" badge in the bug-report dialog). Build again.

---

## Task 9: Update build.sh

**Files:**
- Modify: `scripts/build.sh`

- [ ] **Step 1: Remove the Watch xcodebuild stanza**

Delete this block:
```bash
echo ""
echo "→ Building Watch app target..."
xcodebuild build \
  -project BlinkBreak.xcodeproj \
  -scheme "BlinkBreak Watch App" \
  -destination 'generic/platform=watchOS Simulator' \
  -quiet
echo "  ok — BlinkBreak Watch App built."
```

- [ ] **Step 2: Update the file's docstring at the top**

Change the comment block referencing "iOS + watchOS project" to "iOS project."

- [ ] **Step 3: Run build script end-to-end**

```bash
./scripts/build.sh 2>&1 | tail -10
```

Expected: builds clean, no Watch-related output.

---

## Task 10: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Strip Watch references**

Read the current `CLAUDE.md` and remove every paragraph / bullet that mentions:
- `BlinkBreak Watch App` target
- `WKExtendedRuntimeSession`, `WCSession`
- "three software units" → change to "two software units"
- watchOS deployment target
- Watch haptic feedback testing notes
- "iPhone is the source of truth. The Watch forwards user commands..." paragraph
- Manual on-device verification items that only apply to the Watch

The Project Overview's first paragraph still mentions watchOS. Update to "BlinkBreak is an iOS app that enforces the 20-20-20 rule for eye strain..."

- [ ] **Step 2: Verify it still reads coherently**

Reread the file. Anywhere a section now refers to a non-existent thing (e.g., "the Watch" without context), patch it.

---

## Task 11: Verify the full test + build + lint suite

**Files:** none (verification only)

- [ ] **Step 1: Unit tests**

```bash
./scripts/test.sh 2>&1 | tail -5
```

Expected: green.

- [ ] **Step 2: Lint**

```bash
./scripts/lint.sh 2>&1 | tail -10
```

Expected: no NEW violations (pre-existing warnings about generated `.build/runner.swift` are OK).

- [ ] **Step 3: Build**

```bash
./scripts/build.sh 2>&1 | tail -10
```

Expected: green.

- [ ] **Step 4: Integration tests (only if Step 1–3 all green)**

```bash
./scripts/test-integration.sh 2>&1 | tail -20
```

Expected: green. If failures, investigate — most likely cause is a Watch-related XCUITest assertion that needs deleting.

---

## Task 12: Commit any remaining changes + push branch

**Files:** none

- [ ] **Step 1: Stage and commit anything not yet committed**

```bash
git status
git add -A
git diff --cached --stat
```

Review the staged diff. If it looks right, commit:

```bash
git commit -m "chore: remove Watch app target, sources, and CI/build references

PR 1 of the AlarmKit migration. Deletes the watchOS companion app entirely
(BlinkBreak Watch App/, project.yml target, build.sh stanza) and updates
CLAUDE.md to reflect the iOS-only architecture. SessionController parameter
removal already landed in the previous commit.

iOS app is unchanged in behavior — UNNotification break-reminder path is intact.
TestFlight should now deploy successfully (the broken WKExtendedRuntimeSession
+ smart-alarm code path that was failing App Store Connect validation is gone).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 2: Push branch**

```bash
git push -u origin watch-removal
```

---

## Task 13: Open PR + ship-it flow

**Files:** none

- [ ] **Step 1: Open PR**

```bash
gh pr create --title "chore: remove Watch app and unblock TestFlight" --body "..."
```

Body should reference the design spec at `docs/superpowers/specs/2026-04-15-alarmkit-migration-design.md` and explain that this is PR 1 of 2.

- [ ] **Step 2: Trigger Claude review**

```bash
gh pr comment <number> --body "@claude do a code review"
```

- [ ] **Step 3: Poll for + address bot reviews**

Wait for Gemini and Claude. Address every comment with rigor (per `superpowers:receiving-code-review` skill — don't blindly accept or reject; verify each).

- [ ] **Step 4: Verify CI green and merge**

```bash
gh pr checks <number>
gh pr merge <number> --squash --delete-branch
```

- [ ] **Step 5: Watch deploy**

```bash
gh run watch <deploy-run-id> --exit-status
```

Confirm TestFlight build 17+ uploaded successfully. If still fails, investigate; the only remaining failure mode should be unrelated (e.g., Doppler flake — rerun if so).

---

## Self-Review Notes

- **Spec coverage:** All PR 1 changes from the spec are covered (Watch dir delete, target removal, protocol removal, wiring removal, CI/build script update, CLAUDE.md update, tests update). ✓
- **Placeholder scan:** Body of PR is `"..."` in Task 13 step 1 — that's intentionally TBD because the body should reference what landed; written at PR-creation time, not now.
- **Type consistency:** `connectivity` and `alarm` parameter names match throughout; `BlinkBreak Watch App` directory name (with space) is preserved consistently.
- **One soft TODO:** Task 5 step 3 says "tests whose only assertions are against these removed surfaces should be deleted entirely." This is judgment-call territory; the executor needs to read each test and decide. That's an acceptable level of judgment for an experienced engineer.
