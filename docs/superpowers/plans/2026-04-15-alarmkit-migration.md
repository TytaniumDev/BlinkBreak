# PR 2 — AlarmKit Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `UNNotification`-based break-reminder delivery with Apple's AlarmKit framework (iOS 26+). AlarmKit gives full-screen alarm-takeover, plays at alarm volume regardless of silent/DND, and is the Apple-purpose-built API for scheduled-alarm-clock-style alerts.

**Architecture:** Define a narrow `AlarmSchedulerProtocol` in `BlinkBreakCore` that exposes exactly the surface `SessionController` needs (schedule countdown, cancel, observe events). Implement it in the iOS target with `AlarmKitScheduler` wrapping `AlarmManager.shared`. `SessionController` consumes events to chain cycles.

**Tech Stack:** Swift 5.9, AlarmKit (iOS 26+), Swift Testing, xcodegen.

---

## File Map

**Create:**
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/AlarmScheduler.swift` — protocol + value types (`AlarmKind`, `AlarmEvent`)
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockAlarmScheduler.swift` — test mock
- `BlinkBreak/AlarmKitScheduler.swift` — concrete impl wrapping `AlarmManager.shared`
- `BlinkBreak/StartBreakIntent.swift` — `LiveActivityIntent` for the Start-break secondary button on the alarm UI (only if we end up using a secondary button; see Task 4 design note)

**Modify:**
- `project.yml` — bump iOS deployment target 17.0 → 26.0; add `NSAlarmKitUsageDescription` to iOS Info.plist properties
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift` — replace scheduler-based break/done scheduling with alarm-scheduler equivalents; add events-stream observer in init
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift` — add `currentAlarmId: UUID?` field (Codable, optional, backward-compatible)
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift` — no signature change expected, but verify
- `BlinkBreak/BlinkBreakApp.swift` — wire `AlarmKitScheduler` into `SessionController.init` and call `requestAuthorizationIfNeeded()` on app launch
- `BlinkBreak/AppDelegate.swift` — drop UNNotification category registration (alarms aren't notifications)
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift` — rewrite to drive state through `MockAlarmScheduler` events
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift` — same
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleIntegrationTests.swift` — same
- `CLAUDE.md` — note iOS 26 minimum + AlarmKit-based alert delivery
- `docs/superpowers/specs/2026-04-15-alarmkit-migration-design.md` — append "Implementation notes" section if AlarmKit's actual API forced design adjustments

**Delete:**
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift` — `NotificationSchedulerProtocol`, `UNNotificationScheduler`, `MockNotificationScheduler`
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/CascadeBuilder.swift` — no more notification scheduling
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockNotificationScheduler.swift`
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/CascadeBuilderTests.swift` (if exists)
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift` (if exists)

---

## Design Notes

### Action button shape

Two viable approaches for the alarm UI:

**Option A — single Stop button on the break alarm.** Tapping Stop = "I acknowledge the break." Implicit semantics. SessionController observes the alarm transition out of `.alerting` and schedules the 20-second look-away countdown. Simpler: no `LiveActivityIntent` wiring required.

**Option B — Stop + secondary "Start break" button.** Stop = "Stop the session entirely." Start break = "Acknowledge — begin look-away." Requires a `LiveActivityIntent` to handle the secondary button tap. More expressive but more moving parts.

Use **Option A** for v1. The user can fully stop the session by opening the app and tapping Stop in the UI.

### Mapping cycles to AlarmKit IDs

AlarmKit alarms are identified by `UUID`. Generate a fresh `UUID` for each alarm schedule call. Persist the current alarm's UUID in `SessionRecord.currentAlarmId` so reconciliation can correlate.

### Event chain

```
[user taps Start in app]
→ SessionController.start()
→ alarmScheduler.scheduleCountdown(20min, kind: .breakDue)
→ persist record: currentCycleId=A, currentAlarmId=AlarmA
→ state = .running

[20 minutes pass; alarm fires]
→ alarmScheduler emits .fired(alarmId: AlarmA, kind: .breakDue)
→ SessionController handler: state = .breakPending, persist breakActiveStartedAt=now

[user taps Stop on alarm UI]
→ alarmScheduler emits .dismissed(alarmId: AlarmA, kind: .breakDue)
→ SessionController handler:
    - schedule next look-away alarm: alarmScheduler.scheduleCountdown(20sec, kind: .lookAwayDone)
    - persist record: cycleId=A (unchanged), currentAlarmId=AlarmB, breakActiveStartedAt=now
    - state = .breakActive(startedAt: now)

[20 seconds pass; alarm fires]
→ alarmScheduler emits .fired(alarmId: AlarmB, kind: .lookAwayDone)
→ SessionController handler: state = .lookAway-done-pending (transient — see below)

[user taps Stop on look-away alarm]
→ alarmScheduler emits .dismissed(alarmId: AlarmB, kind: .lookAwayDone)
→ SessionController handler:
    - generate new cycleId=B
    - schedule next break alarm: alarmScheduler.scheduleCountdown(20min, kind: .breakDue)
    - persist record: cycleId=B, currentAlarmId=AlarmC, breakActiveStartedAt=nil
    - state = .running
```

### `breakPending` state

The current code already has `breakPending` for when the break notification has fired but the user hasn't acknowledged. AlarmKit's full-screen takeover means this phase is usually very brief, but we keep the state because the user might dismiss the alarm without acknowledging (some platforms allow this — verify on-device).

### Reconciliation on launch

`SessionController.reconcile()` runs at app launch. With AlarmKit:

1. Load `SessionRecord`. If `sessionActive == false`, state = `.idle`, done.
2. Subscribe to `alarmScheduler.events` (the implementation emits an initial snapshot of currently-scheduled alarms via a synthetic event mechanism, OR we add a `func currentAlarms() async -> [(UUID, AlarmKind)]` to the protocol).
3. If a `.breakDue` alarm is scheduled with id = `currentAlarmId` → state = `.running`.
4. If a `.lookAwayDone` alarm is scheduled with id = `currentAlarmId` → state = `.lookAway`.
5. If no alarm is scheduled but `breakActiveStartedAt` is set within the last hour → state = `.breakPending` (alarm fired while app was killed; reschedule).
6. Otherwise → stale; stop the session.

Add a `currentAlarms() async -> [(id: UUID, kind: AlarmKind)]` query method to the protocol for the sync use case.

---

## Task 1: Create branch and bump iOS deployment target

**Files:** `project.yml`

- [ ] **Step 1: Branch from main**

```bash
git checkout main
git pull --ff-only origin main
git checkout -b alarmkit-migration
```

- [ ] **Step 2: Bump iOS deployment target**

In `project.yml`, change `options.deploymentTarget.iOS` from `"17.0"` to `"26.0"`.

- [ ] **Step 3: Add NSAlarmKitUsageDescription to iOS Info.plist**

In `project.yml`, add to `BlinkBreak` target's `info.properties`:

```yaml
        NSAlarmKitUsageDescription: "BlinkBreak schedules alarms to remind you to take 20-second eye-rest breaks every 20 minutes."
```

Mirror the change in `BlinkBreak/Info.plist` directly so the checked-in plist matches.

- [ ] **Step 4: Regenerate Xcode project**

```bash
xcodegen generate
```

Expected: success.

- [ ] **Step 5: Confirm clean build**

```bash
./scripts/build.sh 2>&1 | tail -5
```

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add project.yml BlinkBreak/Info.plist
git commit -m "chore: bump iOS deployment target to 26 + add NSAlarmKitUsageDescription

Prerequisite for the AlarmKit migration. iOS 26 is the minimum that
exposes the AlarmKit framework. NSAlarmKitUsageDescription is the
user-facing string shown when the system prompts for alarm permission.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Define `AlarmSchedulerProtocol` + value types

**Files:** Create `Packages/BlinkBreakCore/Sources/BlinkBreakCore/AlarmScheduler.swift`

- [ ] **Step 1: Write the file**

```swift
//
//  AlarmScheduler.swift
//  BlinkBreakCore
//
//  Protocol abstraction over AlarmKit's AlarmManager. Zero AlarmKit imports
//  here — concrete iOS-target wrapper imports AlarmKit; mock impl for tests
//  publishes events synchronously.
//
//  SessionController depends on this protocol.
//

import Foundation

/// Which beat of the 20-20-20 cycle this alarm represents.
public enum AlarmKind: String, Sendable, Codable {
    /// The 20-minute "look away now" alarm.
    case breakDue
    /// The 20-second "look-away period is over" alarm.
    case lookAwayDone
}

/// Events emitted by the alarm scheduler. Sent on the `events` AsyncStream.
public enum AlarmEvent: Sendable, Equatable {
    /// The alarm fired and is now showing the alert UI to the user.
    case fired(alarmId: UUID, kind: AlarmKind)
    /// The user acknowledged the alarm (tapped Stop) or it was cancelled.
    case dismissed(alarmId: UUID, kind: AlarmKind)
}

/// A snapshot of an alarm currently scheduled with the system.
public struct ScheduledAlarmInfo: Sendable, Equatable {
    public let alarmId: UUID
    public let kind: AlarmKind
    public init(alarmId: UUID, kind: AlarmKind) {
        self.alarmId = alarmId
        self.kind = kind
    }
}

/// Errors the scheduler can raise.
public enum AlarmSchedulerError: Error, Sendable, Equatable {
    case authorizationDenied
    case schedulingFailed(reason: String)
}

/// The narrow surface SessionController needs from AlarmKit.
public protocol AlarmSchedulerProtocol: AnyObject, Sendable {
    /// Request user permission for alarms. Returns `true` if granted (or already granted).
    func requestAuthorizationIfNeeded() async throws -> Bool

    /// Schedule a countdown alarm that fires after `duration` seconds.
    /// Returns the UUID assigned to the new alarm (callers should persist this for cancellation).
    func scheduleCountdown(duration: TimeInterval, kind: AlarmKind) async throws -> UUID

    /// Cancel a specific alarm by ID. Idempotent — cancelling an unknown ID is a no-op.
    func cancel(alarmId: UUID) async

    /// Cancel every alarm this scheduler has scheduled. Used when the session stops.
    func cancelAll() async

    /// Snapshot the currently-scheduled alarms. Used for reconciliation on launch.
    func currentAlarms() async -> [ScheduledAlarmInfo]

    /// AsyncStream of fired/dismissed events. SessionController subscribes once at init.
    var events: AsyncStream<AlarmEvent> { get }
}
```

- [ ] **Step 2: Confirm BlinkBreakCore builds**

```bash
cd Packages/BlinkBreakCore && swift build 2>&1 | tail -3
```

Expected: green.

---

## Task 3: Build the test mock

**Files:** Create `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockAlarmScheduler.swift`

- [ ] **Step 1: Write the mock**

```swift
//
//  MockAlarmScheduler.swift
//  BlinkBreakCoreTests
//
//  Test double for AlarmSchedulerProtocol. Lets tests:
//  - Drive virtual time by calling `simulateFire` and `simulateDismiss`.
//  - Inspect `scheduled` to assert which alarms were created.
//  - Override `nextAssignedId` to make assertions deterministic.
//

import Foundation
@testable import BlinkBreakCore

final class MockAlarmScheduler: AlarmSchedulerProtocol, @unchecked Sendable {

    struct ScheduleCall: Equatable {
        let alarmId: UUID
        let duration: TimeInterval
        let kind: AlarmKind
    }

    private let lock = NSLock()
    private var _scheduled: [ScheduleCall] = []
    private var _cancelled: [UUID] = []
    private var _cancelAllCount: Int = 0
    private var _currentAlarms: [ScheduledAlarmInfo] = []
    private var _stubbedAuthorization: Bool = true

    private let continuation: AsyncStream<AlarmEvent>.Continuation
    let events: AsyncStream<AlarmEvent>

    /// Override the next ID returned from `scheduleCountdown`. Useful when a test needs a
    /// specific UUID it can later assert on.
    var nextAssignedId: UUID?

    init() {
        var cont: AsyncStream<AlarmEvent>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    var scheduled: [ScheduleCall] { lock.lock(); defer { lock.unlock() }; return _scheduled }
    var cancelledIds: [UUID] { lock.lock(); defer { lock.unlock() }; return _cancelled }
    var cancelAllCount: Int { lock.lock(); defer { lock.unlock() }; return _cancelAllCount }

    func stubAuthorization(_ granted: Bool) {
        lock.lock(); defer { lock.unlock() }
        _stubbedAuthorization = granted
    }

    func setCurrentAlarms(_ alarms: [ScheduledAlarmInfo]) {
        lock.lock(); defer { lock.unlock() }
        _currentAlarms = alarms
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        _scheduled.removeAll()
        _cancelled.removeAll()
        _cancelAllCount = 0
        _currentAlarms.removeAll()
    }

    /// Push a `.fired` event onto the stream. Called by tests to simulate the system firing an alarm.
    func simulateFire(alarmId: UUID, kind: AlarmKind) {
        continuation.yield(.fired(alarmId: alarmId, kind: kind))
    }

    /// Push a `.dismissed` event onto the stream. Simulates the user tapping Stop.
    func simulateDismiss(alarmId: UUID, kind: AlarmKind) {
        continuation.yield(.dismissed(alarmId: alarmId, kind: kind))
    }

    // MARK: - AlarmSchedulerProtocol

    func requestAuthorizationIfNeeded() async throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _stubbedAuthorization
    }

    func scheduleCountdown(duration: TimeInterval, kind: AlarmKind) async throws -> UUID {
        lock.lock(); defer { lock.unlock() }
        let id = nextAssignedId ?? UUID()
        nextAssignedId = nil
        _scheduled.append(ScheduleCall(alarmId: id, duration: duration, kind: kind))
        return id
    }

    func cancel(alarmId: UUID) async {
        lock.lock(); defer { lock.unlock() }
        _cancelled.append(alarmId)
    }

    func cancelAll() async {
        lock.lock(); defer { lock.unlock() }
        _cancelAllCount += 1
    }

    func currentAlarms() async -> [ScheduledAlarmInfo] {
        lock.lock(); defer { lock.unlock() }
        return _currentAlarms
    }
}
```

- [ ] **Step 2: Confirm tests still build (no usage yet — just compile check)**

```bash
swift build --target BlinkBreakCoreTests 2>&1 | tail -5
```

Expected: green.

---

## Task 4: Add `currentAlarmId` to `SessionRecord`

**Files:** `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift`

- [ ] **Step 1: Add the field as optional + backward-compatible**

In `SessionRecord`, add:

```swift
public var currentAlarmId: UUID?
```

In the public init, add the parameter with a default of `nil`. In the static `idle` constant, the new field defaults to `nil` automatically. Verify it Codable-decodes from old JSON (omitted field = `nil`) by the existing backward-compat test pattern.

- [ ] **Step 2: Add a backward-compat test**

In `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift`, add:

```swift
@Test("SessionRecord without currentAlarmId decodes cleanly (backward compat)")
func sessionRecordCurrentAlarmIdBackwardCompat() throws {
    let legacyJSON = """
    {"sessionActive":true,"currentCycleId":"550E8400-E29B-41D4-A716-446655440000","cycleStartedAt":1700000000}
    """
    let data = Data(legacyJSON.utf8)
    let record = try JSONDecoder().decode(SessionRecord.self, from: data)
    #expect(record.sessionActive == true)
    #expect(record.currentAlarmId == nil)
}
```

- [ ] **Step 3: Run tests**

```bash
swift test 2>&1 | tail -3
```

Expected: 97 tests pass.

---

## Task 5: Rewire `SessionController` against `AlarmSchedulerProtocol`

**Files:** `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`

This is the largest change. The work:

- Replace the `scheduler: NotificationSchedulerProtocol` parameter with `alarmScheduler: AlarmSchedulerProtocol`.
- Remove `start()`'s `scheduler.cancelAll()` + `scheduler.schedule(CascadeBuilder.buildBreakNotification...)`. Replace with `Task { let id = try await alarmScheduler.scheduleCountdown(duration: BlinkBreakConstants.breakInterval, kind: .breakDue); persist record with currentAlarmId = id }`.
- Same shape for `stop()`, `handleStartBreakAction()`, `reconcileState()`.
- In `init`, start a `Task { for await event in alarmScheduler.events { handleAlarmEvent(event) } }` to consume events.
- New private method `handleAlarmEvent(_ event: AlarmEvent)`:
  - `.fired(_, .breakDue)` → set `breakActiveStartedAt` (no, that happens on dismiss); actually set state = `.breakPending(cycleStartedAt: ...)`
  - `.dismissed(_, .breakDue)` → schedule look-away countdown, transition to `.breakActive`
  - `.fired(_, .lookAwayDone)` → no UI state change; alarm UI is showing
  - `.dismissed(_, .lookAwayDone)` → schedule next break countdown with new cycleId, transition to `.running`

- [ ] **Step 1: Rewrite the file**

This is significant. Below is the complete new shape — copy-paste, then adjust details inline.

```swift
//
//  SessionController.swift
//  BlinkBreakCore
//
//  The brain of BlinkBreak. Owns the state machine, coordinates the alarm
//  scheduler and persistence, and publishes state changes to observing SwiftUI views.
//
//  Cycle chaining is event-driven: the alarm scheduler emits .fired and .dismissed
//  events as the system delivers alarms and the user acknowledges them. We subscribe
//  in init and react.
//

import Foundation
import Combine

@MainActor
public final class SessionController: ObservableObject, SessionControllerProtocol {

    @Published public private(set) var state: SessionState = .idle
    @Published public private(set) var weeklySchedule: WeeklySchedule = .empty

    private let alarmScheduler: AlarmSchedulerProtocol
    private let persistence: PersistenceProtocol
    private let clock: @Sendable () -> Date
    private let scheduleEvaluator: ScheduleEvaluatorProtocol
    private let calendar: Calendar

    private var eventTask: Task<Void, Never>?

    public init(
        alarmScheduler: AlarmSchedulerProtocol,
        persistence: PersistenceProtocol,
        scheduleEvaluator: ScheduleEvaluatorProtocol = NoopScheduleEvaluator(),
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.alarmScheduler = alarmScheduler
        self.persistence = persistence
        self.scheduleEvaluator = scheduleEvaluator
        self.calendar = calendar
        self.clock = clock
        self.weeklySchedule = persistence.loadSchedule() ?? .empty

        // Consume events on the main actor.
        let stream = alarmScheduler.events
        self.eventTask = Task { @MainActor [weak self] in
            for await event in stream {
                self?.handleAlarmEvent(event)
            }
        }
    }

    deinit {
        eventTask?.cancel()
    }

    public func start() {
        startSession(wasAutoStarted: false)
    }

    private func startSession(wasAutoStarted: Bool = false) {
        Task {
            await alarmScheduler.cancelAll()

            let cycleId = UUID()
            let cycleStartedAt = clock()

            // Schedule the break alarm. Capture its assigned ID for cancellation.
            let alarmId: UUID
            do {
                alarmId = try await alarmScheduler.scheduleCountdown(
                    duration: BlinkBreakConstants.breakInterval,
                    kind: .breakDue
                )
            } catch {
                // Authorization not granted, etc. Stay idle.
                return
            }

            let record = SessionRecord(
                sessionActive: true,
                currentCycleId: cycleId,
                cycleStartedAt: cycleStartedAt,
                breakActiveStartedAt: nil,
                lastUpdatedAt: cycleStartedAt,
                wasAutoStarted: wasAutoStarted ? true : nil,
                currentAlarmId: alarmId
            )
            persistence.save(record)
            state = .running(cycleStartedAt: cycleStartedAt)
        }
    }

    public func stop() {
        Task {
            await alarmScheduler.cancelAll()
            let now = clock()
            var idleRecord = SessionRecord.idle
            idleRecord.lastUpdatedAt = now
            if scheduleEvaluator.shouldBeActive(at: now, manualStopDate: nil, calendar: calendar) {
                idleRecord.manualStopDate = now
            }
            persistence.save(idleRecord)
            state = .idle
        }
    }

    public func updateSchedule(_ schedule: WeeklySchedule) {
        persistence.saveSchedule(schedule)
        weeklySchedule = schedule
    }

    /// Public hook for "user pressed Start break inside the app" (BreakPendingView).
    public func acknowledgeCurrentBreak() {
        guard let alarmId = persistence.load().currentAlarmId else { return }
        // Synthesize a dismissed event — equivalent to the user tapping Stop on the alarm.
        Task {
            await alarmScheduler.cancel(alarmId: alarmId)
            handleAlarmEvent(.dismissed(alarmId: alarmId, kind: .breakDue))
        }
    }

    /// Legacy entry point retained for AppDelegate's notification-action callback path,
    /// even though we no longer schedule notifications. Notification taps from prior
    /// installations should still safely no-op.
    public func handleStartBreakAction(cycleId: UUID) {
        // No-op; kept for source compatibility. AlarmKit handles all break-acknowledgment now.
    }

    public func reconcile() async {
        await reconcileState()
        evaluateSchedule()
    }

    private func reconcileState() async {
        let record = persistence.load()
        let now = clock()

        guard record.sessionActive else {
            state = .idle
            return
        }

        guard let currentCycleId = record.currentCycleId,
              let cycleStartedAt = record.cycleStartedAt else {
            persistence.save(.idle)
            state = .idle
            return
        }

        // What's actually scheduled in the system right now?
        let scheduled = await alarmScheduler.currentAlarms()
        let activeAlarm = record.currentAlarmId.flatMap { id in
            scheduled.first(where: { $0.alarmId == id })
        }

        if let alarm = activeAlarm {
            switch alarm.kind {
            case .breakDue:
                state = .running(cycleStartedAt: cycleStartedAt)
            case .lookAwayDone:
                if let breakActiveStartedAt = record.breakActiveStartedAt {
                    state = .lookAway(startedAt: breakActiveStartedAt)
                } else {
                    state = .running(cycleStartedAt: cycleStartedAt)
                }
            }
            return
        }

        // No alarm scheduled. Check if we're mid-break (alarm fired while killed).
        if let breakActiveStartedAt = record.breakActiveStartedAt,
           now.timeIntervalSince(breakActiveStartedAt) < BlinkBreakConstants.lookAwayDuration * 2 {
            state = .breakActive(startedAt: breakActiveStartedAt)
            return
        }

        // Stale state — stop the session.
        var idleRecord = SessionRecord.idle
        idleRecord.lastUpdatedAt = now
        persistence.save(idleRecord)
        state = .idle
    }

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

    private func handleAlarmEvent(_ event: AlarmEvent) {
        switch event {
        case let .fired(_, kind):
            handleFired(kind: kind)
        case let .dismissed(alarmId, kind):
            handleDismissed(alarmId: alarmId, kind: kind)
        }
    }

    private func handleFired(kind: AlarmKind) {
        let record = persistence.load()
        guard record.sessionActive,
              let cycleStartedAt = record.cycleStartedAt else { return }
        switch kind {
        case .breakDue:
            // Break alarm is showing the alert UI. State is breakPending until user acknowledges.
            state = .breakPending(cycleStartedAt: cycleStartedAt)
        case .lookAwayDone:
            // Look-away alarm is showing the alert UI. State stays lookAway until user
            // dismisses, at which point we roll the cycle.
            break
        }
    }

    private func handleDismissed(alarmId: UUID, kind: AlarmKind) {
        let record = persistence.load()
        guard record.sessionActive,
              record.currentAlarmId == alarmId,
              let currentCycleId = record.currentCycleId,
              let cycleStartedAt = record.cycleStartedAt else { return }

        switch kind {
        case .breakDue:
            // User acknowledged the break. Schedule the look-away countdown.
            Task {
                let breakActiveStartedAt = clock()
                let lookAwayAlarmId: UUID
                do {
                    lookAwayAlarmId = try await alarmScheduler.scheduleCountdown(
                        duration: BlinkBreakConstants.lookAwayDuration,
                        kind: .lookAwayDone
                    )
                } catch {
                    // Authorization revoked? Stop session.
                    stop()
                    return
                }

                var newRecord = record
                newRecord.breakActiveStartedAt = breakActiveStartedAt
                newRecord.lastUpdatedAt = clock()
                newRecord.currentAlarmId = lookAwayAlarmId
                persistence.save(newRecord)
                state = .breakActive(startedAt: breakActiveStartedAt)
            }
        case .lookAwayDone:
            // Look-away period over. Roll to next cycle and schedule the next break alarm.
            Task {
                let nextCycleId = UUID()
                let nextCycleStartedAt = clock()
                let nextAlarmId: UUID
                do {
                    nextAlarmId = try await alarmScheduler.scheduleCountdown(
                        duration: BlinkBreakConstants.breakInterval,
                        kind: .breakDue
                    )
                } catch {
                    stop()
                    return
                }
                let newRecord = SessionRecord(
                    sessionActive: true,
                    currentCycleId: nextCycleId,
                    cycleStartedAt: nextCycleStartedAt,
                    breakActiveStartedAt: nil,
                    lastUpdatedAt: nextCycleStartedAt,
                    wasAutoStarted: record.wasAutoStarted,
                    currentAlarmId: nextAlarmId
                )
                persistence.save(newRecord)
                state = .running(cycleStartedAt: nextCycleStartedAt)
            }
        }
    }
}
```

- [ ] **Step 2: Verify Sources compile**

```bash
swift build 2>&1 | grep -E "error:" | grep -v Tests | head
```

Expected: zero errors from `Sources/`.

---

## Task 6: Update tests to use `MockAlarmScheduler`

**Files:**
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift`
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift`
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleIntegrationTests.swift`

- [ ] **Step 1: Replace fixtures**

In each file, replace:
```swift
let scheduler = MockNotificationScheduler()
```
with:
```swift
let alarmScheduler = MockAlarmScheduler()
```

Replace each `SessionController(scheduler: scheduler, persistence: persistence, ...)` with `SessionController(alarmScheduler: alarmScheduler, persistence: persistence, ...)`.

- [ ] **Step 2: Rewrite assertions**

For each test that previously asserted on `scheduler.scheduledNotifications`, rewrite to assert on `alarmScheduler.scheduled` (the array of `ScheduleCall` records).

For tests that previously called `f.advance(by: BlinkBreakConstants.breakInterval); await f.controller.reconcile()` to simulate the break time arriving, instead push an event:

```swift
let alarmId = f.alarmScheduler.scheduled.last!.alarmId
f.alarmScheduler.simulateFire(alarmId: alarmId, kind: .breakDue)
try await Task.sleep(for: .milliseconds(10))  // let the event handler run
```

- [ ] **Step 3: Run tests**

```bash
swift test 2>&1 | tail -5
```

Expected: green.

---

## Task 7: Delete the obsolete notification scheduler

**Files:**
- Delete: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift`
- Delete: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/CascadeBuilder.swift`
- Delete: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockNotificationScheduler.swift`
- Delete: any test files that exclusively cover the deleted code

- [ ] **Step 1: Delete files**

```bash
git rm Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift
git rm Packages/BlinkBreakCore/Sources/BlinkBreakCore/CascadeBuilder.swift
git rm Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockNotificationScheduler.swift
```

Identify and delete any other test file that only tested NotificationScheduler / CascadeBuilder.

- [ ] **Step 2: Update DiagnosticCollector to drop the scheduler dependency**

`DiagnosticCollector.collect` calls `scheduler.pendingRequests()`. With UNNotificationScheduler gone, pending notifications are no longer relevant. Remove the `scheduler` parameter and the `pendingNotifications` field from the report. Update tests + bug-report rendering accordingly.

- [ ] **Step 3: Run tests**

```bash
swift test 2>&1 | tail -3
```

Expected: green.

---

## Task 8: Implement `AlarmKitScheduler` in the iOS target

**Files:** Create `BlinkBreak/AlarmKitScheduler.swift`

- [ ] **Step 1: Write the iOS-side wrapper**

```swift
//
//  AlarmKitScheduler.swift
//  BlinkBreak
//
//  Concrete `AlarmSchedulerProtocol` implementation backed by AlarmKit's
//  `AlarmManager.shared`. iOS 26+ only.
//

import Foundation
import AlarmKit
import SwiftUI
@preconcurrency import BlinkBreakCore

@available(iOS 26.0, *)
public final class AlarmKitScheduler: AlarmSchedulerProtocol, @unchecked Sendable {

    /// Marker metadata; AlarmKit requires a Metadata generic parameter even when unused.
    public struct Metadata: AlarmMetadata {
        public init() {}
    }

    private let lock = NSLock()
    private var idToKind: [UUID: AlarmKind] = [:]

    public let events: AsyncStream<AlarmEvent>
    private let eventContinuation: AsyncStream<AlarmEvent>.Continuation
    private var observerTask: Task<Void, Never>?

    public init() {
        var cont: AsyncStream<AlarmEvent>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.eventContinuation = cont

        // Watch alarm updates and translate to our event vocabulary.
        observerTask = Task { [weak self] in
            var lastAlerting: Set<UUID> = []
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                let nowAlerting = Set(alarms.filter { $0.state == .alerting }.map { $0.id })
                let known = self.snapshotMapping()
                // Newly alerting → fired
                for id in nowAlerting.subtracting(lastAlerting) {
                    if let kind = known[id] {
                        self.eventContinuation.yield(.fired(alarmId: id, kind: kind))
                    }
                }
                // No longer alerting → dismissed
                let presentIds = Set(alarms.map(\.id))
                for id in lastAlerting where !nowAlerting.contains(id) || !presentIds.contains(id) {
                    if let kind = known[id] {
                        self.eventContinuation.yield(.dismissed(alarmId: id, kind: kind))
                        self.forgetMapping(id: id)
                    }
                }
                lastAlerting = nowAlerting
            }
        }
    }

    deinit {
        observerTask?.cancel()
        eventContinuation.finish()
    }

    private func snapshotMapping() -> [UUID: AlarmKind] {
        lock.lock(); defer { lock.unlock() }
        return idToKind
    }

    private func rememberMapping(id: UUID, kind: AlarmKind) {
        lock.lock(); defer { lock.unlock() }
        idToKind[id] = kind
    }

    private func forgetMapping(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        idToKind.removeValue(forKey: id)
    }

    // MARK: - AlarmSchedulerProtocol

    public func requestAuthorizationIfNeeded() async throws -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let state = try await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        @unknown default:
            return false
        }
    }

    public func scheduleCountdown(duration: TimeInterval, kind: AlarmKind) async throws -> UUID {
        let id = UUID()
        let stopButton = AlarmButton(
            text: kind == .breakDue ? "Start break" : "Done",
            textColor: .white,
            systemImageName: kind == .breakDue ? "eye" : "checkmark"
        )
        let alert = AlarmPresentation.Alert(
            title: kind == .breakDue ? "Time to look away" : "Look-away complete",
            stopButton: stopButton
        )
        let attributes = AlarmAttributes<Metadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .blue
        )
        let configuration = AlarmManager.AlarmConfiguration<Metadata>.timer(
            duration: duration,
            attributes: attributes
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        } catch {
            throw AlarmSchedulerError.schedulingFailed(reason: String(describing: error))
        }
        rememberMapping(id: id, kind: kind)
        return id
    }

    public func cancel(alarmId: UUID) async {
        do {
            try AlarmManager.shared.cancel(id: alarmId)
        } catch {
            // Cancelling a non-existent alarm is fine — the user may have already dismissed it.
        }
        forgetMapping(id: alarmId)
    }

    public func cancelAll() async {
        let mapping = snapshotMapping()
        for id in mapping.keys {
            await cancel(alarmId: id)
        }
    }

    public func currentAlarms() async -> [ScheduledAlarmInfo] {
        let mapping = snapshotMapping()
        return mapping.map { ScheduledAlarmInfo(alarmId: $0.key, kind: $0.value) }
    }
}
```

> **Implementation note:** AlarmKit's exact API surface (e.g., `AlarmConfiguration` factory method names, `AlarmAttributes` initializer arguments, `AlarmPresentation.Alert`'s exact init) may differ slightly from what's written above based on the actual iOS 26 SDK. Adjust the wrapper to match what the SDK exposes. The protocol on the `BlinkBreakCore` side is the contract; the iOS wrapper bridges to whatever AlarmKit actually provides.

- [ ] **Step 2: Build iOS app**

```bash
xcodebuild build -project BlinkBreak.xcodeproj -scheme BlinkBreak -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -10
```

Expected: green. If AlarmKit API call sites don't match the SDK, fix them — the protocol layer doesn't change, only the wrapper.

---

## Task 9: Wire it all up in `BlinkBreakApp.swift`

**Files:** `BlinkBreak/BlinkBreakApp.swift`

- [ ] **Step 1: Replace scheduler construction**

Change the `SessionController` initializer call to pass `alarmScheduler: AlarmKitScheduler()` instead of `scheduler: sharedScheduler`.

- [ ] **Step 2: Drop the `sharedScheduler` static + `registerCategories()` call**

`UNNotificationScheduler` is gone. Remove the `private static let sharedScheduler = UNNotificationScheduler()` line and its `.registerCategories()` call.

- [ ] **Step 3: Request alarm permission on launch**

In `.onAppear`, add (after `appDelegate.requestNotificationAuthorizationIfNeeded()`):

```swift
Task {
    _ = try? await alarmScheduler.requestAuthorizationIfNeeded()
}
```

(Hold a reference to the alarm scheduler in the App struct so this works.)

- [ ] **Step 4: Build**

```bash
./scripts/build.sh 2>&1 | tail -5
```

Expected: green.

---

## Task 10: Update `AppDelegate.swift`

**Files:** `BlinkBreak/AppDelegate.swift`

- [ ] **Step 1: Drop UN category registration and notification action handling**

Remove the `registerCategories` call (lives on the deleted scheduler) and the `userNotificationCenter(_:didReceive:withCompletionHandler:)` action handler. The `requestNotificationAuthorizationIfNeeded` method also goes — alarm permission is the relevant thing now.

- [ ] **Step 2: Keep BGTaskScheduler registration if present**

The weekly-schedule auto-start/stop relies on background task scheduling. Leave that in place.

- [ ] **Step 3: Build**

```bash
./scripts/build.sh 2>&1 | tail -5
```

Expected: green.

---

## Task 11: Update `CLAUDE.md` and the spec doc

**Files:**
- `CLAUDE.md`
- `docs/superpowers/specs/2026-04-15-alarmkit-migration-design.md`

- [ ] **Step 1: Update CLAUDE.md**

Change "iOS 17+" to "iOS 26+". Update the architecture section to mention AlarmKit instead of UNNotification. Update the test count reference to whatever the new green test count is.

- [ ] **Step 2: Append "Implementation notes" to the spec**

Add a section at the bottom of the design spec describing any deviations from the planned shape that surfaced during implementation (e.g., if AlarmKit's `AlarmConfiguration` had a different name; if `currentAlarms()` had to be implemented entirely client-side because AlarmKit had no equivalent).

---

## Task 12: Verify the full suite

- [ ] **Step 1: Unit tests** — `./scripts/test.sh` → green
- [ ] **Step 2: Lint** — `./scripts/lint.sh` → no new violations
- [ ] **Step 3: Build** — `./scripts/build.sh` → green
- [ ] **Step 4: Integration tests** — `./scripts/test-integration.sh` → green (these use real iOS simulator with fast-mode env vars; they should pass if the state machine is correct, regardless of whether AlarmKit's full-screen UI actually renders in simulator)

If integration tests fail because they assert on UNNotification banner UI that no longer exists, simplify the assertions to focus on state transitions visible in the app's own SwiftUI views.

---

## Task 13: Commit + push + open PR + ship-it

- [ ] **Step 1: Commit**

```bash
git add -A
git commit -m "feat: migrate from UNNotification to AlarmKit for break alerts

PR 2 of the AlarmKit migration. ..."
```

- [ ] **Step 2: Push and open PR**

```bash
git push -u origin alarmkit-migration
gh pr create --title "feat: migrate to AlarmKit (PR 2 of AlarmKit migration)" --body "..."
```

- [ ] **Step 3: Trigger Claude review + poll for both bots**

```bash
gh pr comment <num> --body "@claude do a code review"
```

- [ ] **Step 4: Address feedback rigorously, push fixes**

- [ ] **Step 5: Verify CI green and merge**

```bash
gh pr checks <num>
gh pr merge <num> --squash --delete-branch
```

- [ ] **Step 6: Watch deploy**

```bash
gh run watch <deploy-run-id> --exit-status
```

Expected: build XX uploaded to TestFlight successfully.

---

## Self-Review Notes

- **Spec coverage:** All design-spec PR 2 items covered (deployment-target bump, NSAlarmKitUsageDescription, protocol+impl, SessionController rewire, test rewrites, CLAUDE.md update). ✓
- **Placeholder scan:** Task 13 PR body is placeholder `"..."` — written at PR-creation time. AlarmKit-specific call sites in `AlarmKitScheduler.swift` are best-effort based on research, not verified against the SDK; flagged with an inline implementation note.
- **Type consistency:** `alarmId` (UUID), `cycleId` (UUID), `kind` (AlarmKind), `currentAlarmId` (Optional<UUID>) — naming consistent across all tasks.
- **Risk:** AlarmKit API may differ from this plan's signatures. The protocol layer in `BlinkBreakCore` is fixed; the iOS-target wrapper adapts to whatever the real AlarmKit exposes. Treat task 8 as "match the real SDK" rather than "copy this code verbatim."
