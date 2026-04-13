# Architecture Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the codebase for readability, clean API surfaces, and proper separation of concerns across 8 design changes.

**Architecture:** Pure refactor — no new features, no behavior changes. Mechanical renames (states, protocol, method), structural improvements (timer elimination, double-write fix, logic extraction), and minor API cleanup (DiagnosticCollector, notification categories).

**Tech Stack:** Swift 5.9+, SwiftUI (iOS 17+ / watchOS 10+), Swift Testing framework, XCUITest

**Spec:** `docs/superpowers/specs/2026-04-13-architecture-cleanup-design.md`

---

## File Map

### BlinkBreakCore (Sources)

| File | Changes |
|------|---------|
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionState.swift` | Rename enum cases, delete `.name`, update `.description` |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift` | Rename states in switch/comments, rename `reconcileOnLaunch`→`reconcile`, extract `startSession(wasAutoStarted:)` |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift` | Rename `reconcileOnLaunch`→`reconcile` |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift` | Rename `lookAwayStartedAt`→`breakActiveStartedAt`, add `CodingKeys` |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/WatchConnectivityService.swift` | Rename `lookAwayStartedAt`→`breakActiveStartedAt` in `SessionSnapshot`, add `CodingKeys` |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/ScheduleEvaluator.swift` | Rename protocol `ScheduleEvaluating`→`ScheduleEvaluatorProtocol`, add `statusText(at:calendar:)` |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift` | Add schedule category to `registerCategories()` |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/DiagnosticCollector.swift` | Change `sessionState` parameter from `String` to `SessionState` |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift` | Add `scheduleStartActionId` and `scheduleCategoryId` (move from iOS target) |

### BlinkBreakCore (Tests)

| File | Changes |
|------|---------|
| `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift` | Rename states in assertions, `reconcileOnLaunch`→`reconcile`, `.name`→`.description` |
| `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift` | Rename states in assertions, `reconcileOnLaunch`→`reconcile` |
| `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleIntegrationTests.swift` | `reconcileOnLaunch`→`reconcile` |
| `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleEvaluatorTests.swift` | Add `statusText` tests |
| `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockScheduleEvaluator.swift` | Rename protocol conformance, add `statusText` stub |

### iOS App (BlinkBreak/)

| File | Action |
|------|--------|
| `BlinkBreak/Views/BreakActiveView.swift` | **Rename file** → `BreakPendingView.swift`, rename struct |
| `BlinkBreak/Views/LookAwayView.swift` | **Rename file** → `BreakActiveView.swift`, rename struct |
| `BlinkBreak/Views/RootView.swift` | Remove timer, update switch cases, add `scenePhase` observer |
| `BlinkBreak/Views/RunningView.swift` | Replace `Timer.publish` with `TimelineView` |
| `BlinkBreak/Views/IdleView.swift` | Update `ScheduleStatusLabel` call site |
| `BlinkBreak/Views/ScheduleSection.swift` | No changes |
| `BlinkBreak/Views/Components/ScheduleStatusLabel.swift` | Simplify to render evaluator output |
| `BlinkBreak/Views/Components/TimeFormatting.swift` | Move `formatScheduleTime` to BlinkBreakCore |
| `BlinkBreak/Preview/PreviewSessionController.swift` | Rename states, `reconcileOnLaunch`→`reconcile` |
| `BlinkBreak/BlinkBreakApp.swift` | Remove schedule category registration, update call sites |
| `BlinkBreak/AppDelegate.swift` | Add `reconcile()` call in `willPresent`, update `reconcileOnLaunch` |
| `BlinkBreak/ScheduleTaskManager.swift` | Rename `ScheduleEvaluating`→`ScheduleEvaluatorProtocol`, `reconcileOnLaunch`→`reconcile` |
| `BlinkBreak/BugReport/ShakeDetector.swift` | Update `DiagnosticCollector` call site |

### watchOS App (BlinkBreak Watch App/)

| File | Action |
|------|--------|
| `BlinkBreak Watch App/Views/WatchBreakActiveView.swift` | **Rename file** → `WatchBreakPendingView.swift`, rename struct |
| `BlinkBreak Watch App/Views/WatchLookAwayView.swift` | **Rename file** → `WatchBreakActiveView.swift`, rename struct |
| `BlinkBreak Watch App/Views/WatchRootView.swift` | Remove timer, update switch cases |
| `BlinkBreak Watch App/Views/WatchRunningView.swift` | Replace `Timer.publish` with `TimelineView` |
| `BlinkBreak Watch App/BlinkBreakWatchApp.swift` | Update `reconcileOnLaunch`→`reconcile` |
| `BlinkBreak Watch App/WatchAppDelegate.swift` | Add `reconcile()` call in `willPresent` |

### Integration Tests (BlinkBreakUITests/)

| File | Changes |
|------|---------|
| `BlinkBreakUITests/BlinkBreakUITestsBase.swift` | Rename `A11y.BreakActive`→`A11y.BreakPending`, `A11y.LookAway`→`A11y.BreakActive`, update comments |
| `BlinkBreakUITests/BreakCycleTests.swift` | Update all A11y references and comments |
| `BlinkBreakUITests/ReconciliationTests.swift` | Update all A11y references and comments |
| `BlinkBreakUITests/LaunchAndIdleTests.swift` | Update comments |

---

## Task 1: Rename `ScheduleEvaluating` → `ScheduleEvaluatorProtocol`

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/ScheduleEvaluator.swift`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`
- Modify: `BlinkBreak/ScheduleTaskManager.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockScheduleEvaluator.swift`

- [ ] **Step 1: Rename the protocol and all conformances**

In `ScheduleEvaluator.swift`, rename the protocol:

```swift
public protocol ScheduleEvaluatorProtocol: Sendable {
    func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool
    func nextTransitionDate(from date: Date, calendar: Calendar) -> Date?
}

public struct NoopScheduleEvaluator: ScheduleEvaluatorProtocol {
```

```swift
public final class ScheduleEvaluator: ScheduleEvaluatorProtocol, @unchecked Sendable {
```

In `SessionController.swift`, update the property type (line 42) and init parameter (line 63):

```swift
private let scheduleEvaluator: ScheduleEvaluatorProtocol
```

```swift
scheduleEvaluator: ScheduleEvaluatorProtocol = NoopScheduleEvaluator(),
```

In `ScheduleTaskManager.swift`, update the property type (line 21) and init parameter (line 26):

```swift
private let evaluator: ScheduleEvaluatorProtocol
```

```swift
evaluator: ScheduleEvaluatorProtocol,
```

In `MockScheduleEvaluator.swift`, update the conformance (line 11):

```swift
final class MockScheduleEvaluator: ScheduleEvaluatorProtocol, @unchecked Sendable {
```

- [ ] **Step 2: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "Rename ScheduleEvaluating → ScheduleEvaluatorProtocol for naming consistency"
```

---

## Task 2: Remove `SessionState.name`, use `.description` everywhere

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionState.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift`

- [ ] **Step 1: Delete the `.name` property**

In `SessionState.swift`, delete lines 62-70 (the entire `name` computed property and its doc comment):

```swift
    /// The name of the current state, for logging and debugging.
    public var name: String {
        switch self {
        case .idle:        return "idle"
        case .running:     return "running"
        case .breakActive: return "breakActive"
        case .lookAway:    return "lookAway"
        }
    }
```

- [ ] **Step 2: Update the 3 test assertions that use `.name`**

In `SessionControllerTests.swift`, update the `fullLoop` test (lines 404, 411, 418):

```swift
        #expect(f.controller.state.description == "running")
```

```swift
        #expect(f.controller.state.description == "lookAway")
```

```swift
        #expect(f.controller.state.description == "running")
```

- [ ] **Step 3: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Remove SessionState.name — use .description (CustomStringConvertible) everywhere"
```

---

## Task 3: Rename states — `breakActive` → `breakPending`, `lookAway` → `breakActive`

This is a large mechanical rename across the entire codebase. The approach: rename in BlinkBreakCore first (enum, controller, persistence, connectivity), then views, then tests.

**Files (all):** See File Map above — every file with a state reference changes.

### Part A: Core types

- [ ] **Step 1: Rename enum cases in `SessionState.swift`**

Replace the enum cases and all extensions:

```swift
public enum SessionState: Equatable, Sendable {

    /// No session running. Start button is visible. No pending notifications.
    case idle

    /// A session is active, counting down to the next break.
    /// - Parameter cycleStartedAt: When the current 20-minute countdown started.
    case running(cycleStartedAt: Date)

    /// The break notification has fired. Awaiting user confirmation to start the break.
    /// - Parameter cycleStartedAt: When the 20-minute countdown for this cycle started.
    case breakPending(cycleStartedAt: Date)

    /// The user confirmed the break. The 20-second look-away is counting down.
    /// - Parameter startedAt: When the break began.
    case breakActive(startedAt: Date)
}

// MARK: - Convenience queries

extension SessionState {

    /// `true` if the session is active in any form (not `.idle`).
    public var isActive: Bool {
        switch self {
        case .idle:
            return false
        case .running, .breakPending, .breakActive:
            return true
        }
    }
}

extension SessionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: return "idle"
        case .running: return "running"
        case .breakPending: return "breakPending"
        case .breakActive: return "breakActive"
        }
    }
}
```

Update the state diagram in the file header comment:

```swift
//  The four-case state enum that drives all UI and the state machine. Views `switch`
//  on this enum to render their body; they never contain business logic beyond that.
//
//  Flutter analogue: this is the equivalent of a sealed class with four subtypes,
//  consumed by a Selector<SessionState, SessionState> and rendered with a switch.
//
```

- [ ] **Step 2: Rename `lookAwayStartedAt` → `breakActiveStartedAt` in `SessionRecord.swift`**

Rename the property and add `CodingKeys` for backwards compatibility:

```swift
    /// When the current break window began. Non-nil only in the `breakActive` state.
    public var breakActiveStartedAt: Date?
```

Add `CodingKeys` enum inside the struct (after the `wasAutoStarted` property, before `init`):

```swift
    private enum CodingKeys: String, CodingKey {
        case sessionActive
        case currentCycleId
        case cycleStartedAt
        case breakActiveStartedAt = "lookAwayStartedAt"
        case lastUpdatedAt
        case manualStopDate
        case wasAutoStarted
    }
```

Update `init`:

```swift
    public init(
        sessionActive: Bool = false,
        currentCycleId: UUID? = nil,
        cycleStartedAt: Date? = nil,
        breakActiveStartedAt: Date? = nil,
        lastUpdatedAt: Date? = nil,
        manualStopDate: Date? = nil,
        wasAutoStarted: Bool? = nil
    ) {
        self.sessionActive = sessionActive
        self.currentCycleId = currentCycleId
        self.cycleStartedAt = cycleStartedAt
        self.breakActiveStartedAt = breakActiveStartedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.manualStopDate = manualStopDate
        self.wasAutoStarted = wasAutoStarted
    }
```

Update `init(from snapshot:)`:

```swift
    public init(from snapshot: SessionSnapshot) {
        self.sessionActive = snapshot.sessionActive
        self.currentCycleId = snapshot.currentCycleId
        self.cycleStartedAt = snapshot.cycleStartedAt
        self.breakActiveStartedAt = snapshot.breakActiveStartedAt
        self.lastUpdatedAt = snapshot.updatedAt
    }
```

Update `idle` sentinel:

```swift
    public static let idle = SessionRecord(
        sessionActive: false,
        currentCycleId: nil,
        cycleStartedAt: nil,
        breakActiveStartedAt: nil,
        lastUpdatedAt: nil
    )
```

- [ ] **Step 3: Rename `lookAwayStartedAt` → `breakActiveStartedAt` in `SessionSnapshot`**

In `WatchConnectivityService.swift`, rename the property and add `CodingKeys`:

```swift
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public let sessionActive: Bool
    public let currentCycleId: UUID?
    public let cycleStartedAt: Date?
    public let breakActiveStartedAt: Date?
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case sessionActive
        case currentCycleId
        case cycleStartedAt
        case breakActiveStartedAt = "lookAwayStartedAt"
        case updatedAt
    }

    public init(
        sessionActive: Bool,
        currentCycleId: UUID?,
        cycleStartedAt: Date?,
        breakActiveStartedAt: Date?,
        updatedAt: Date
    ) {
        self.sessionActive = sessionActive
        self.currentCycleId = currentCycleId
        self.cycleStartedAt = cycleStartedAt
        self.breakActiveStartedAt = breakActiveStartedAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 4: Update `SessionController.swift` — all state references**

In `reconcileState()`, update case 3 (the break-active window check):

```swift
        // Case 3: if we're still inside the breakActive window, show breakActive.
        if let breakActiveStartedAt = record.breakActiveStartedAt {
            let breakActiveEnd = breakActiveStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)
            if now < breakActiveEnd {
                state = .breakActive(startedAt: breakActiveStartedAt)
                return
            }
            // breakActive has already elapsed. Clear the stale field in persistence and fall
            // through to the running/breakPending check below. The persisted cycleStartedAt
            // already points to the next cycle (set when handleStartBreakAction ran).
            var cleared = record
            cleared.breakActiveStartedAt = nil
            persistence.save(cleared)
            broadcastSnapshot(for: cleared)
        }
```

Update case 5:

```swift
        // Case 5: break time has arrived (or passed) without a break-active start.
        // State is breakPending — the user needs to confirm the break.
        state = .breakPending(cycleStartedAt: cycleStartedAt)
```

In `handleStartBreakAction`, update the state transition and record:

```swift
        // 3. The user is about to start the break. Generate a new cycleId for the NEXT cycle.
        let breakActiveStartedAt = clock()
        let nextCycleId = UUID()
        let nextCycleStartedAt = breakActiveStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)

        // 4. Schedule the "done, back to work" notification.
        scheduler.schedule(
            CascadeBuilder.buildDoneNotification(cycleId: cycleId, breakActiveStartedAt: breakActiveStartedAt)
        )
```

```swift
        let newRecord = SessionRecord(
            sessionActive: true,
            currentCycleId: nextCycleId,
            cycleStartedAt: nextCycleStartedAt,
            breakActiveStartedAt: breakActiveStartedAt,
            lastUpdatedAt: clock(),
            wasAutoStarted: record.wasAutoStarted
        )
        persistence.save(newRecord)

        // 8. Update UI state and broadcast to the Watch.
        state = .breakActive(startedAt: breakActiveStartedAt)
```

In `handleRemoteSnapshot`, update the remote-ack detection:

```swift
        let remoteAckedBreak = snapshot.breakActiveStartedAt != nil && local.breakActiveStartedAt == nil
```

In `broadcastSnapshot`, update the snapshot construction:

```swift
    private func broadcastSnapshot(for record: SessionRecord) {
        let snapshot = SessionSnapshot(
            sessionActive: record.sessionActive,
            currentCycleId: record.currentCycleId,
            cycleStartedAt: record.cycleStartedAt,
            breakActiveStartedAt: record.breakActiveStartedAt,
            updatedAt: clock()
        )
        connectivity.broadcast(snapshot)
    }
```

- [ ] **Step 5: Update `CascadeBuilder.buildDoneNotification` parameter name**

In `NotificationScheduler.swift`, rename the parameter:

```swift
    public static func buildDoneNotification(
        cycleId: UUID,
        breakActiveStartedAt: Date
    ) -> ScheduledNotification {
        ScheduledNotification(
            identifier: BlinkBreakConstants.doneIdPrefix + cycleId.uuidString,
            title: "Back to work",
            body: "Your eyes had a rest. Carry on.",
            fireDate: breakActiveStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration),
            isTimeSensitive: false,
            threadIdentifier: cycleId.uuidString,
            categoryIdentifier: nil
        )
    }
```

- [ ] **Step 6: Run unit tests to verify core compiles and passes**

Run: `./scripts/test.sh`
Expected: All tests FAIL (test code still uses old names). Core should compile.

### Part B: Tests

- [ ] **Step 7: Update `SessionControllerTests.swift`**

Update `ackTransitionsToLookAway` test (rename + state check):

```swift
    @Test("handleStartBreakAction with current cycleId transitions running → breakActive")
    func ackTransitionsToBreakActive() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!
        f.advance(by: BlinkBreakConstants.breakInterval + 1)

        f.controller.handleStartBreakAction(cycleId: cycleId)

        guard case .breakActive(let startedAt) = f.controller.state else {
            Issue.record("expected breakActive, got \(f.controller.state)")
            return
        }
        #expect(startedAt == f.nowBox.value)
    }
```

Update `startPersistsRecord` (line 105):

```swift
        #expect(record.breakActiveStartedAt == nil)
```

Update `ackUpdatesPersistenceWithNewCycle` (line 267):

```swift
        #expect(record.breakActiveStartedAt == f.nowBox.value)
```

Update `fullLoop` test — replace `.name` references with `.description` and use new state names:

```swift
    @Test("full loop: start → wait → ack → wait → reconcile → stop")
    func fullLoop() async {
        let f = Fixture()

        // Start
        f.controller.start()
        let firstCycleId = f.persistence.load().currentCycleId!
        #expect(f.controller.state.description == "running")

        // Break time arrives
        f.advance(by: BlinkBreakConstants.breakInterval)

        // User acknowledges
        f.controller.handleStartBreakAction(cycleId: firstCycleId)
        #expect(f.controller.state.description == "breakActive")

        // Break elapses
        f.advance(by: BlinkBreakConstants.lookAwayDuration + 1)

        // Reconcile picks up that we've rolled into the next running cycle
        await f.controller.reconcileOnLaunch()
        #expect(f.controller.state.description == "running")

        let newRecord = f.persistence.load()
        #expect(newRecord.currentCycleId != firstCycleId)

        // User stops
        f.controller.stop()
        #expect(f.controller.state == .idle)
        #expect(f.persistence.load().sessionActive == false)
    }
```

Update `remoteAckCancelsDelivered` and `remoteAckDisarmsAlarm` snapshots (lines 325, 345):

```swift
            breakActiveStartedAt: f.nowBox.value,
```

Update `remoteSnapshotDoubleDelivery` snapshot (line 365):

```swift
            breakActiveStartedAt: f.nowBox.value,
```

Update `remoteSnapshotStaleIgnored` snapshot (line 389):

```swift
            breakActiveStartedAt: nil,
```

- [ ] **Step 8: Update `ReconciliationTests.swift`**

Update `pastBreakWithPendingCascade` assertion (line 98):

```swift
        guard case .breakPending(let startedAt) = f.controller.state else {
            Issue.record("expected breakPending, got \(f.controller.state)")
```

Update `pastBreakNoPending` assertion and comment (line 105, 128):

```swift
    @Test("reconcile past break time with no pending notifications → breakPending (single-notification design)")
    func pastBreakNoPending() async {
```

```swift
        guard case .breakPending(let startedAt) = f.controller.state else {
            Issue.record("expected breakPending, got \(f.controller.state)")
```

Update `withinLookAwayWindow` (rename to `withinBreakActiveWindow`, line 135):

```swift
    @Test("reconcile within breakActive window → breakActive")
    func withinBreakActiveWindow() async {
        let f = Fixture()
        let breakActiveStart = f.nowBox.value
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: breakActiveStart.addingTimeInterval(BlinkBreakConstants.lookAwayDuration),
            breakActiveStartedAt: breakActiveStart
        ))

        f.advance(by: BlinkBreakConstants.lookAwayDuration / 2)

        await f.controller.reconcileOnLaunch()

        guard case .breakActive(let startedAt) = f.controller.state else {
            Issue.record("expected breakActive, got \(f.controller.state)")
            return
        }
        #expect(startedAt == breakActiveStart)
    }
```

Update `afterLookAwayExpired` (rename to `afterBreakActiveExpired`, line 157):

```swift
    @Test("reconcile after breakActive expired → next running cycle")
    func afterBreakActiveExpired() async {
        let f = Fixture()
        let breakActiveStart = f.nowBox.value
        let nextCycleId = UUID()
        let nextCycleStart = breakActiveStart.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: nextCycleId,
            cycleStartedAt: nextCycleStart,
            breakActiveStartedAt: breakActiveStart
        ))
        f.scheduler.stubPendingIdentifiers = CascadeBuilder.identifiers(for: nextCycleId)

        f.advance(by: BlinkBreakConstants.lookAwayDuration + 1)

        await f.controller.reconcileOnLaunch()

        guard case .running(let startedAt) = f.controller.state else {
            Issue.record("expected running, got \(f.controller.state)")
            return
        }
        #expect(startedAt == nextCycleStart)
        #expect(f.persistence.load().breakActiveStartedAt == nil)
    }
```

- [ ] **Step 9: Update `ScheduleIntegrationTests.swift`**

Update `autoStartSurvivesBreakCycle` comment (line 154):

```swift
        // Advance past the break interval so reconcile transitions to breakPending.
```

- [ ] **Step 10: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

### Part C: iOS Views

- [ ] **Step 11: Rename iOS view files**

First rename `BreakActiveView.swift` → `BreakPendingView.swift` (must happen first to avoid collision):

```bash
cd /Users/tylerholland/Dev/BlinkBreak
git mv BlinkBreak/Views/BreakActiveView.swift BlinkBreak/Views/BreakPendingView.swift
```

Then rename `LookAwayView.swift` → `BreakActiveView.swift`:

```bash
git mv BlinkBreak/Views/LookAwayView.swift BlinkBreak/Views/BreakActiveView.swift
```

- [ ] **Step 12: Update the renamed `BreakPendingView.swift` (was BreakActiveView)**

Update the file header, struct name, accessibility identifier, and preview:

```swift
//
//  BreakPendingView.swift
//  BlinkBreak
//
//  The breakPending-state view. Full-bleed red alert with a large "Start break"
//  button. Only shown when the app is foregrounded during the break notification —
//  backgrounded users see the notifications instead.
//
//  Contains zero business logic: the "Start break" button calls
//  `controller.acknowledgeCurrentBreak()` and the controller looks up its own
//  cycleId from persistence. The view doesn't know or care about cycleIds.
//

import SwiftUI
import BlinkBreakCore

struct BreakPendingView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            EyebrowLabel(text: "Break time")

            Text("Look at something\n20 feet away")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("Focus on a distant object for 20 seconds to rest your eyes.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            Button {
                controller.acknowledgeCurrentBreak()
            } label: {
                Text("Start break")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.69, green: 0.00, blue: 0.13))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("button.breakPending.startBreak")
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

#Preview {
    ZStack {
        AlertBackground()
        BreakPendingView(controller: PreviewSessionController.breakPending)
    }
}
```

- [ ] **Step 13: Update the renamed `BreakActiveView.swift` (was LookAwayView)**

```swift
//
//  BreakActiveView.swift
//  BlinkBreak
//
//  The breakActive-state view. Calm dark theme. No countdown UI — the entire point
//  of the 20-second rest is to stop looking at screens. The user doesn't need
//  to see this view; it's here only for the rare case they foreground the app
//  mid-break. A haptic on the Watch will tell them when the 20 seconds are up.
//
//  The only interactive element is the Stop button, in case the user is ending
//  their session entirely.
//

import SwiftUI
import BlinkBreakCore

struct BreakActiveView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    var body: some View {
        VStack(spacing: 16) {
            EyebrowLabel(text: "Looking away")

            Spacer()

            Text("Don't look at this screen.\nWe'll haptic you when your 20 seconds are up.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 32)
                .accessibilityIdentifier("label.breakActive.message")

            Spacer()

            DestructiveButton(title: "Stop") {
                controller.stop()
            }
            .accessibilityIdentifier("button.breakActive.stop")
        }
        .padding(24)
    }
}

#Preview {
    ZStack {
        CalmBackground()
        BreakActiveView(controller: PreviewSessionController.breakActive)
    }
}
```

- [ ] **Step 14: Update `RootView.swift` switch cases**

Update the state dispatch (lines 32-51):

```swift
            switch controller.state {
            case .breakPending:
                AlertBackground()
            default:
                CalmBackground()
            }

            // Swap the foreground content based on state.
            Group {
                switch controller.state {
                case .idle:
                    IdleView(controller: controller)
                case .running(let cycleStartedAt):
                    RunningView(controller: controller, cycleStartedAt: cycleStartedAt)
                case .breakPending:
                    BreakPendingView(controller: controller)
                case .breakActive:
                    BreakActiveView(controller: controller)
                }
            }
```

Update previews:

```swift
#Preview("Break Pending") {
    RootView(controller: PreviewSessionController.breakPending)
}

#Preview("Break Active") {
    RootView(controller: PreviewSessionController.breakActive)
}
```

- [ ] **Step 15: Update `PreviewSessionController.swift`**

```swift
    func handleStartBreakAction(cycleId: UUID) {
        state = .breakActive(startedAt: Date())
    }

    func acknowledgeCurrentBreak() {
        state = .breakActive(startedAt: Date())
    }
```

```swift
    static var breakPending: PreviewSessionController {
        PreviewSessionController(
            state: .breakPending(cycleStartedAt: Date().addingTimeInterval(-20 * 60))
        )
    }

    static var breakActive: PreviewSessionController {
        PreviewSessionController(
            state: .breakActive(startedAt: Date().addingTimeInterval(-5))
        )
    }
```

### Part D: Watch Views

- [ ] **Step 16: Rename Watch view files**

```bash
cd /Users/tylerholland/Dev/BlinkBreak
git mv "BlinkBreak Watch App/Views/WatchBreakActiveView.swift" "BlinkBreak Watch App/Views/WatchBreakPendingView.swift"
git mv "BlinkBreak Watch App/Views/WatchLookAwayView.swift" "BlinkBreak Watch App/Views/WatchBreakActiveView.swift"
```

- [ ] **Step 17: Update `WatchBreakPendingView.swift` (was WatchBreakActiveView)**

```swift
//
//  WatchBreakPendingView.swift
//  BlinkBreak Watch App
//
//  Break-pending state on the Watch. Full-bleed red with a large Start break button.

import SwiftUI
import BlinkBreakCore

struct WatchBreakPendingView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    var body: some View {
        VStack(spacing: 10) {
            Text("LOOK AWAY")
                .font(.caption2)
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.9))

            Text("20 ft")
                .font(.title.weight(.semibold))

            Spacer()

            Button("Start break") {
                controller.acknowledgeCurrentBreak()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(Color(red: 0.69, green: 0, blue: 0.13))
            .accessibilityIdentifier("button.breakPending.startBreak")
        }
        .padding(.vertical, 10)
    }
}
```

- [ ] **Step 18: Update `WatchBreakActiveView.swift` (was WatchLookAwayView)**

```swift
//
//  WatchBreakActiveView.swift
//  BlinkBreak Watch App
//
//  Break-active state on the Watch. Minimal — the user should NOT be staring at
//  their wrist during the 20-second break.

import SwiftUI

struct WatchBreakActiveView: View {

    var body: some View {
        VStack(spacing: 8) {
            Text("Look 20 ft away")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("label.breakActive.message")

            Text("We'll tap you when it's time")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
```

- [ ] **Step 19: Update `WatchRootView.swift` switch cases**

```swift
            switch controller.state {
            case .breakPending:
                Color(red: 0.69, green: 0, blue: 0.13).ignoresSafeArea()
            default:
                Color.black.ignoresSafeArea()
            }

            Group {
                switch controller.state {
                case .idle:
                    WatchIdleView(controller: controller)
                case .running(let cycleStartedAt):
                    WatchRunningView(controller: controller, cycleStartedAt: cycleStartedAt)
                case .breakPending:
                    WatchBreakPendingView(controller: controller)
                case .breakActive:
                    WatchBreakActiveView()
                }
            }
```

### Part E: Integration tests

- [ ] **Step 20: Update `A11y` enum in `BlinkBreakUITestsBase.swift`**

```swift
enum A11y {
    enum Idle {
        static let startButton = "button.idle.start"
    }
    enum Running {
        static let stopButton = "button.running.stop"
        static let countdown = "label.running.countdown"
    }
    enum BreakPending {
        static let startBreakButton = "button.breakPending.startBreak"
    }
    enum BreakActive {
        static let stopButton = "button.breakActive.stop"
        static let message = "label.breakActive.message"
    }
    enum Schedule {
        static let section = "section.schedule"
        static let statusLabel = "label.schedule.status"
    }
}
```

Update the `launchForIntegrationTest` comment — replace "lookAway" with "breakActive":

```swift
    /// Defaults: 3-second break interval, 3-second breakActive duration.
```

- [ ] **Step 21: Update `BreakCycleTests.swift`**

Replace all `A11y.BreakActive.` → `A11y.BreakPending.` and `A11y.LookAway.` → `A11y.BreakActive.` references, and update comments. Every `A11y.BreakActive.startBreakButton` becomes `A11y.BreakPending.startBreakButton`. Every `A11y.LookAway.stopButton` becomes `A11y.BreakActive.stopButton`. Every `A11y.LookAway.message` becomes `A11y.BreakActive.message`.

Update test names and comments:
- `test_breakActive_tapStartBreak_transitionsToLookAway` → `test_breakPending_tapStartBreak_transitionsToBreakActive`
- `test_lookAway_autoTransitionsBackToRunning_afterLookAwayDuration` → `test_breakActive_autoTransitionsBackToRunning_afterBreakDuration`
- Comments: "running → breakActive" → "running → breakPending", "lookAway → running" → "breakActive → running"
- Full cycle comment: `idle → running → breakPending → breakActive → running → idle`

- [ ] **Step 22: Update `ReconciliationTests.swift` (UI tests)**

Replace all `A11y.BreakActive.` → `A11y.BreakPending.` and `A11y.LookAway.` → `A11y.BreakActive.` references. Update comments mentioning "lookAway" or "breakActive" to use the new names.

- [ ] **Step 23: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 24: Commit the full state rename**

```bash
git add -A && git commit -m "Rename breakActive → breakPending, lookAway → breakActive

The old names were misleading: 'breakActive' meant 'waiting for user
confirmation' and 'lookAway' meant 'break is actually active'. New names
match the actual semantics. CodingKeys preserve backwards compatibility
with existing persisted data and Watch wire format."
```

---

## Task 4: Eliminate double-write in `evaluateSchedule()`

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`

- [ ] **Step 1: Extract `startSession(wasAutoStarted:)`**

In `SessionController.swift`, replace the `start()` method and add a private helper:

```swift
    public func start() {
        startSession(wasAutoStarted: false)
    }

    /// Core start logic used by both manual `start()` and schedule-driven auto-start.
    private func startSession(wasAutoStarted: Bool) {
        // Clean up any stale state from a previous (possibly crashed) session.
        scheduler.cancelAll()

        let cycleId = UUID()
        let cycleStartedAt = clock()

        let record = SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: cycleStartedAt,
            breakActiveStartedAt: nil,
            lastUpdatedAt: cycleStartedAt,
            wasAutoStarted: wasAutoStarted ? true : nil
        )
        persistence.save(record)

        // Schedule the single break notification for this cycle.
        scheduler.schedule(CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: cycleStartedAt))

        // Arm the Watch-side extended runtime session alarm. No-op on iPhone.
        alarm.arm(
            cycleId: cycleId,
            fireDate: cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        )

        state = .running(cycleStartedAt: cycleStartedAt)
        broadcastSnapshot(for: record)
    }
```

- [ ] **Step 2: Simplify `evaluateSchedule()` to use `startSession(wasAutoStarted: true)`**

```swift
    private func evaluateSchedule() {
        guard weeklySchedule.isEnabled else { return }
        let record = persistence.load()
        let now = clock()
        let shouldBeActive = scheduleEvaluator.shouldBeActive(
            at: now,
            manualStopDate: record.manualStopDate,
            calendar: calendar
        )
        if shouldBeActive && state == .idle {
            startSession(wasAutoStarted: true)
        } else if !shouldBeActive && state.isActive && (record.wasAutoStarted ?? false) {
            stop()
        }
    }
```

- [ ] **Step 3: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass (especially `autoStartSurvivesBreakCycle` which verifies `wasAutoStarted` persists across break cycles).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Eliminate double-write in evaluateSchedule()

Extract startSession(wasAutoStarted:) so schedule-driven auto-start
writes wasAutoStarted in a single persistence save instead of calling
start() then patching the record."
```

---

## Task 5: Eliminate polling timer, notification-driven transitions

**Files:**
- Modify: `BlinkBreak/Views/RootView.swift`
- Modify: `BlinkBreak/Views/RunningView.swift`
- Modify: `BlinkBreak/AppDelegate.swift`
- Modify: `BlinkBreak Watch App/Views/WatchRootView.swift`
- Modify: `BlinkBreak Watch App/Views/WatchRunningView.swift`
- Modify: `BlinkBreak Watch App/WatchAppDelegate.swift`

- [ ] **Step 1: Remove timer from `RootView.swift`, add `scenePhase` observer**

Replace the entire `RootView` body:

```swift
struct RootView<Controller: SessionControllerProtocol>: View {

    /// The session controller driving the app. Injected from BlinkBreakApp so that
    /// previews can substitute a PreviewSessionController.
    @ObservedObject var controller: Controller

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Swap the background based on state so the red alert is unmistakable.
            switch controller.state {
            case .breakPending:
                AlertBackground()
            default:
                CalmBackground()
            }

            // Swap the foreground content based on state.
            Group {
                switch controller.state {
                case .idle:
                    IdleView(controller: controller)
                case .running(let cycleStartedAt):
                    RunningView(controller: controller, cycleStartedAt: cycleStartedAt)
                case .breakPending:
                    BreakPendingView(controller: controller)
                case .breakActive:
                    BreakActiveView(controller: controller)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: controller.state)
        }
        .foregroundStyle(.white)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await controller.reconcile() }
            }
        }
    }
}
```

(Note: `reconcile()` is still named `reconcileOnLaunch()` at this point — Task 6 does the rename. Use the current name for now.)

Actually, to avoid a two-step compile break, use the current name `reconcileOnLaunch()` in this task and rename in Task 6.

```swift
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await controller.reconcileOnLaunch() }
            }
        }
```

- [ ] **Step 2: Replace `Timer.publish` with `TimelineView` in `RunningView.swift`**

Replace the entire `RunningView`:

```swift
struct RunningView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    let cycleStartedAt: Date

    var body: some View {
        TimelineView(.periodic(every: 1)) { context in
            let now = context.date
            let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
            let remainingSeconds = max(0, breakFireTime.timeIntervalSince(now))
            let total = Int(remainingSeconds.rounded(.up))
            let countdownLabel = String(format: "%02d:%02d", total / 60, total % 60)
            let progress = (BlinkBreakConstants.breakInterval - remainingSeconds) / BlinkBreakConstants.breakInterval

            VStack(spacing: 20) {
                EyebrowLabel(text: "Next break in")

                CountdownRing(progress: progress, label: countdownLabel)
                    .accessibilityIdentifier("label.running.countdown")

                Text("Fires at \(breakFireTimeFormatted)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                DestructiveButton(title: "Stop") {
                    controller.stop()
                }
                .accessibilityIdentifier("button.running.stop")
            }
            .padding(24)
        }
    }

    private var breakFireTimeFormatted: String {
        let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: breakFireTime)
    }
}
```

- [ ] **Step 3: Add `reconcile()` call in iOS `AppDelegate.willPresent`**

In `AppDelegate.swift`, update `willPresent` to trigger reconcile when a notification fires in the foreground:

```swift
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Reconcile state when a notification fires while the app is foregrounded.
        // This drives the running → breakPending and breakActive → running transitions
        // without needing a polling timer.
        Task { @MainActor in
            await controller?.reconcileOnLaunch()
        }
        completionHandler([.banner, .sound, .list])
    }
```

- [ ] **Step 4: Remove timer from `WatchRootView.swift`, add `scenePhase` observer**

```swift
struct WatchRootView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch controller.state {
            case .breakPending:
                Color(red: 0.69, green: 0, blue: 0.13).ignoresSafeArea()
            default:
                Color.black.ignoresSafeArea()
            }

            Group {
                switch controller.state {
                case .idle:
                    WatchIdleView(controller: controller)
                case .running(let cycleStartedAt):
                    WatchRunningView(controller: controller, cycleStartedAt: cycleStartedAt)
                case .breakPending:
                    WatchBreakPendingView(controller: controller)
                case .breakActive:
                    WatchBreakActiveView()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: controller.state)
        }
        .foregroundStyle(.white)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await controller.reconcileOnLaunch() }
            }
        }
    }
}
```

- [ ] **Step 5: Replace `Timer.publish` with `TimelineView` in `WatchRunningView.swift`**

```swift
struct WatchRunningView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    let cycleStartedAt: Date

    var body: some View {
        TimelineView(.periodic(every: 1)) { context in
            let now = context.date
            let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
            let remaining = max(0, breakFireTime.timeIntervalSince(now))
            let total = Int(remaining.rounded(.up))
            let countdownLabel = String(format: "%02d:%02d", total / 60, total % 60)

            VStack(spacing: 8) {
                Text("NEXT BREAK")
                    .font(.caption2)
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))

                Text(countdownLabel)
                    .font(.system(size: 34, weight: .ultraLight, design: .default))
                    .monospacedDigit()
                    .accessibilityIdentifier("label.running.countdown")

                Spacer()

                Button("Stop") {
                    controller.stop()
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.6))
                .accessibilityIdentifier("button.running.stop")
            }
            .padding(.vertical, 8)
        }
    }
}
```

- [ ] **Step 6: Add `reconcile()` call in `WatchAppDelegate.willPresent`**

```swift
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            await controller?.reconcileOnLaunch()
        }
        completionHandler([.banner, .sound, .list])
    }
```

- [ ] **Step 7: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "Replace polling timer with notification-driven state transitions

Remove the 1-second Timer.publish from RootView and WatchRootView.
State transitions (running → breakPending, breakActive → running) are
now triggered by notification delivery via willPresent, plus scenePhase
changes for foregrounding. Countdown UI uses TimelineView instead of
Timer.publish — only active when the running view is visible."
```

---

## Task 6: Rename `reconcileOnLaunch()` → `reconcile()`

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`
- Modify: `BlinkBreak/BlinkBreakApp.swift`
- Modify: `BlinkBreak/AppDelegate.swift`
- Modify: `BlinkBreak/ScheduleTaskManager.swift`
- Modify: `BlinkBreak/Preview/PreviewSessionController.swift`
- Modify: `BlinkBreak/Views/RootView.swift`
- Modify: `BlinkBreak Watch App/BlinkBreakWatchApp.swift`
- Modify: `BlinkBreak Watch App/WatchAppDelegate.swift`
- Modify: `BlinkBreak Watch App/Views/WatchRootView.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleIntegrationTests.swift`

- [ ] **Step 1: Rename in protocol**

In `SessionControllerProtocol.swift`, rename the method and update the doc comment:

```swift
    /// Rebuilds in-memory state from persistence + clock. Called on app launch,
    /// foregrounding, and notification delivery. Never trusts in-memory state.
    func reconcile() async
```

- [ ] **Step 2: Rename in `SessionController.swift`**

Rename `reconcileOnLaunch()` → `reconcile()` (line 208) and update the doc comment:

```swift
    /// Rebuilds in-memory `state` from the persisted record + the current clock.
    /// Called on launch, foregrounding, and notification delivery. Never trusts
    /// in-memory state. After reconciling persisted state, evaluates the weekly
    /// schedule to auto-start or auto-stop as appropriate.
    public func reconcile() async {
        reconcileState()
        evaluateSchedule()
    }
```

Also update the `handleRemoteSnapshot` call (line 376):

```swift
        Task { await reconcile() }
```

- [ ] **Step 3: Rename in all app-target call sites**

Search-and-replace `reconcileOnLaunch` → `reconcile` in:
- `BlinkBreak/BlinkBreakApp.swift` (line 101)
- `BlinkBreak/AppDelegate.swift` (lines 81, and the new willPresent call)
- `BlinkBreak/ScheduleTaskManager.swift` (line 59)
- `BlinkBreak/Preview/PreviewSessionController.swift` (line 48)
- `BlinkBreak/Views/RootView.swift` (scenePhase handler)
- `BlinkBreak Watch App/BlinkBreakWatchApp.swift` (line 42)
- `BlinkBreak Watch App/WatchAppDelegate.swift` (willPresent handler)
- `BlinkBreak Watch App/Views/WatchRootView.swift` (scenePhase handler)

- [ ] **Step 4: Rename in all test call sites**

Search-and-replace `reconcileOnLaunch` → `reconcile` in:
- `SessionControllerTests.swift` (line 417)
- `ReconciliationTests.swift` (lines 55, 72, 96, 121, 148, 173, 193, 210)
- `ScheduleIntegrationTests.swift` (lines 60, 71, 75, 84, 115, 127, 140, 141, 151, 156, 164, 170)

- [ ] **Step 5: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Rename reconcileOnLaunch() → reconcile()

No longer called from a polling timer — called on launch, foregrounding,
and notification delivery. Name reflects actual usage."
```

---

## Task 7: Move schedule status text into BlinkBreakCore

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/ScheduleEvaluator.swift`
- Create: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/TimeFormatting.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleEvaluatorTests.swift`
- Modify: `BlinkBreak/Views/Components/ScheduleStatusLabel.swift`
- Modify: `BlinkBreak/Views/Components/TimeFormatting.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockScheduleEvaluator.swift`

- [ ] **Step 1: Write failing tests for `statusText`**

In `ScheduleEvaluatorTests.swift`, add a new suite:

```swift
@Suite("ScheduleEvaluator — statusText")
struct ScheduleEvaluatorStatusTextTests {

    let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        return cal
    }()

    func date(weekday: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4
        comps.day = 5 + (weekday - 1)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return calendar.date(from: comps)!
    }

    func evaluator(schedule: WeeklySchedule) -> ScheduleEvaluator {
        ScheduleEvaluator(schedule: { schedule })
    }

    @Test("Returns nil when schedule is disabled")
    func disabledSchedule() {
        var schedule = WeeklySchedule.default
        schedule.isEnabled = false
        let eval = evaluator(schedule: schedule)
        #expect(eval.statusText(at: date(weekday: 2, hour: 10, minute: 0), calendar: calendar) == nil)
    }

    @Test("Returns 'Starts at...' when before today's window")
    func beforeWindow() {
        let eval = evaluator(schedule: .default)
        let text = eval.statusText(at: date(weekday: 2, hour: 7, minute: 0), calendar: calendar)
        #expect(text != nil)
        #expect(text!.hasPrefix("Starts at"))
    }

    @Test("Returns 'Active until...' when inside today's window")
    func insideWindow() {
        let eval = evaluator(schedule: .default)
        let text = eval.statusText(at: date(weekday: 2, hour: 12, minute: 0), calendar: calendar)
        #expect(text != nil)
        #expect(text!.hasPrefix("Active until"))
    }

    @Test("Returns 'Next:...' when after today's window")
    func afterWindow() {
        let eval = evaluator(schedule: .default)
        let text = eval.statusText(at: date(weekday: 2, hour: 18, minute: 0), calendar: calendar)
        #expect(text != nil)
        #expect(text!.hasPrefix("Next:"))
    }

    @Test("Returns 'Next:...' on a disabled day")
    func disabledDay() {
        let eval = evaluator(schedule: .default)
        let text = eval.statusText(at: date(weekday: 1, hour: 10, minute: 0), calendar: calendar) // Sunday
        #expect(text != nil)
        #expect(text!.hasPrefix("Next:"))
    }

    @Test("Returns nil when no days are enabled")
    func noDaysEnabled() {
        let schedule = WeeklySchedule(isEnabled: true, days: [:])
        let eval = evaluator(schedule: schedule)
        #expect(eval.statusText(at: date(weekday: 2, hour: 10, minute: 0), calendar: calendar) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh`
Expected: FAIL — `statusText` method does not exist yet.

- [ ] **Step 3: Create time formatting helper in BlinkBreakCore**

Create `Packages/BlinkBreakCore/Sources/BlinkBreakCore/TimeFormatting.swift`:

```swift
//
//  TimeFormatting.swift
//  BlinkBreakCore
//
//  Locale-aware time formatting used by schedule status text. Shared between
//  BlinkBreakCore (status text computation) and the app targets (UI components).
//

import Foundation

/// Format a time-of-day from DateComponents into a locale-appropriate short string
/// (e.g., "9:00 AM" in en_US, "09:00" in en_GB).
public func formatScheduleTime(_ components: DateComponents) -> String {
    guard let date = Calendar.current.date(from: components) else { return "" }
    return date.formatted(date: .omitted, time: .shortened)
}

/// Convenience overload accepting hour/minute directly.
public func formatScheduleTime(hour: Int, minute: Int) -> String {
    formatScheduleTime(DateComponents(hour: hour, minute: minute))
}
```

- [ ] **Step 4: Add `statusText` to `ScheduleEvaluator`**

In `ScheduleEvaluator.swift`, add `statusText` to the protocol:

```swift
public protocol ScheduleEvaluatorProtocol: Sendable {
    func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool
    func nextTransitionDate(from date: Date, calendar: Calendar) -> Date?
    func statusText(at date: Date, calendar: Calendar) -> String?
}
```

Add a default return to `NoopScheduleEvaluator`:

```swift
public struct NoopScheduleEvaluator: ScheduleEvaluatorProtocol {
    public init() {}
    public func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool { false }
    public func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? { nil }
    public func statusText(at date: Date, calendar: Calendar) -> String? { nil }
}
```

Add the implementation to `ScheduleEvaluator`:

```swift
    public func statusText(at date: Date, calendar: Calendar) -> String? {
        let sched = schedule()
        guard sched.isEnabled else { return nil }

        let weekday = calendar.component(.weekday, from: date)
        if let day = sched.days[weekday], day.isEnabled,
           let startHour = day.startTime.hour, let startMinute = day.startTime.minute,
           let endHour = day.endTime.hour, let endMinute = day.endTime.minute {

            let currentMinutes = calendar.component(.hour, from: date) * 60
                + calendar.component(.minute, from: date)
            let startMinutes = startHour * 60 + startMinute
            let endMinutes = endHour * 60 + endMinute

            if currentMinutes < startMinutes {
                return "Starts at \(formatScheduleTime(hour: startHour, minute: startMinute))"
            } else if currentMinutes < endMinutes {
                return "Active until \(formatScheduleTime(hour: endHour, minute: endMinute))"
            }
        }

        // After today's window or on a disabled day — find the next start.
        return nextStartText(from: date, schedule: sched, calendar: calendar)
    }

    private func nextStartText(from date: Date, schedule sched: WeeklySchedule, calendar: Calendar) -> String? {
        for dayOffset in 1...7 {
            guard let future = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let wd = calendar.component(.weekday, from: future)
            if let d = sched.days[wd], d.isEnabled,
               let h = d.startTime.hour, let m = d.startTime.minute {
                let dayName = calendar.shortWeekdaySymbols[wd - 1]
                return "Next: \(dayName) \(formatScheduleTime(hour: h, minute: m))"
            }
        }
        return nil
    }
```

- [ ] **Step 5: Add `statusText` stub to `MockScheduleEvaluator`**

```swift
    var stubbedStatusText: String?

    func statusText(at date: Date, calendar: Calendar) -> String? {
        stubbedStatusText
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 7: Simplify `ScheduleStatusLabel` to use the evaluator**

The view currently does its own schedule logic. Replace it with a thin wrapper. Since `ScheduleStatusLabel` doesn't have access to the evaluator directly, the simplest approach is to accept the computed text as a parameter instead.

Update `ScheduleStatusLabel.swift`:

```swift
//
//  ScheduleStatusLabel.swift
//  BlinkBreak
//
//  Shows schedule context above the Start button: "Starts at 9:00 AM",
//  "Active until 5:00 PM", or nothing when schedule is disabled.
//
//  The status text is computed by ScheduleEvaluator in BlinkBreakCore.
//

import SwiftUI

struct ScheduleStatusLabel: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityIdentifier("label.schedule.status")
        }
    }
}

#Preview("Before window") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        ScheduleStatusLabel(text: "Starts at 9:00 AM")
    }
}
```

- [ ] **Step 8: Update `IdleView.swift` call site**

The `IdleView` needs access to the evaluator's `statusText`. The cleanest way: pass the evaluator through the view hierarchy from `BlinkBreakApp`, or compute the text at the `IdleView` level. Since the evaluator is already accessible as a static on `BlinkBreakApp`, the simplest approach is to have `IdleView` accept the text:

In `IdleView.swift`, add a parameter and update the call:

```swift
struct IdleView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    let scheduleStatusText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "BlinkBreak")

            Text("20-20-20 Rule")
                .font(.title2.weight(.semibold))

            Text("Every 20 minutes, look at something 20 feet away for 20 seconds. Your eyes will thank you.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)

            ScheduleSection(controller: controller)
                .padding(.top, 12)

            Spacer()

            ScheduleStatusLabel(text: scheduleStatusText)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            PrimaryButton(title: "Start") {
                controller.start()
            }
            .accessibilityIdentifier("button.idle.start")
        }
        .padding(24)
    }
}
```

Update the `IdleView` preview:

```swift
#Preview {
    ZStack {
        CalmBackground()
        IdleView(
            controller: {
                let c = PreviewSessionController(state: .idle)
                c.weeklySchedule = .default
                return c
            }(),
            scheduleStatusText: "Starts at 9:00 AM"
        )
            .foregroundStyle(.white)
    }
}
```

In `RootView.swift`, update the `IdleView` instantiation. Add the evaluator as a parameter to `RootView`:

```swift
struct RootView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    var scheduleEvaluator: ScheduleEvaluatorProtocol = NoopScheduleEvaluator()
```

In the switch case:

```swift
                case .idle:
                    IdleView(
                        controller: controller,
                        scheduleStatusText: scheduleEvaluator.statusText(at: Date(), calendar: .current)
                    )
```

In `BlinkBreakApp.swift`, pass the evaluator to `RootView`:

```swift
            RootView(controller: controller, scheduleEvaluator: Self.sharedEvaluator)
```

Update `RootView` previews to not pass an evaluator (uses default `NoopScheduleEvaluator`).

- [ ] **Step 9: Remove the old business logic from `TimeFormatting.swift` in the app target**

Delete the contents of `BlinkBreak/Views/Components/TimeFormatting.swift` and replace with a re-export:

```swift
//
//  TimeFormatting.swift
//  BlinkBreak
//
//  Re-exports the formatScheduleTime functions from BlinkBreakCore so existing
//  call sites in DayRow.swift continue to compile without import changes.
//

@_exported import func BlinkBreakCore.formatScheduleTime
```

Wait — `@_exported import func` is not standard Swift. The simpler approach: since `DayRow.swift` already imports `BlinkBreakCore`, and the function is now `public` in Core, just delete the app-target `TimeFormatting.swift` file and let `DayRow.swift` use the Core version.

Check if `DayRow.swift` imports `BlinkBreakCore`:

Actually, `DayRow.swift` is under `BlinkBreak/Views/Components/` and likely imports `BlinkBreakCore` since it uses `DaySchedule`. The `formatScheduleTime` calls in `DayRow.swift` will resolve to the Core version automatically since `BlinkBreak` depends on `BlinkBreakCore`.

Delete `BlinkBreak/Views/Components/TimeFormatting.swift`:

```bash
git rm BlinkBreak/Views/Components/TimeFormatting.swift
```

- [ ] **Step 10: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 11: Commit**

```bash
git add -A && git commit -m "Move schedule status text logic into BlinkBreakCore

ScheduleEvaluator.statusText(at:calendar:) replaces inline business logic
in ScheduleStatusLabel. Time formatting helpers moved to BlinkBreakCore.
Status text is now unit-testable alongside other schedule logic."
```

---

## Task 8: Simplify `DiagnosticCollector` — accept `SessionState` instead of `String`

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/DiagnosticCollector.swift`
- Modify: `BlinkBreak/BugReport/ShakeDetector.swift`

- [ ] **Step 1: Change the parameter type**

In `DiagnosticCollector.swift`, change the property and init:

```swift
    private let sessionState: SessionState
```

```swift
    public init(
        scheduler: NotificationSchedulerProtocol,
        persistence: PersistenceProtocol,
        logBuffer: LogBuffer,
        sessionState: SessionState,
        watchIsPaired: Bool,
        watchIsReachable: Bool
    ) {
```

Update the `collect` method to use `.description`:

```swift
            sessionState: sessionState.description,
```

- [ ] **Step 2: Update the call site in `ShakeDetector.swift`**

Find the `DiagnosticCollector` instantiation and change `sessionState: controller.state.description` to `sessionState: controller.state`.

The exact location depends on the file — search for `DiagnosticCollector(` in `ShakeDetector.swift` and change the `sessionState:` argument.

- [ ] **Step 3: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "DiagnosticCollector accepts SessionState instead of String

Eliminates the awkward .description conversion at the call site."
```

---

## Task 9: Consolidate notification category registration

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift`
- Modify: `BlinkBreak/BlinkBreakApp.swift`

- [ ] **Step 1: Move schedule constants to `Constants.swift` if not already there**

Verify `BlinkBreakConstants.scheduleCategoryId` and `scheduleStartActionId` already exist in `Constants.swift`. They do (lines 85-88). No changes needed.

- [ ] **Step 2: Move schedule category registration into `registerCategories()`**

In `NotificationScheduler.swift`, update `registerCategories()` to register both categories:

```swift
    public func registerCategories() {
        // The "Start break" action attached to every break notification.
        let startBreakAction = UNNotificationAction(
            identifier: BlinkBreakConstants.startBreakActionId,
            title: "Start break",
            options: [.foreground]
        )
        let breakCategory = UNNotificationCategory(
            identifier: BlinkBreakConstants.breakCategoryId,
            actions: [startBreakAction],
            intentIdentifiers: [],
            options: []
        )

        // The "Open" action on schedule start-time notifications.
        let scheduleAction = UNNotificationAction(
            identifier: BlinkBreakConstants.scheduleStartActionId,
            title: "Open",
            options: [.foreground]
        )
        let scheduleCategory = UNNotificationCategory(
            identifier: BlinkBreakConstants.scheduleCategoryId,
            actions: [scheduleAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([breakCategory, scheduleCategory])
    }
```

- [ ] **Step 3: Remove the inline category registration from `BlinkBreakApp.swift`**

Remove the 15-line block from `onAppear` (lines 78-92) that registers the schedule category:

```swift
                    // Register the schedule notification category so iOS can display
                    // the "Open" action button on schedule start-time notifications.
                    let scheduleAction = UNNotificationAction(
                        identifier: BlinkBreakConstants.scheduleStartActionId,
                        title: "Open",
                        options: [.foreground]
                    )
                    let scheduleCategory = UNNotificationCategory(
                        identifier: BlinkBreakConstants.scheduleCategoryId,
                        actions: [scheduleAction],
                        intentIdentifiers: []
                    )
                    UNUserNotificationCenter.current().getNotificationCategories { existing in
                        var categories = existing
                        categories.insert(scheduleCategory)
                        UNUserNotificationCenter.current().setNotificationCategories(categories)
                    }
```

- [ ] **Step 4: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Consolidate notification category registration into registerCategories()

Both break and schedule categories are now registered in one place, one
call, at launch. Removes 15 lines of inline UNNotificationCategory
boilerplate from BlinkBreakApp.onAppear."
```

---

## Task 10: Final verification

- [ ] **Step 1: Run unit tests**

Run: `./scripts/test.sh`
Expected: All ~46 tests pass.

- [ ] **Step 2: Run lint**

Run: `./scripts/lint.sh`
Expected: No violations (no SwiftUI/UIKit/WatchKit imports in BlinkBreakCore).

- [ ] **Step 3: Run build**

Run: `./scripts/build.sh`
Expected: BlinkBreakCore builds, iOS + Watch targets build.

- [ ] **Step 4: Run integration tests**

Run: `./scripts/test-integration.sh`
Expected: All 21 integration tests pass. The key tests to watch:
- `test_runningState_autoTransitionsToBreakActive_afterBreakInterval` — now driven by notification delivery instead of polling timer
- `test_breakActive_tapStartBreak_transitionsToLookAway` → now `test_breakPending_tapStartBreak_transitionsToBreakActive`
- Full cycle test — all renamed states

- [ ] **Step 5: Manual smoke test in simulator**

Launch the app in the iOS simulator:
1. Tap Start → verify running state with countdown
2. Wait for break → verify transition to breakPending (red screen with "Start break")
3. Tap "Start break" → verify transition to breakActive (calm screen)
4. Wait for break to end → verify transition back to running
5. Tap Stop → verify back to idle

Key thing to verify: the running → breakPending transition happens **when the notification fires**, not from a polling timer. The countdown should tick down smoothly via `TimelineView`, and the state change should happen at the notification delivery moment.
