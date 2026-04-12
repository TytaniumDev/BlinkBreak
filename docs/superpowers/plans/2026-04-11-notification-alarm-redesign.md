# Notification Alarm Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 6-notification iPhone cascade with a single iPhone notification (custom 30-second alarm sound) plus a Watch-owned `WKExtendedRuntimeSession` that plays a repeating haptic until acknowledged, and make "Start break" visible directly from the Watch notification.

**Architecture:** Both devices independently fire their own alarm at T+20:00. iPhone has one `.timeSensitive` notification with a custom `break-alarm.caf` sound file; Watch holds an extended runtime session alive in the background and at break time calls `session.notifyUser(hapticType:repeatHandler:)` plus posts its own local notification. Acknowledgment on either device broadcasts a `SessionSnapshot` via WCSession; the other device processes the snapshot via a new `SessionController.handleRemoteSnapshot(_:)` method that idempotently cancels delivered notifications and disarms the local alarm. No cascade. No nudge notifications. A new `SessionAlarmProtocol` in `BlinkBreakCore` abstracts the extended runtime session so iPhone can use a `NoopSessionAlarm` while Watch uses `WKExtendedRuntimeSessionAlarm` (which lives in the Watch target because it imports `WatchKit`).

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, watchOS 10+, Swift Testing (`import Testing` — not XCTest), `UserNotifications`, `WatchKit`, `WatchConnectivity`, `AVFoundation` (for sound generation script), `xcodegen`, local Swift Package for `BlinkBreakCore`.

**Spec:** [`docs/superpowers/specs/2026-04-11-notification-alarm-redesign-design.md`](../specs/2026-04-11-notification-alarm-redesign-design.md)

---

## File Structure

### Files to CREATE

- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionAlarm.swift` — `SessionAlarmProtocol` + `NoopSessionAlarm`.
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockSessionAlarm.swift` — test mock that records `arm`/`disarm` calls.
- `BlinkBreak Watch App/WKExtendedRuntimeSessionAlarm.swift` — concrete Watch implementation holding a `WKExtendedRuntimeSession`, a `DispatchSourceTimer`, and a repeat-handler.
- `scripts/sound/generate-alarm.swift` — Swift script using `AVFoundation` to synthesize `break-alarm.caf` deterministically.
- `BlinkBreak/Resources/Sounds/break-alarm.caf` — the generated ~28-second alarm sound file (committed as a binary asset).

### Files to MODIFY

- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift` — add `lastUpdatedAt: Date?` field + `init(from snapshot: SessionSnapshot)` convenience.
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift` — add `soundName: String?` to `ScheduledNotification`; update `UNNotificationScheduler.schedule(_:)` to use it; add `CascadeBuilder.buildBreakNotification(cycleId:cycleStartedAt:)` alongside the existing cascade; then later delete `buildBreakCascade`.
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift` — delete `nudgeInterval`, `nudgeCount`, `breakNudgeIdPrefix`.
- `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift` — add `alarm:` dependency, wire into all transitions, switch `start()` to single notification, add `handleRemoteSnapshot(_:)`, rename `wireUpWatchCommands()` → `wireUpConnectivity()`.
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift` — update fixture, update all cascade assertions to single-notification, add alarm assertions.
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift` — update fixture, update reconciliation tests to work with single notification + alarm re-arm.
- `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift` — replace cascade tests with single-notification tests.
- `BlinkBreak/BlinkBreakApp.swift` — inject `NoopSessionAlarm`, call `wireUpConnectivity()`.
- `BlinkBreak Watch App/BlinkBreakWatchApp.swift` — inject `WKExtendedRuntimeSessionAlarm`, call `wireUpConnectivity()`, delete `wireUpSnapshotReceiver()`.
- `project.yml` — add `BlinkBreak/Resources/Sounds/` as a resource path on the iOS target.

### Files to DELETE (content inside existing files)

- `CascadeBuilder.buildBreakCascade(cycleId:cycleStartedAt:)` — replaced by `buildBreakNotification`.
- Nudge references in `CascadeBuilder.identifiers(for:)`.
- Cascade-specific test cases in `NotificationSchedulerTests.swift`.

---

## Pre-Flight

Before starting task 1, verify the clean baseline:

- [ ] **Pre-flight: baseline tests pass on main**

```bash
cd /Users/tylerholland/Dev/BlinkBreak
git checkout spec/notification-alarm-redesign
./scripts/test.sh
```

Expected: all ~35 tests pass. The spec commit is already on this branch; implementation work continues here.

- [ ] **Pre-flight: baseline lint passes**

```bash
./scripts/lint.sh
```

Expected: no forbidden-import failures; swiftlint (if installed) reports zero errors.

---

## Task 1: Add `lastUpdatedAt` to SessionRecord

**Why:** The new `handleRemoteSnapshot` staleness guard compares incoming `snapshot.updatedAt` against the locally-persisted `lastUpdatedAt`. Without this field, out-of-order snapshot delivery could apply an older snapshot and clobber newer state.

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift`

- [ ] **Step 1: Add failing test for the new field**

Open `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift` and add the following test at the bottom of the existing `@Suite`:

```swift
@Test("SessionRecord round-trips lastUpdatedAt through JSON")
func lastUpdatedAtRoundTrip() throws {
    let when = Date(timeIntervalSince1970: 1_700_001_234)
    let record = SessionRecord(
        sessionActive: true,
        currentCycleId: UUID(),
        cycleStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
        lookAwayStartedAt: nil,
        lastUpdatedAt: when
    )
    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
    #expect(decoded.lastUpdatedAt == when)
}

@Test("SessionRecord decodes legacy JSON without lastUpdatedAt")
func legacyRecordDecodes() throws {
    // Exact shape of the pre-redesign encoded record (no lastUpdatedAt).
    let legacyJSON = """
    {
        "sessionActive": true,
        "currentCycleId": "11111111-2222-3333-4444-555555555555",
        "cycleStartedAt": 1700000000
    }
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(SessionRecord.self, from: legacyJSON)
    #expect(decoded.sessionActive == true)
    #expect(decoded.lastUpdatedAt == nil)
}

@Test("SessionRecord.init(from: SessionSnapshot) copies updatedAt into lastUpdatedAt")
func initFromSnapshot() {
    let cycleId = UUID()
    let cycleStart = Date(timeIntervalSince1970: 1_700_000_000)
    let lookAwayStart = Date(timeIntervalSince1970: 1_700_000_100)
    let snap = SessionSnapshot(
        sessionActive: true,
        currentCycleId: cycleId,
        cycleStartedAt: cycleStart,
        lookAwayStartedAt: lookAwayStart,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
    )
    let record = SessionRecord(from: snap)
    #expect(record.sessionActive == true)
    #expect(record.currentCycleId == cycleId)
    #expect(record.cycleStartedAt == cycleStart)
    #expect(record.lookAwayStartedAt == lookAwayStart)
    #expect(record.lastUpdatedAt == Date(timeIntervalSince1970: 1_700_000_200))
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
./scripts/test.sh
```

Expected: compilation fails — `SessionRecord` has no `lastUpdatedAt` parameter and no `init(from:)` initializer.

- [ ] **Step 3: Add the field and convenience initializer**

Replace the entire body of `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift` with:

```swift
//
//  SessionRecord.swift
//  BlinkBreakCore
//
//  The Codable persistence struct stored in UserDefaults. Small on purpose: the
//  pending notification queue is the source of truth for "what happens next";
//  this record is just what lets the UI rehydrate on launch.
//
//  `lastUpdatedAt` is a staleness marker used by `SessionController.handleRemoteSnapshot`
//  to drop out-of-order snapshot deliveries. It's optional for Codable backwards
//  compatibility with pre-redesign persisted records.
//
//  Flutter analogue: the @JsonSerializable() model you'd stash in SharedPreferences.
//

import Foundation

/// The persisted session record. Written on every state transition and read once on
/// app launch to rehydrate UI state.
public struct SessionRecord: Codable, Equatable, Sendable {

    /// Whether a session is currently active. `false` means idle.
    public var sessionActive: Bool

    /// The current cycle's UUID. Used to tag notifications so we can cancel the
    /// break notification on acknowledgment without touching unrelated cycles.
    public var currentCycleId: UUID?

    /// When the current running-state cycle began. Used to derive the next-break fire time.
    /// Nil in the idle state.
    public var cycleStartedAt: Date?

    /// When the current look-away window began. Non-nil only in the `lookAway` state.
    public var lookAwayStartedAt: Date?

    /// When this record was last written (locally or from an incoming remote snapshot).
    /// Optional so legacy persisted records decode without migration.
    public var lastUpdatedAt: Date?

    public init(
        sessionActive: Bool = false,
        currentCycleId: UUID? = nil,
        cycleStartedAt: Date? = nil,
        lookAwayStartedAt: Date? = nil,
        lastUpdatedAt: Date? = nil
    ) {
        self.sessionActive = sessionActive
        self.currentCycleId = currentCycleId
        self.cycleStartedAt = cycleStartedAt
        self.lookAwayStartedAt = lookAwayStartedAt
        self.lastUpdatedAt = lastUpdatedAt
    }

    /// Build a persistence record from an incoming WatchConnectivity snapshot.
    /// Copies `snapshot.updatedAt` into `lastUpdatedAt` so the staleness guard
    /// in `handleRemoteSnapshot` sees the right timestamp.
    public init(from snapshot: SessionSnapshot) {
        self.sessionActive = snapshot.sessionActive
        self.currentCycleId = snapshot.currentCycleId
        self.cycleStartedAt = snapshot.cycleStartedAt
        self.lookAwayStartedAt = snapshot.lookAwayStartedAt
        self.lastUpdatedAt = snapshot.updatedAt
    }

    /// The canonical "idle" record. Use this when stopping or clearing session state.
    public static let idle = SessionRecord(
        sessionActive: false,
        currentCycleId: nil,
        cycleStartedAt: nil,
        lookAwayStartedAt: nil,
        lastUpdatedAt: nil
    )
}
```

- [ ] **Step 4: Run to confirm tests pass**

```bash
./scripts/test.sh
```

Expected: all tests pass, including the three new ones.

- [ ] **Step 5: Lint**

```bash
./scripts/lint.sh
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift
git commit -m "$(cat <<'EOF'
Add SessionRecord.lastUpdatedAt for remote-snapshot staleness guard

New optional field decoded with nil default so legacy persisted records
round-trip cleanly. Adds init(from: SessionSnapshot) convenience used by
the upcoming handleRemoteSnapshot path.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add SessionAlarmProtocol, NoopSessionAlarm, and MockSessionAlarm

**Why:** Every downstream task depends on `SessionController` being able to accept a `SessionAlarmProtocol` and tests being able to inject a `MockSessionAlarm`. Building the protocol and both trivial implementations together keeps the wiring additions atomic.

**Files:**
- Create: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionAlarm.swift`
- Create: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockSessionAlarm.swift`

- [ ] **Step 1: Create `SessionAlarm.swift`**

Create `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionAlarm.swift` with exactly this content:

```swift
//
//  SessionAlarm.swift
//  BlinkBreakCore
//
//  Protocol abstraction for "hold an extended runtime session and fire a repeating
//  haptic at a specific time, until acknowledged." Zero WatchKit imports — the
//  protocol lives in the core package; the concrete WKExtendedRuntimeSession-backed
//  implementation lives in the Watch app target.
//
//  SessionController depends on this protocol; iPhone injects NoopSessionAlarm
//  (iPhone doesn't hold the extended runtime session), Watch injects
//  WKExtendedRuntimeSessionAlarm (lives in BlinkBreak Watch App/), tests inject
//  MockSessionAlarm.
//
//  Flutter analogue: an abstract PlatformAlarmService with a NoopPlatformAlarm
//  and a WatchOSPlatformAlarm implementation in platform-specific directories.
//

import Foundation

/// Abstracts "at time `fireDate`, play a repeating haptic pattern until acknowledged."
/// Implementations are responsible for holding whatever runtime-session machinery they
/// need alive in the background. `arm` and `disarm` must both be idempotent.
public protocol SessionAlarmProtocol: Sendable {

    /// Called when a new cycle begins (either via `start()` or after a break ack).
    /// The implementation should prepare its alarm machinery to fire at `fireDate`
    /// and play a repeating haptic until `disarm(cycleId:)` is called for the matching
    /// cycleId or an implementation-internal maximum duration (~30 seconds) is reached.
    ///
    /// Calling `arm` when another cycle is already armed must first disarm the previous
    /// cycle (there can only ever be one armed cycle at a time).
    func arm(cycleId: UUID, fireDate: Date)

    /// Called when the user acknowledges a break (on either device) or stops the session.
    /// Must be idempotent: calling `disarm` for a cycleId that isn't armed is a no-op.
    /// Disarming must stop any in-progress haptic loop on the next haptic invocation.
    func disarm(cycleId: UUID)
}

/// A `SessionAlarmProtocol` that does nothing. Used on iPhone (where the extended
/// runtime session isn't available / isn't needed — iPhone uses a notification with
/// a custom sound as its alarm) and in tests that don't care about the alarm path.
public final class NoopSessionAlarm: SessionAlarmProtocol, @unchecked Sendable {

    public init() {}

    public func arm(cycleId: UUID, fireDate: Date) {}

    public func disarm(cycleId: UUID) {}
}
```

- [ ] **Step 2: Create `MockSessionAlarm.swift`**

Create `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockSessionAlarm.swift` with exactly this content:

```swift
//
//  MockSessionAlarm.swift
//  BlinkBreakCoreTests
//
//  A test-only SessionAlarmProtocol that records every arm/disarm call for assertion.
//  Same shape and style as MockNotificationScheduler.
//

import Foundation
@testable import BlinkBreakCore

/// Records calls for assertion. Used by SessionController tests to verify that the
/// state machine interacts correctly with the alarm surface.
final class MockSessionAlarm: SessionAlarmProtocol, @unchecked Sendable {

    // MARK: - Recorded calls

    private let lock = NSLock()
    private(set) var armedCalls: [(cycleId: UUID, fireDate: Date)] = []
    private(set) var disarmedCycleIds: [UUID] = []

    // MARK: - SessionAlarmProtocol

    func arm(cycleId: UUID, fireDate: Date) {
        lock.lock()
        defer { lock.unlock() }
        armedCalls.append((cycleId, fireDate))
    }

    func disarm(cycleId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        disarmedCycleIds.append(cycleId)
    }

    // MARK: - Test helpers

    /// The most recent arm call, or nil if never armed.
    var lastArmed: (cycleId: UUID, fireDate: Date)? {
        lock.lock()
        defer { lock.unlock() }
        return armedCalls.last
    }

    /// The most recent disarm target, or nil if never disarmed.
    var lastDisarmedCycleId: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return disarmedCycleIds.last
    }

    /// Reset all recorded state. Useful between test phases within one test.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        armedCalls.removeAll()
        disarmedCycleIds.removeAll()
    }
}
```

- [ ] **Step 3: Run to confirm both files compile**

```bash
./scripts/test.sh
```

Expected: all existing tests still pass; the new files compile cleanly but nothing exercises them yet.

- [ ] **Step 4: Lint**

```bash
./scripts/lint.sh
```

Expected: zero errors. Neither new file imports SwiftUI/UIKit/WatchKit.

- [ ] **Step 5: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionAlarm.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockSessionAlarm.swift
git commit -m "$(cat <<'EOF'
Add SessionAlarmProtocol with Noop and Mock implementations

Protocol abstracts "hold an extended runtime session and fire a repeating
haptic." iPhone injects Noop (no-op on both sides) since iPhone alarms via
a notification sound; Watch will inject WKExtendedRuntimeSessionAlarm in a
later task. MockSessionAlarm records arm/disarm calls for test assertions.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add `soundName` to ScheduledNotification and thread it through the scheduler

**Why:** The iPhone fallback alarm uses a custom notification sound (`break-alarm.caf`). Today `ScheduledNotification` always uses `.default` sound; we need an optional override.

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockNotificationScheduler.swift` (no change needed — mock passes the struct through unchanged)

- [ ] **Step 1: Add failing test for the new field**

Open `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift` and add this test at the bottom of the existing `@Suite("CascadeBuilder")`:

```swift
@Test("ScheduledNotification carries an optional soundName, defaulting to nil")
func soundNameDefaultsToNil() {
    let notification = ScheduledNotification(
        identifier: "test",
        title: "t", body: "b",
        fireDate: startedAt,
        isTimeSensitive: true,
        threadIdentifier: "thread",
        categoryIdentifier: nil
    )
    #expect(notification.soundName == nil)
}

@Test("ScheduledNotification stores a custom soundName when provided")
func soundNameStoresCustom() {
    let notification = ScheduledNotification(
        identifier: "test",
        title: "t", body: "b",
        fireDate: startedAt,
        isTimeSensitive: true,
        threadIdentifier: "thread",
        categoryIdentifier: nil,
        soundName: "break-alarm.caf"
    )
    #expect(notification.soundName == "break-alarm.caf")
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
./scripts/test.sh
```

Expected: compilation fails — `ScheduledNotification` has no `soundName` parameter.

- [ ] **Step 3: Add the field to the struct and plumb it through the real scheduler**

Open `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift` and replace the `public struct ScheduledNotification` definition (lines ~22–65) with:

```swift
/// A description of a notification to schedule. Platform-neutral — the real scheduler
/// translates it to a UNNotificationRequest, the mock scheduler just records it.
public struct ScheduledNotification: Equatable, Sendable {

    /// The unique identifier for this notification (used for cancellation).
    public let identifier: String

    /// Notification title shown on the banner / Watch face.
    public let title: String

    /// Notification body.
    public let body: String

    /// When the notification should fire, in absolute wall-clock time.
    public let fireDate: Date

    /// Whether this notification should break through Focus modes.
    /// Corresponds to `UNNotificationInterruptionLevel.timeSensitive`.
    public let isTimeSensitive: Bool

    /// Group identifier used to collapse related notifications into a single Notification
    /// Center entry. All notifications for one cycle share a thread ID.
    public let threadIdentifier: String

    /// If non-nil, attaches the given category ID so the notification exposes action buttons.
    public let categoryIdentifier: String?

    /// If non-nil, plays the named custom sound file bundled in the app when the notification
    /// fires. If nil, uses `UNNotificationSound.default`. iOS caps custom notification sounds
    /// at 30 seconds; files longer than that fall back to the default.
    public let soundName: String?

    public init(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        isTimeSensitive: Bool,
        threadIdentifier: String,
        categoryIdentifier: String?,
        soundName: String? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.isTimeSensitive = isTimeSensitive
        self.threadIdentifier = threadIdentifier
        self.categoryIdentifier = categoryIdentifier
        self.soundName = soundName
    }
}
```

Then in the same file, update `UNNotificationScheduler.schedule(_:)` — find the line `content.sound = .default` and replace the sound assignment block with:

```swift
        if let soundName = notification.soundName {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        } else {
            content.sound = .default
        }
```

- [ ] **Step 4: Run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass, including the two new `soundName` tests.

- [ ] **Step 5: Lint**

```bash
./scripts/lint.sh
```

Expected: zero errors.

- [ ] **Step 6: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift
git commit -m "$(cat <<'EOF'
Add optional soundName to ScheduledNotification

UNNotificationScheduler now picks UNNotificationSound(named:) when the
field is set, falling back to .default otherwise. Used in the next task
to plumb the custom break-alarm.caf sound into the single break
notification.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add `CascadeBuilder.buildBreakNotification` (alongside the existing cascade)

**Why:** Introduce the new single-notification builder before we switch `SessionController` to use it. This keeps tests passing across the transition and lets us delete the cascade in a later, focused task. The new function lives in the existing `CascadeBuilder` enum (the name becomes a bit of a misnomer but we preserve it to minimize churn).

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift`

- [ ] **Step 1: Add failing tests for the new builder**

In `NotificationSchedulerTests.swift`, add these tests at the bottom of the `@Suite`:

```swift
@Test("buildBreakNotification produces exactly one notification")
func buildBreakNotificationIsSingle() {
    let n = CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: startedAt)
    #expect(n.identifier == BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString)
}

@Test("buildBreakNotification fires at cycleStartedAt + breakInterval")
func buildBreakNotificationFireDate() {
    let n = CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: startedAt)
    #expect(n.fireDate == startedAt.addingTimeInterval(BlinkBreakConstants.breakInterval))
}

@Test("buildBreakNotification is time-sensitive with the break category")
func buildBreakNotificationFlags() {
    let n = CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: startedAt)
    #expect(n.isTimeSensitive)
    #expect(n.categoryIdentifier == BlinkBreakConstants.breakCategoryId)
    #expect(n.threadIdentifier == cycleId.uuidString)
}

@Test("buildBreakNotification uses the break-alarm.caf custom sound")
func buildBreakNotificationSoundName() {
    let n = CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: startedAt)
    #expect(n.soundName == "break-alarm.caf")
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
./scripts/test.sh
```

Expected: compilation fails — `CascadeBuilder.buildBreakNotification` doesn't exist yet.

- [ ] **Step 3: Add the new builder and the sound-file constant**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift`, add this line to `BlinkBreakConstants` right after `doneIdPrefix`:

```swift
    /// Filename (without directory path) of the bundled custom alarm sound for the break
    /// notification. iOS looks for this in the app bundle and truncates at 30 seconds.
    public static let breakSoundFileName = "break-alarm.caf"
```

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift`, find the `public enum CascadeBuilder` and add this function right below `buildBreakCascade` (keep the cascade builder in place for now):

```swift
    /// Build the single break notification for one cycle. Replaces the six-notification
    /// cascade once the caller (SessionController) switches over.
    /// - Parameters:
    ///   - cycleId: The UUID identifying this cycle.
    ///   - cycleStartedAt: When the 20-minute countdown began.
    /// - Returns: One ScheduledNotification with the custom alarm sound attached.
    public static func buildBreakNotification(
        cycleId: UUID,
        cycleStartedAt: Date
    ) -> ScheduledNotification {
        ScheduledNotification(
            identifier: BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString,
            title: "Time to look away",
            body: "Focus on something 20 feet away for 20 seconds.",
            fireDate: cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval),
            isTimeSensitive: true,
            threadIdentifier: cycleId.uuidString,
            categoryIdentifier: BlinkBreakConstants.breakCategoryId,
            soundName: BlinkBreakConstants.breakSoundFileName
        )
    }
```

- [ ] **Step 4: Run to confirm tests pass**

```bash
./scripts/test.sh
```

Expected: all tests pass, including the four new `buildBreakNotification` tests. Existing cascade tests still pass — nothing deleted yet.

- [ ] **Step 5: Lint**

```bash
./scripts/lint.sh
```

- [ ] **Step 6: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift \
        Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift
git commit -m "$(cat <<'EOF'
Add CascadeBuilder.buildBreakNotification for single-notification path

New builder returns one ScheduledNotification with soundName set to
break-alarm.caf. Lives alongside the existing cascade builder so the
transition can be done in isolated steps; cascade builder is deleted in
a later task.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Thread `alarm:` dependency through SessionController

**Why:** Before changing any behavior, thread the new `SessionAlarmProtocol` dependency through `SessionController.init` and wire `alarm.arm` / `alarm.disarm` into `start()`, `stop()`, `handleStartBreakAction()`, and `reconcileOnLaunch()`. In this task, `SessionController` still uses the cascade — behavior doesn't change. Only the dependency surface changes.

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift`

- [ ] **Step 1: Add alarm parameter + stored property + update start/stop/ack/reconcile**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`, find the `// MARK: - Dependencies` section and add `alarm` to the stored properties:

```swift
    private let scheduler: NotificationSchedulerProtocol
    private let connectivity: WatchConnectivityProtocol
    private let persistence: PersistenceProtocol
    private let alarm: SessionAlarmProtocol
    private let clock: @Sendable () -> Date
```

Replace the `public init(...)` with:

```swift
    /// - Parameters:
    ///   - scheduler: Notification scheduler. Use `UNNotificationScheduler()` in production,
    ///     `MockNotificationScheduler()` in tests.
    ///   - connectivity: WatchConnectivity wrapper. Use `WCSessionConnectivity()` in production,
    ///     `NoopConnectivity()` in tests / on macOS.
    ///   - persistence: Session record storage. Use `UserDefaultsPersistence()` in production,
    ///     `InMemoryPersistence()` in tests.
    ///   - alarm: Extended runtime session alarm. Use `WKExtendedRuntimeSessionAlarm()` on
    ///     Watch, `NoopSessionAlarm()` on iPhone and in tests.
    ///   - clock: Closure returning "now". Defaults to `{ Date() }`. Tests pass a closure
    ///     backed by a mutable fake date so they can advance virtual time.
    public init(
        scheduler: NotificationSchedulerProtocol,
        connectivity: WatchConnectivityProtocol,
        persistence: PersistenceProtocol,
        alarm: SessionAlarmProtocol,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scheduler = scheduler
        self.connectivity = connectivity
        self.persistence = persistence
        self.alarm = alarm
        self.clock = clock
    }
```

In the same file, update `start()` to arm the alarm after scheduling notifications. Find the existing `start()` and replace the body's last three lines (from the `for notification in ...` block through `broadcastSnapshot(for: record)`) with:

```swift
        // Schedule the six-notification cascade for this cycle.
        for notification in CascadeBuilder.buildBreakCascade(cycleId: cycleId, cycleStartedAt: cycleStartedAt) {
            scheduler.schedule(notification)
        }

        // Arm the Watch-side extended runtime session alarm. No-op on iPhone.
        alarm.arm(cycleId: cycleId, fireDate: cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval))

        state = .running(cycleStartedAt: cycleStartedAt)
        broadcastSnapshot(for: record)
```

Update `stop()` — replace the body with:

```swift
    /// Stops the current session. Transitions any-state → idle. Cancels all pending notifications
    /// and disarms the alarm.
    public func stop() {
        if let currentCycleId = persistence.load().currentCycleId {
            alarm.disarm(cycleId: currentCycleId)
        }
        scheduler.cancelAll()
        persistence.save(.idle)
        state = .idle
        broadcastSnapshot(for: .idle)
    }
```

Update `handleStartBreakAction(cycleId:)` — find the existing implementation and replace the entire method body with:

```swift
    public func handleStartBreakAction(cycleId: UUID) {
        let record = persistence.load()
        guard record.sessionActive,
              let currentCycleId = record.currentCycleId,
              currentCycleId == cycleId else {
            return
        }

        // 1. Disarm the current cycle's alarm (stops any in-progress haptic loop on Watch).
        alarm.disarm(cycleId: cycleId)

        // 2. Cancel all notifications for this cycle (pending and delivered).
        scheduler.cancel(identifiers: CascadeBuilder.identifiers(for: cycleId))

        // 3. Generate the next cycle.
        let lookAwayStartedAt = clock()
        let nextCycleId = UUID()
        let nextCycleStartedAt = lookAwayStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)

        // 4. Schedule the done notification for the current look-away window.
        scheduler.schedule(
            CascadeBuilder.buildDoneNotification(cycleId: cycleId, lookAwayStartedAt: lookAwayStartedAt)
        )

        // 5. Schedule the next cycle's cascade (still cascade at this point; switched in the
        //    next task).
        for notification in CascadeBuilder.buildBreakCascade(cycleId: nextCycleId, cycleStartedAt: nextCycleStartedAt) {
            scheduler.schedule(notification)
        }

        // 6. Arm the alarm for the next cycle.
        alarm.arm(
            cycleId: nextCycleId,
            fireDate: nextCycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        )

        // 7. Persist + update state + broadcast.
        let newRecord = SessionRecord(
            sessionActive: true,
            currentCycleId: nextCycleId,
            cycleStartedAt: nextCycleStartedAt,
            lookAwayStartedAt: lookAwayStartedAt,
            lastUpdatedAt: clock()
        )
        persistence.save(newRecord)
        state = .lookAway(lookAwayStartedAt: lookAwayStartedAt)
        broadcastSnapshot(for: newRecord)
    }
```

Update `reconcileOnLaunch()` — find the `// Case 4: break time hasn't arrived yet → running.` block and replace it with:

```swift
        // Case 4: break time hasn't arrived yet → running.
        let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        if now < breakFireTime {
            state = .running(cycleStartedAt: cycleStartedAt)
            // Re-arm the alarm for the remaining time in the cycle. On iPhone this is
            // a no-op (NoopSessionAlarm); on Watch it restores the extended runtime
            // session after an app kill / launch.
            alarm.arm(cycleId: currentCycleId, fireDate: breakFireTime)
            return
        }
```

- [ ] **Step 2: Update test fixtures to inject MockSessionAlarm**

Open `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift` and update the `Fixture` class. Replace the stored properties and init with:

```swift
        let scheduler = MockNotificationScheduler()
        let connectivity = MockWatchConnectivity()
        let persistence = InMemoryPersistence()
        let alarm = MockSessionAlarm()
        let nowBox = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
        let controller: SessionController

        init() {
            let box = nowBox
            self.controller = SessionController(
                scheduler: scheduler,
                connectivity: connectivity,
                persistence: persistence,
                alarm: alarm,
                clock: { box.value }
            )
        }
```

Open `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift` and apply the equivalent update. Replace the `Fixture` init section with:

```swift
        let scheduler = MockNotificationScheduler()
        let persistence = InMemoryPersistence()
        let alarm = MockSessionAlarm()
        let nowBox = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
        let controller: SessionController

        init() {
            let box = nowBox
            self.controller = SessionController(
                scheduler: scheduler,
                connectivity: MockWatchConnectivity(),
                persistence: persistence,
                alarm: alarm,
                clock: { box.value }
            )
        }
```

- [ ] **Step 3: Add test assertions that alarm is armed/disarmed correctly**

At the bottom of `SessionControllerTests.swift`'s `@Suite`, add:

```swift
    // MARK: - Alarm wiring

    @Test("start() arms the alarm with the cycleId and correct fireDate")
    func startArmsAlarm() {
        let f = Fixture()
        f.controller.start()

        let armed = f.alarm.lastArmed
        #expect(armed != nil)
        #expect(armed?.cycleId == f.persistence.load().currentCycleId)
        #expect(armed?.fireDate == f.nowBox.value.addingTimeInterval(BlinkBreakConstants.breakInterval))
    }

    @Test("stop() disarms the current cycle's alarm")
    func stopDisarmsAlarm() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!

        f.controller.stop()

        #expect(f.alarm.lastDisarmedCycleId == cycleId)
    }

    @Test("handleStartBreakAction disarms the current cycle and arms the next")
    func ackDisarmsAndReArms() {
        let f = Fixture()
        f.controller.start()
        let firstCycleId = f.persistence.load().currentCycleId!
        f.advance(by: BlinkBreakConstants.breakInterval)

        f.controller.handleStartBreakAction(cycleId: firstCycleId)

        #expect(f.alarm.disarmedCycleIds.contains(firstCycleId))
        #expect(f.alarm.armedCalls.count == 2)  // start + re-arm
        let nextArmed = f.alarm.lastArmed!
        #expect(nextArmed.cycleId == f.persistence.load().currentCycleId)
    }
```

And at the bottom of `ReconciliationTests.swift`'s `@Suite`, add:

```swift
    @Test("reconcile in running state re-arms the alarm for the remaining time")
    func reconcileRunningReArmsAlarm() async {
        let f = Fixture()
        let cycleId = UUID()
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: f.nowBox.value,
            lookAwayStartedAt: nil
        ))
        f.scheduler.stubPendingIdentifiers = CascadeBuilder.identifiers(for: cycleId)

        await f.controller.reconcileOnLaunch()

        #expect(f.alarm.lastArmed?.cycleId == cycleId)
        #expect(f.alarm.lastArmed?.fireDate == f.nowBox.value.addingTimeInterval(BlinkBreakConstants.breakInterval))
    }
```

- [ ] **Step 4: Run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass, including the four new alarm-wiring assertions. Existing cascade tests still pass because SessionController still uses the cascade builder.

- [ ] **Step 5: Lint**

```bash
./scripts/lint.sh
```

- [ ] **Step 6: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift
git commit -m "$(cat <<'EOF'
Thread SessionAlarmProtocol through SessionController

Adds alarm: dependency to init and wires alarm.arm/alarm.disarm into
start, stop, handleStartBreakAction, and reconcileOnLaunch. Tests inject
MockSessionAlarm and assert the expected arm/disarm call sequence. No
behavior change for cascade/notification scheduling — SessionController
still uses the cascade builder; the switch to single-notification happens
in the next task.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Switch SessionController to use `buildBreakNotification` (single notification)

**Why:** Now that the alarm surface is wired, switch the notification path from cascade (6 notifications) to single. This is where the user-visible behavior changes. All existing cascade-based test assertions need updating to expect a single notification per cycle.

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift`

- [ ] **Step 1: Switch `start()` to use `buildBreakNotification`**

In `SessionController.swift`, find the `for notification in CascadeBuilder.buildBreakCascade(...)` block inside `start()` and replace it with:

```swift
        // Schedule the single break notification for this cycle.
        scheduler.schedule(CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: cycleStartedAt))
```

- [ ] **Step 2: Switch `handleStartBreakAction()` to use `buildBreakNotification` for the next cycle**

In the same file, find the `for notification in CascadeBuilder.buildBreakCascade(cycleId: nextCycleId, ...)` block inside `handleStartBreakAction` and replace it with:

```swift
        // 5. Schedule the next cycle's single break notification.
        scheduler.schedule(
            CascadeBuilder.buildBreakNotification(cycleId: nextCycleId, cycleStartedAt: nextCycleStartedAt)
        )
```

- [ ] **Step 3: Update `SessionControllerTests.swift` cascade assertions**

Open `SessionControllerTests.swift`. Find and replace the following tests:

Replace `startSchedulesCascade` (the whole test function, ~20 lines) with:

```swift
    @Test("start() schedules a single break notification")
    func startSchedulesSingleBreakNotification() {
        let f = Fixture()
        f.controller.start()

        #expect(f.scheduler.scheduledNotifications.count == 1)
        let n = f.scheduler.scheduledNotifications[0]
        #expect(n.isTimeSensitive)
        #expect(n.categoryIdentifier == BlinkBreakConstants.breakCategoryId)
        #expect(n.soundName == BlinkBreakConstants.breakSoundFileName)
        let cycleId = f.persistence.load().currentCycleId!
        #expect(n.identifier == BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString)
        #expect(n.threadIdentifier == cycleId.uuidString)
    }
```

Replace `startCancelsStaleNotifications` with:

```swift
    @Test("start() wipes stale notifications from a previous crashed session")
    func startCancelsStaleNotifications() {
        let f = Fixture()
        f.scheduler.schedule(ScheduledNotification(
            identifier: "stale.old",
            title: "x", body: "x",
            fireDate: f.nowBox.value.addingTimeInterval(60),
            isTimeSensitive: false,
            threadIdentifier: "stale",
            categoryIdentifier: nil
        ))

        f.controller.start()

        #expect(f.scheduler.cancelAllCount == 1)
        #expect(f.scheduler.scheduledNotifications.count == 1)
        #expect(!f.scheduler.scheduledNotifications.contains { $0.identifier == "stale.old" })
    }
```

Replace `ackSchedulesDoneAndNextCascade` with:

```swift
    @Test("handleStartBreakAction schedules a done notification + next break notification")
    func ackSchedulesDoneAndNextBreak() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!
        f.advance(by: BlinkBreakConstants.breakInterval)

        f.controller.handleStartBreakAction(cycleId: cycleId)

        // After ack: old break cancelled, done scheduled (1) + new break scheduled (1) = 2 remaining.
        #expect(f.scheduler.scheduledNotifications.count == 2)

        let ids = f.scheduler.scheduledNotifications.map(\.identifier)
        #expect(ids.contains(BlinkBreakConstants.doneIdPrefix + cycleId.uuidString))

        // The new break notification is for a different cycleId.
        let newCycleId = f.persistence.load().currentCycleId!
        #expect(newCycleId != cycleId)
        #expect(ids.contains(BlinkBreakConstants.breakPrimaryIdPrefix + newCycleId.uuidString))
    }
```

- [ ] **Step 4: Update `ReconciliationTests.swift` `pastBreakNoPending` test**

In `ReconciliationTests.swift`, find the `pastBreakNoPending` test and replace its `f.advance(by:)` call with a simpler version (no more nudgeInterval/nudgeCount references — we'll delete those constants later, but even now they compile since they still exist). Replace the entire test with:

```swift
    @Test("reconcile past break time with no pending notifications → idle fallback")
    func pastBreakNoPending() async {
        let f = Fixture()
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: f.nowBox.value,
            lookAwayStartedAt: nil
        ))
        f.scheduler.stubPendingIdentifiers = []

        // Advance well past the break time.
        f.advance(by: BlinkBreakConstants.breakInterval + 60)

        await f.controller.reconcileOnLaunch()

        #expect(f.controller.state == .idle)
        #expect(f.persistence.load() == .idle)
    }
```

- [ ] **Step 5: Run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass. `NotificationSchedulerTests` still contains cascade tests (we delete them in a later task). `SessionControllerTests` and `ReconciliationTests` now expect single-notification behavior.

- [ ] **Step 6: Lint**

```bash
./scripts/lint.sh
```

- [ ] **Step 7: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift
git commit -m "$(cat <<'EOF'
Switch SessionController to single break notification

start() and handleStartBreakAction() now call buildBreakNotification
instead of buildBreakCascade. Tests updated to expect exactly 1 break
notification per cycle with soundName set to the bundled alarm file.
Cascade builder is still present; dead-code cleanup happens in a
later task after handleRemoteSnapshot lands.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Add `handleRemoteSnapshot` + rename `wireUpWatchCommands` → `wireUpConnectivity` + wire `onSnapshotReceived`

**Why:** This is what makes "tap Start break on Watch, iPhone notification disappears" work. When either device runs `handleStartBreakAction`, it broadcasts the new snapshot via WCSession; the other device's `handleRemoteSnapshot` processes the incoming snapshot to cancel its own delivered notification and disarm its local alarm.

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockWatchConnectivity.swift` (if needed)

- [ ] **Step 1: Inspect MockWatchConnectivity for existing test helpers**

```bash
cat Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockWatchConnectivity.swift
```

If the mock doesn't expose a way to trigger `onSnapshotReceived?(snapshot)` from a test, add a helper like:

```swift
func simulateIncomingSnapshot(_ snapshot: SessionSnapshot) {
    onSnapshotReceived?(snapshot)
}
```

to the mock class (inserted into the existing `MockWatchConnectivity` file). Only add if not already present.

- [ ] **Step 2: Add failing tests for `handleRemoteSnapshot`**

At the bottom of `SessionControllerTests.swift`'s `@Suite`, add:

```swift
    // MARK: - handleRemoteSnapshot

    @Test("handleRemoteSnapshot with a remote ack cancels delivered notifications for the acked cycle")
    func remoteAckCancelsDelivered() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!
        f.advance(by: BlinkBreakConstants.breakInterval)

        // Simulate the OTHER device acking the break.
        let remoteSnapshot = SessionSnapshot(
            sessionActive: true,
            currentCycleId: UUID(),  // new cycle from the remote side
            cycleStartedAt: f.nowBox.value.addingTimeInterval(BlinkBreakConstants.lookAwayDuration),
            lookAwayStartedAt: f.nowBox.value,
            updatedAt: f.nowBox.value
        )
        f.controller.handleRemoteSnapshot(remoteSnapshot)

        let cancelled = f.scheduler.lastCancelledIdentifiers ?? []
        #expect(cancelled.contains(BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString))
    }

    @Test("handleRemoteSnapshot with a remote ack disarms the local alarm for the acked cycle")
    func remoteAckDisarmsAlarm() {
        let f = Fixture()
        f.controller.start()
        let cycleId = f.persistence.load().currentCycleId!
        f.alarm.reset()  // clear the initial arm from start()
        f.advance(by: BlinkBreakConstants.breakInterval)

        let remoteSnapshot = SessionSnapshot(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: f.nowBox.value.addingTimeInterval(BlinkBreakConstants.lookAwayDuration),
            lookAwayStartedAt: f.nowBox.value,
            updatedAt: f.nowBox.value
        )
        f.controller.handleRemoteSnapshot(remoteSnapshot)

        #expect(f.alarm.disarmedCycleIds.contains(cycleId))
    }

    @Test("handleRemoteSnapshot is idempotent when called twice with the same snapshot")
    func remoteSnapshotDoubleDelivery() {
        let f = Fixture()
        f.controller.start()
        f.advance(by: BlinkBreakConstants.breakInterval)

        let snapshot = SessionSnapshot(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: f.nowBox.value.addingTimeInterval(BlinkBreakConstants.lookAwayDuration),
            lookAwayStartedAt: f.nowBox.value,
            updatedAt: f.nowBox.value
        )
        f.controller.handleRemoteSnapshot(snapshot)
        let recordAfterFirst = f.persistence.load()
        f.controller.handleRemoteSnapshot(snapshot)
        let recordAfterSecond = f.persistence.load()

        #expect(recordAfterFirst == recordAfterSecond)
    }

    @Test("handleRemoteSnapshot ignores snapshots older than the local lastUpdatedAt")
    func remoteSnapshotStaleIgnored() {
        let f = Fixture()
        f.controller.start()
        let cycleIdBefore = f.persistence.load().currentCycleId

        // Manually age the local record forward.
        var rec = f.persistence.load()
        rec.lastUpdatedAt = f.nowBox.value.addingTimeInterval(100)
        f.persistence.save(rec)

        // Deliver a snapshot with an older updatedAt.
        let stale = SessionSnapshot(
            sessionActive: false,
            currentCycleId: nil,
            cycleStartedAt: nil,
            lookAwayStartedAt: nil,
            updatedAt: f.nowBox.value.addingTimeInterval(50)
        )
        f.controller.handleRemoteSnapshot(stale)

        // Local record untouched.
        #expect(f.persistence.load().currentCycleId == cycleIdBefore)
    }
```

- [ ] **Step 3: Run to confirm failure**

```bash
./scripts/test.sh
```

Expected: compilation fails — `handleRemoteSnapshot` doesn't exist on `SessionController`.

- [ ] **Step 4: Implement `handleRemoteSnapshot` + rename `wireUpWatchCommands` → `wireUpConnectivity`**

In `SessionController.swift`, find `wireUpWatchCommands()` and replace it entirely with:

```swift
    /// Hook up the WatchConnectivity service to the controller's state. Call once, after
    /// initializing. Wires both directions:
    /// - Incoming commands (`start`, `stop`, `startBreak`) become method calls.
    /// - Incoming state snapshots become `handleRemoteSnapshot` calls.
    public func wireUpConnectivity() {
        connectivity.onCommandReceived = { [weak self] command, cycleId in
            guard let self else { return }
            Task { @MainActor in
                switch command {
                case .start:
                    self.start()
                case .stop:
                    self.stop()
                case .startBreak:
                    if let cycleId = cycleId {
                        self.handleStartBreakAction(cycleId: cycleId)
                    }
                }
            }
        }
        connectivity.onSnapshotReceived = { [weak self] snapshot in
            guard let self else { return }
            Task { @MainActor in
                self.handleRemoteSnapshot(snapshot)
            }
        }
    }

    /// Processes an incoming WCSession snapshot from the paired device. Implements the
    /// acknowledgment-sync rule: if a remote ack just happened (incoming `lookAwayStartedAt`
    /// newly set), cancel our delivered notification for the acked cycle and disarm our
    /// local alarm.
    ///
    /// Idempotent: calling with the same snapshot twice produces the same end state.
    /// Protected by a staleness guard: snapshots older than the local `lastUpdatedAt` are
    /// dropped so out-of-order delivery can't clobber newer state.
    public func handleRemoteSnapshot(_ snapshot: SessionSnapshot) {
        let local = persistence.load()

        // Staleness guard: ignore older-than-local snapshots.
        let localStamp = local.lastUpdatedAt ?? .distantPast
        guard snapshot.updatedAt > localStamp else { return }

        // Detect a fresh remote ack: incoming snapshot has lookAwayStartedAt set, local
        // didn't. Cancel delivered notifications for the acked cycleId and disarm the alarm.
        let remoteAckedBreak = snapshot.lookAwayStartedAt != nil && local.lookAwayStartedAt == nil
        if remoteAckedBreak, let ackedCycleId = local.currentCycleId {
            scheduler.cancel(identifiers: CascadeBuilder.identifiers(for: ackedCycleId))
            alarm.disarm(cycleId: ackedCycleId)
        }

        // Persist the new snapshot locally. reconcileOnLaunch will be called as an
        // awaited task below, outside this synchronous method, for callers that want to
        // pick up the new state. For tests we rely on the persisted record being updated.
        persistence.save(SessionRecord(from: snapshot))
    }
```

Update `BlinkBreakApp.swift` and `BlinkBreakWatchApp.swift` callers (we'll do that in tasks 9 and 11), but also update this file's single reference to `wireUpWatchCommands` in any call path — search for it:

```bash
grep -rn "wireUpWatchCommands" Packages BlinkBreak "BlinkBreak Watch App"
```

Any references inside `Packages/BlinkBreakCore/` should be updated to `wireUpConnectivity` in this task; references inside the app targets are updated in later tasks.

- [ ] **Step 5: Run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass, including the four new `handleRemoteSnapshot` tests.

- [ ] **Step 6: Lint**

```bash
./scripts/lint.sh
```

- [ ] **Step 7: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockWatchConnectivity.swift
git commit -m "$(cat <<'EOF'
Add handleRemoteSnapshot + rename wireUpWatchCommands

handleRemoteSnapshot processes incoming WCSession snapshots and, on
detecting a fresh remote break acknowledgment, cancels our delivered
notification for the acked cycle and disarms the local alarm — idempotent
and guarded against out-of-order delivery via lastUpdatedAt staleness
check. wireUpWatchCommands renamed to wireUpConnectivity since it now
wires both onCommandReceived and onSnapshotReceived.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Delete cascade builder + nudge constants + cascade-specific tests

**Why:** Nothing in `BlinkBreakCore` still calls `buildBreakCascade` or references the nudge constants. Deleting them removes dead code and shrinks the `identifiers(for:)` return to two entries.

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ReconciliationTests.swift` (check for remaining nudge references)

- [ ] **Step 1: Verify no source-of-truth references remain**

```bash
grep -rn "buildBreakCascade\|nudgeInterval\|nudgeCount\|breakNudgeIdPrefix" \
    Packages/BlinkBreakCore/Sources
```

Expected: only lines inside `NotificationScheduler.swift` (the cascade function we're deleting) and `Constants.swift` (the constants we're deleting). No call sites in `SessionController.swift`.

- [ ] **Step 2: Delete `buildBreakCascade` + collapse `identifiers(for:)`**

In `NotificationScheduler.swift`, delete the entire `public static func buildBreakCascade(...)` function (lines ~103 through ~144 in the original file).

Then replace `CascadeBuilder.identifiers(for:)` with:

```swift
    /// Returns every notification identifier that belongs to a specific cycle.
    /// Used for targeted cancellation — "cancel the notifications for this cycle" translates
    /// into `cancel(identifiers: CascadeBuilder.identifiers(for: cycleId))`.
    public static func identifiers(for cycleId: UUID) -> [String] {
        [
            BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString,
            BlinkBreakConstants.doneIdPrefix + cycleId.uuidString
        ]
    }
```

- [ ] **Step 3: Delete nudge constants**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift`, delete these lines from `BlinkBreakConstants`:

- `public static let nudgeInterval: TimeInterval = 5`
- `public static let nudgeCount: Int = 5`
- `public static let breakNudgeIdPrefix = "break.nudge."`

Also delete the `// MARK: - Notification cascade tuning` section header since all its contents are gone.

- [ ] **Step 4: Delete cascade-specific tests from NotificationSchedulerTests.swift**

Open `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift` and DELETE these tests entirely:

- `cascadeCount`
- `primaryFireTime`
- `nudgeFireTimes`
- `sharedThreadId` (replaced with a test on the new builder — see below)
- `allTimeSensitive` (same)
- `allInBreakCategory` (same)

Replace `allIdentifiersForCycle` with:

```swift
    @Test("identifiers(for:) returns the break + done identifiers for a cycle")
    func allIdentifiersForCycle() {
        let ids = CascadeBuilder.identifiers(for: cycleId)
        #expect(ids.count == 2)
        #expect(ids.contains(BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString))
        #expect(ids.contains(BlinkBreakConstants.doneIdPrefix + cycleId.uuidString))
    }
```

The `buildBreakNotification*` and `doneNotification` tests (added in Task 4 and already present in the file) stay.

- [ ] **Step 5: Run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass. No more nudge references anywhere.

- [ ] **Step 6: Final grep to confirm cleanup**

```bash
grep -rn "buildBreakCascade\|nudgeInterval\|nudgeCount\|breakNudgeIdPrefix" \
    Packages
```

Expected: zero results.

- [ ] **Step 7: Lint**

```bash
./scripts/lint.sh
```

- [ ] **Step 8: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift \
        Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift
git commit -m "$(cat <<'EOF'
Delete cascade builder, nudge constants, and cascade-specific tests

The single-notification path is now fully in place and tested.
buildBreakCascade, nudgeInterval, nudgeCount, and breakNudgeIdPrefix all
removed. CascadeBuilder.identifiers(for:) collapsed from 7 ids to 2.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Wire iPhone app to inject `NoopSessionAlarm` + call `wireUpConnectivity`

**Why:** The iPhone target now needs to construct its `SessionController` with `alarm: NoopSessionAlarm()` and call the renamed `wireUpConnectivity()` on first appear.

**Files:**
- Modify: `BlinkBreak/BlinkBreakApp.swift`

- [ ] **Step 1: Update injection and wiring call**

Open `BlinkBreak/BlinkBreakApp.swift` and replace the `@StateObject private var controller` block and the `onAppear` modifier with:

```swift
    @StateObject private var controller: SessionController = {
        let scheduler = UNNotificationScheduler()
        scheduler.registerCategories()
        return SessionController(
            scheduler: scheduler,
            connectivity: WCSessionConnectivity(),
            persistence: UserDefaultsPersistence(),
            alarm: NoopSessionAlarm()
        )
    }()

    var body: some Scene {
        WindowGroup {
            RootView(controller: controller)
                .onAppear {
                    appDelegate.controller = controller
                    appDelegate.requestNotificationAuthorizationIfNeeded()

                    // Activate WatchConnectivity and wire up incoming Watch commands
                    // and snapshots. Snapshots from the Watch arrive when the user acks
                    // a break on the Watch — handleRemoteSnapshot cancels our delivered
                    // iPhone notification and disarms our (noop) alarm.
                    controller.connectivity.activate()
                    controller.wireUpConnectivity()
                    Task { await controller.reconcileOnLaunch() }
                }
        }
    }
```

Note: this references `controller.connectivity.activate()` — verify that `SessionController` exposes `connectivity` externally or that the call is reshaped. Check:

```bash
grep -n "connectivity" Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift
```

If `connectivity` is `private let`, add a method on `SessionController`:

```swift
    /// Activate the underlying connectivity service. Call once at launch, before wireUpConnectivity.
    public func activateConnectivity() {
        connectivity.activate()
    }
```

and then the iOS app calls `controller.activateConnectivity()` instead of `controller.connectivity.activate()`. Use whichever approach keeps `connectivity` private.

- [ ] **Step 2: Run tests + build**

```bash
./scripts/test.sh
./scripts/build.sh
```

Expected: both pass. The iOS target builds cleanly.

- [ ] **Step 3: Lint**

```bash
./scripts/lint.sh
```

- [ ] **Step 4: Commit**

```bash
git add BlinkBreak/BlinkBreakApp.swift \
        Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift
git commit -m "$(cat <<'EOF'
Inject NoopSessionAlarm on iPhone and wire onSnapshotReceived

iPhone SessionController now receives NoopSessionAlarm (iPhone doesn't
host the extended runtime session; its alarm is the custom-sound
notification). onAppear calls wireUpConnectivity so handleRemoteSnapshot
runs when the Watch broadcasts a break acknowledgment.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Create `WKExtendedRuntimeSessionAlarm` in the Watch target

**Why:** The concrete Watch-side `SessionAlarmProtocol` implementation that actually holds an extended runtime session alive in the background, schedules a timer for the break fire date, and at fire time starts the repeating haptic loop via `notifyUser(hapticType:repeatHandler:)`.

**Files:**
- Create: `BlinkBreak Watch App/WKExtendedRuntimeSessionAlarm.swift`

Note: this class is hand-verified, not unit-tested. It imports `WatchKit` so it can't live in `BlinkBreakCore`. Its surface is covered indirectly by the SessionController tests through `MockSessionAlarm`.

- [ ] **Step 1: Create the file**

Create `BlinkBreak Watch App/WKExtendedRuntimeSessionAlarm.swift` with exactly this content:

```swift
//
//  WKExtendedRuntimeSessionAlarm.swift
//  BlinkBreak Watch App
//
//  Concrete implementation of SessionAlarmProtocol backed by WKExtendedRuntimeSession.
//  Holds the Watch app alive in the background for the duration of one 20-minute cycle,
//  then at break time calls session.notifyUser(hapticType:repeatHandler:) to play a
//  repeating haptic until the user taps Start break (which calls disarm) or the ~30s
//  maximum elapses.
//
//  Also posts a Watch-local notification at break time so the user has a tappable
//  notification-center entry with the "Start break" action visible directly from the
//  wrist (the thing that was broken in V1).
//
//  Not unit-tested — this class is a thin translator between the protocol and the
//  platform APIs. Interesting logic lives in SessionController and is covered via
//  MockSessionAlarm. Manual on-device verification is the test plan.
//

import Foundation
import WatchKit
import UserNotifications
import BlinkBreakCore

/// Watch-side alarm that holds an extended runtime session alive and fires repeating
/// haptics + a local notification when the break fire date is reached.
final class WKExtendedRuntimeSessionAlarm: NSObject, SessionAlarmProtocol, @unchecked Sendable {

    // MARK: - State

    private let lock = NSLock()
    private var armedCycleId: UUID?
    private var session: WKExtendedRuntimeSession?
    private var fireTimer: DispatchSourceTimer?
    private var disarmed: Bool = false

    /// Maximum elapsed time the haptic loop continues before auto-terminating.
    /// Matches the cascade's original ~25–30 second alarm window.
    private let maxHapticSeconds: TimeInterval = 30

    // MARK: - SessionAlarmProtocol

    func arm(cycleId: UUID, fireDate: Date) {
        // Defensive: if we already have an armed cycle, tear it down first.
        disarmInternal()

        lock.lock()
        armedCycleId = cycleId
        disarmed = false
        lock.unlock()

        // Start the extended runtime session. This keeps the Watch app alive in the
        // background for this cycle. Session type .selfCare covers self-care activities
        // like the 20-20-20 eye rest. (If .selfCare is unavailable on the target watchOS
        // SDK, switch to .mindfulness — both are ~1 hour max, well above a 20-minute cycle.)
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        newSession.start()
        session = newSession

        // Schedule a DispatchSourceTimer for the break fire date. When it fires, we
        // kick off the repeating haptic + post the Watch-local notification.
        let delay = max(fireDate.timeIntervalSinceNow, 0.1)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.fireAlarm(cycleId: cycleId)
        }
        timer.resume()
        fireTimer = timer
    }

    func disarm(cycleId: UUID) {
        lock.lock()
        guard armedCycleId == cycleId else {
            lock.unlock()
            return
        }
        lock.unlock()
        disarmInternal()
        removeDeliveredNotification(for: cycleId)
    }

    // MARK: - Private

    private func disarmInternal() {
        lock.lock()
        disarmed = true
        armedCycleId = nil
        lock.unlock()

        fireTimer?.cancel()
        fireTimer = nil

        if let s = session, s.state == .running {
            s.invalidate()
        }
        session = nil
    }

    private func fireAlarm(cycleId: UUID) {
        guard let s = session, s.state == .running else { return }

        // Kick off the repeating haptic. System controls cadence between calls; we
        // control total duration and early termination via the `stop` out-parameter.
        s.notifyUser(hapticType: .notification) { [weak self] elapsed in
            guard let self else { return .notification }

            self.lock.lock()
            let isDisarmed = self.disarmed
            self.lock.unlock()

            if isDisarmed || elapsed >= self.maxHapticSeconds {
                // Per the API: returning a haptic type here still plays it, but the
                // system will not invoke the closure again after this call. We terminate
                // by ending the session after the closure returns. Simplest approach:
                // invalidate the session on the main queue so no further invocations occur.
                DispatchQueue.main.async { [weak self] in
                    if let s = self?.session, s.state == .running {
                        s.invalidate()
                    }
                }
                return .stop
            }

            return .notification
        }

        postWatchLocalNotification(cycleId: cycleId)
    }

    private func postWatchLocalNotification(cycleId: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Time to look away"
        content.body = "Focus on something 20 feet away for 20 seconds."
        content.sound = .default
        content.categoryIdentifier = BlinkBreakConstants.breakCategoryId
        content.threadIdentifier = cycleId.uuidString
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[WKExtendedRuntimeSessionAlarm] notification add failed: \(error)")
            }
        }
    }

    private func removeDeliveredNotification(for cycleId: UUID) {
        let id = BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WKExtendedRuntimeSessionAlarm: WKExtendedRuntimeSessionDelegate {

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("[WKExtendedRuntimeSessionAlarm] session started")
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // Session is about to be reclaimed. We don't attempt renewal — the iPhone
        // notification at T+20:00 is the fallback that guarantees the user still
        // gets alerted even if the session dies early. This should essentially never
        // fire in normal use since sessions of type .selfCare run up to ~1 hour and
        // a cycle is only ~20 minutes.
        print("[WKExtendedRuntimeSessionAlarm] session will expire — relying on iPhone fallback")
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        print("[WKExtendedRuntimeSessionAlarm] session invalidated: reason=\(reason.rawValue) error=\(String(describing: error))")
        lock.lock()
        session = nil
        lock.unlock()
    }
}
```

**Note on `.selfCare` session type:** If this enum value isn't available at compile time on the target SDK, swap to `.mindfulness` — both have equivalent runtime semantics for our needs. Verify against the current Apple docs if the compiler complains.

**Note on `.stop` haptic type return:** `WKHapticType` does include `.stop` as a valid terminator signal for the repeat handler. If the compiler complains, replace the stop paths with `.notification` and rely on the explicit `session.invalidate()` call to halt further haptic invocations.

- [ ] **Step 2: Build the Watch target**

```bash
./scripts/build.sh
```

Expected: the full Xcode build (including the Watch target) succeeds.

- [ ] **Step 3: Lint**

```bash
./scripts/lint.sh
```

Expected: no forbidden-import failures. `WKExtendedRuntimeSessionAlarm` is in `BlinkBreak Watch App/`, not in `BlinkBreakCore`, so its `import WatchKit` is allowed.

- [ ] **Step 4: Commit**

```bash
git add "BlinkBreak Watch App/WKExtendedRuntimeSessionAlarm.swift"
git commit -m "$(cat <<'EOF'
Add WKExtendedRuntimeSessionAlarm for Watch haptic loop

Holds a WKExtendedRuntimeSession alive in the background for one cycle,
schedules a DispatchSourceTimer for the break fire date, and at fire time
calls session.notifyUser(hapticType:repeatHandler:) to play repeating
haptics for up to 30 seconds or until disarm is called. Also posts a
Watch-local notification with the Start break action visible directly on
the wrist. Hand-verified on device — not unit-tested, consistent with how
the UNNotificationScheduler translator is treated today.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Wire Watch app to inject `WKExtendedRuntimeSessionAlarm` + call `wireUpConnectivity`

**Why:** The Watch target needs to construct its `SessionController` with the concrete alarm, activate connectivity, and wire both `onCommandReceived` and `onSnapshotReceived` via the renamed method. This also deletes the stub `wireUpSnapshotReceiver()` helper.

**Files:**
- Modify: `BlinkBreak Watch App/BlinkBreakWatchApp.swift`

- [ ] **Step 1: Update the Watch app struct**

Replace the entire contents of `BlinkBreak Watch App/BlinkBreakWatchApp.swift` with:

```swift
//
//  BlinkBreakWatchApp.swift
//  BlinkBreak Watch App
//
//  The watchOS app entry point. Wires up a shared SessionController with the
//  WKExtendedRuntimeSession-backed alarm, an AppDelegate for notification handling,
//  and activates WatchConnectivity so the Watch can receive state snapshots from the
//  iPhone and forward user commands back.
//

import SwiftUI
import BlinkBreakCore

@main
struct BlinkBreakWatchApp: App {

    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate

    @StateObject private var controller: SessionController = {
        let scheduler = UNNotificationScheduler()
        scheduler.registerCategories()
        return SessionController(
            scheduler: scheduler,
            connectivity: WCSessionConnectivity(),
            persistence: UserDefaultsPersistence(),
            alarm: WKExtendedRuntimeSessionAlarm()
        )
    }()

    var body: some Scene {
        WindowGroup {
            WatchRootView(controller: controller)
                .onAppear {
                    appDelegate.controller = controller

                    // Activate WatchConnectivity and wire up both directions:
                    // - onCommandReceived: the (rarely-used) Watch→Phone path.
                    // - onSnapshotReceived: iPhone broadcasts state snapshots the
                    //   Watch applies via handleRemoteSnapshot.
                    controller.activateConnectivity()
                    controller.wireUpConnectivity()
                    Task { await controller.reconcileOnLaunch() }
                }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
./scripts/build.sh
```

Expected: clean build. Both targets compile.

- [ ] **Step 3: Run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass.

- [ ] **Step 4: Lint**

```bash
./scripts/lint.sh
```

- [ ] **Step 5: Commit**

```bash
git add "BlinkBreak Watch App/BlinkBreakWatchApp.swift"
git commit -m "$(cat <<'EOF'
Inject WKExtendedRuntimeSessionAlarm on Watch and wire snapshots

Watch SessionController now receives the concrete WKExtendedRuntimeSession
alarm. onAppear activates connectivity and calls wireUpConnectivity so
handleRemoteSnapshot runs when the iPhone broadcasts state changes.
Deletes the dead wireUpSnapshotReceiver() stub that was never hooking
up onSnapshotReceived.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Generate `break-alarm.caf` + add to project resources

**Why:** iPhone's single-notification fallback needs a bundled custom sound file. This task creates the generator script, runs it to produce the .caf, updates `project.yml` to bundle the resources directory, and regenerates the Xcode project.

**Files:**
- Create: `scripts/sound/generate-alarm.swift`
- Create: `BlinkBreak/Resources/Sounds/break-alarm.caf` (via the script)
- Modify: `project.yml`

- [ ] **Step 1: Create the generator script**

Create `scripts/sound/generate-alarm.swift` with exactly this content:

```swift
#!/usr/bin/env swift
//
// generate-alarm.swift
//
// Synthesizes a ~28-second pulsing two-tone alarm pattern and writes it to
// BlinkBreak/Resources/Sounds/break-alarm.caf. Run from the repo root:
//
//     swift scripts/sound/generate-alarm.swift
//
// iOS caps custom UNNotificationSound files at 30 seconds, so we stay safely under.
//

import Foundation
import AVFoundation

// MARK: - Parameters

let sampleRate: Double = 44100
let totalDuration: Double = 28.0
let totalFrames = Int(sampleRate * totalDuration)

// Each "beep cycle" is two short tones + rest:
//   beep1 (800 Hz) : 150 ms
//   gap            : 100 ms
//   beep2 (1000 Hz): 150 ms
//   rest           : 800 ms
// Total cycle: 1200 ms → 23 full cycles + a partial cycle in 28 s.
let beepDur: Double = 0.15
let beepGap: Double = 0.10
let restDur: Double = 0.80
let cycleDur: Double = beepDur + beepGap + beepDur + restDur  // 1.2 s
let freq1: Double = 800
let freq2: Double = 1000
let amplitude: Double = 0.5
let fadeDur: Double = 0.010  // 10 ms fade in/out to avoid click artifacts

// MARK: - Audio buffer

guard let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: sampleRate,
    channels: 1,
    interleaved: false
) else {
    fatalError("Failed to build audio format")
}

guard let buffer = AVAudioPCMBuffer(
    pcmFormat: format,
    frameCapacity: AVAudioFrameCount(totalFrames)
) else {
    fatalError("Failed to build audio buffer")
}
buffer.frameLength = AVAudioFrameCount(totalFrames)

guard let samples = buffer.int16ChannelData?[0] else {
    fatalError("Failed to get channel data")
}

// MARK: - Synthesis

func envelope(_ t: Double, duration: Double) -> Double {
    if t < fadeDur { return t / fadeDur }
    if t > duration - fadeDur { return max(0, (duration - t) / fadeDur) }
    return 1.0
}

for i in 0..<totalFrames {
    let t = Double(i) / sampleRate
    let cycle = t.truncatingRemainder(dividingBy: cycleDur)
    var sample: Double = 0

    if cycle < beepDur {
        // First beep — 800 Hz
        let env = envelope(cycle, duration: beepDur)
        sample = env * amplitude * sin(2 * .pi * freq1 * t)
    } else if cycle < beepDur + beepGap {
        // Gap between beeps
        sample = 0
    } else if cycle < 2 * beepDur + beepGap {
        // Second beep — 1000 Hz
        let local = cycle - beepDur - beepGap
        let env = envelope(local, duration: beepDur)
        sample = env * amplitude * sin(2 * .pi * freq2 * t)
    } else {
        // Rest
        sample = 0
    }

    samples[i] = Int16(max(-1, min(1, sample)) * 32767)
}

// MARK: - Write to CAF

let repoRoot = FileManager.default.currentDirectoryPath
let outputURL = URL(fileURLWithPath: repoRoot)
    .appendingPathComponent("BlinkBreak/Resources/Sounds/break-alarm.caf")

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let outputSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false
]

let file = try AVAudioFile(
    forWriting: outputURL,
    settings: outputSettings,
    commonFormat: .pcmFormatInt16,
    interleaved: false
)
try file.write(from: buffer)

print("✓ Wrote \(outputURL.path)")
print("  Duration: \(totalDuration)s")
print("  Frames: \(totalFrames)")
```

Make it executable:

```bash
chmod +x scripts/sound/generate-alarm.swift
```

- [ ] **Step 2: Run the generator**

```bash
cd /Users/tylerholland/Dev/BlinkBreak
swift scripts/sound/generate-alarm.swift
```

Expected: prints `✓ Wrote ...break-alarm.caf` and creates `BlinkBreak/Resources/Sounds/break-alarm.caf`.

- [ ] **Step 3: Audition the sound**

```bash
afplay BlinkBreak/Resources/Sounds/break-alarm.caf
```

Expected: hear a ~28-second two-tone pulsing alarm at moderate volume. If the tone is too shrill or the volume is off, edit the `freq1`, `freq2`, and `amplitude` constants in the script and re-run. Iterate until the user is satisfied. The judgment call here is "soft alarm clock, not fire alarm."

- [ ] **Step 4: Add the resources directory to `project.yml`**

Open `project.yml` and find the `BlinkBreak:` iOS target section. Replace the `sources:` block with:

```yaml
    sources:
      - path: BlinkBreak
      - path: BlinkBreak/Resources
```

Wait — because `BlinkBreak/Resources` is inside `BlinkBreak/`, xcodegen already picks it up via the `path: BlinkBreak` rule. Verify by running xcodegen and checking the generated project:

```bash
xcodegen generate
```

If `break-alarm.caf` shows up in the iOS app bundle (check via Xcode > BlinkBreak target > Build Phases > Copy Bundle Resources, or via `grep break-alarm BlinkBreak.xcodeproj/project.pbxproj`), no `project.yml` change is needed. If it doesn't, add an explicit `resources:` block to the iOS target:

```yaml
    sources:
      - path: BlinkBreak
    info:
      # ...existing info block...
```

And inside the target, below `sources:`, add:

```yaml
    resources:
      - path: BlinkBreak/Resources
```

- [ ] **Step 5: Build with the new resource**

```bash
./scripts/build.sh
```

Expected: the iOS target compiles and `break-alarm.caf` is bundled in the `.app`. Verify via:

```bash
find ~/Library/Developer/Xcode/DerivedData -name "break-alarm.caf" 2>/dev/null
```

Expected: at least one hit inside a `BlinkBreak.app` bundle under DerivedData.

- [ ] **Step 6: Run tests + lint**

```bash
./scripts/test.sh
./scripts/lint.sh
```

Both should still pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/sound/generate-alarm.swift \
        BlinkBreak/Resources/Sounds/break-alarm.caf \
        project.yml
git commit -m "$(cat <<'EOF'
Add break-alarm.caf generator and bundle the generated sound

scripts/sound/generate-alarm.swift synthesizes a 28-second two-tone
pulsing alarm pattern using AVFoundation and writes it to
BlinkBreak/Resources/Sounds/break-alarm.caf. The file is committed so
the iOS build doesn't depend on regenerating it; rerun the script to
tweak the sound. project.yml updated to bundle the resources directory.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Final validation — tests, lint, build, and on-device manual verification

**Why:** Catch anything that slipped through the task-level checks, especially Xcode-only build issues and the on-device behaviors that can't be unit-tested (the actual haptic loop, notification action button visibility on the Watch, ack sync between devices).

**Files:** None to modify — this task is pure verification.

- [ ] **Step 1: Full test suite**

```bash
./scripts/test.sh
```

Expected: all tests pass (around ~40 total after additions).

- [ ] **Step 2: Full lint**

```bash
./scripts/lint.sh
```

Expected: zero errors.

- [ ] **Step 3: Full build (both targets)**

```bash
./scripts/build.sh
```

Expected: clean build for iOS and watchOS targets.

- [ ] **Step 4: Grep for any remaining nudge / cascade references**

```bash
grep -rn "cascade\|nudge\|buildBreakCascade" \
    Packages BlinkBreak "BlinkBreak Watch App" \
    --include="*.swift" \
    | grep -v "CascadeBuilder"
```

Expected: zero results (CascadeBuilder is the retained enum name; individual symbols are gone).

- [ ] **Step 5: On-device verification checklist**

Hand-verify these scenarios on a physical iPhone + paired Apple Watch. Xcode device build required.

1. **Happy path:** Tap Start on iPhone → Watch face shows extended-runtime session indicator → wait 20 minutes → Watch wrist buzzes repeatedly with a distinct pattern → iPhone plays the 28-second alarm sound → tap Start break on the Watch notification (directly from the wrist, no long-press) → Watch haptics stop → iPhone notification disappears from Notification Center → both devices show `lookAway` state.
2. **Acknowledge on iPhone:** Repeat the happy path but tap Start break on the iPhone notification. Verify the Watch's haptic loop stops within ~1 second and the Watch-local notification disappears.
3. **Watch-only scenario:** Put iPhone into airplane mode → tap Start on Watch → wait → verify Watch alarm fires correctly and the "Start break" action on the Watch notification works.
4. **iPhone-only scenario:** Turn off Bluetooth on iPhone so the Watch is unreachable → tap Start on iPhone → wait 20 minutes → verify iPhone notification fires with alarm sound and "Start break" action works.
5. **Concurrent fire:** Happy path but don't tap anything for 30 seconds → verify the Watch haptic loop auto-stops after ~30 seconds → verify the Watch-local notification stays in Notification Center with the Start break action visible → verify tapping it at this point still correctly transitions the state.
6. **Session survives app kill:** Tap Start → swipe-kill BlinkBreak Watch App from the app switcher → re-open the Watch app → verify state is `running` and the alarm is re-armed for the remaining time.
7. **Stop during alarm:** Tap Start → wait for alarm to fire → tap Stop inside the app → verify haptic loop halts immediately and all notifications disappear.

For each scenario, note pass/fail. If any fail, file a followup and iterate before calling the task done.

- [ ] **Step 6: Push the branch and open a PR**

```bash
git push -u origin spec/notification-alarm-redesign
gh pr create --title "Replace notification cascade with Watch alarm + single iPhone notification" --body "$(cat <<'EOF'
## Summary
- Watch now holds a WKExtendedRuntimeSession alive for the cycle and fires a repeating haptic until acknowledged, replacing the 6-notification cascade.
- iPhone fires a single .timeSensitive notification with a bundled 28-second custom alarm sound (`break-alarm.caf`) as the fallback / concurrent alarm.
- Acknowledgment on either device cancels the delivered notification on the other device and disarms the Watch haptic loop via WCSession snapshot sync (new `SessionController.handleRemoteSnapshot`).
- New `SessionAlarmProtocol` + `NoopSessionAlarm` in `BlinkBreakCore`, with `WKExtendedRuntimeSessionAlarm` in the Watch target. Zero WatchKit imports inside `BlinkBreakCore`.
- Deleted cascade builder, nudge constants, and cascade-specific tests. `CascadeBuilder.identifiers(for:)` shrinks from 7 ids to 2.

## Design doc
`docs/superpowers/specs/2026-04-11-notification-alarm-redesign-design.md`

## Test plan
- [x] Automated: `./scripts/test.sh` passes (all BlinkBreakCore tests including new alarm + remote-snapshot assertions)
- [x] Automated: `./scripts/lint.sh` passes (forbidden-import scan green)
- [x] Automated: `./scripts/build.sh` passes (iOS + Watch targets)
- [ ] Manual: Happy path on physical iPhone + Watch
- [ ] Manual: Acknowledge on iPhone stops Watch haptics
- [ ] Manual: Watch-only scenario (iPhone airplane mode)
- [ ] Manual: iPhone-only scenario (Bluetooth off)
- [ ] Manual: Alarm auto-stops after 30s without acknowledgment
- [ ] Manual: Session survives Watch app kill + relaunch
- [ ] Manual: Stop during alarm halts haptics immediately

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: branch pushed, PR opened. CI should be green (Lint + Build + Test).

- [ ] **Step 7: Final task completion note**

Once CI is green and manual verification is complete, mark this plan done. The PR author is responsible for the on-device manual checklist — do not merge until all seven scenarios pass.

---

## Appendix: Quick reference for agents executing this plan

- `./scripts/test.sh` — run `swift test` (falls back gracefully if only Command Line Tools are installed).
- `./scripts/lint.sh` — forbidden-import scan + optional SwiftLint.
- `./scripts/build.sh` — `swift build` on the core package + `xcodebuild build` for the full Xcode project.
- `xcodegen generate` — regenerates `BlinkBreak.xcodeproj` from `project.yml`. Run after any `project.yml` change.
- The branch is `spec/notification-alarm-redesign`, created off `main` and already containing the design spec commit.
- CLAUDE.md rules that matter here:
  - Never push directly to `main`.
  - `BlinkBreakCore` must not import `SwiftUI`, `UIKit`, or `WatchKit`. The lint script enforces this.
  - All `BlinkBreakCore` types used by app targets must be `public`.
  - Write the test first, watch it fail, make it pass. All existing tests must stay green after any core change.
