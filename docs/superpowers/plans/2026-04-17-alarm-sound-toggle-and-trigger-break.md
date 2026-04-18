# Alarm Sound Toggle + "Take Break Now" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an alarm-sound mute toggle (visible in both IdleView and RunningView, rescheduling the current alarm immediately when changed) and a "Take break now" button in RunningView that fires the break alarm in ~1 second.

**Architecture:** `muteAlarmSound` is a `@Published` property on `SessionController`, persisted via `PersistenceProtocol` (same pattern as `weeklySchedule`). `scheduleCountdown()` gains a `muteSound: Bool` parameter passed through from the controller. `triggerBreakNow()` cancels the current alarm and reschedules it for 1 second. A new `SoundToggleRow` stateless component renders the toggle in both views.

**Tech Stack:** Swift 5.9, SwiftUI, BlinkBreakCore (local package), Swift Testing framework, AlarmKit (iOS 26.1)

---

## File Map

| Action | File |
|--------|------|
| Create | `BlinkBreak/Resources/Sounds/break-alarm-silent.caf` |
| Modify | `Packages/BlinkBreakCore/Sources/BlinkBreakCore/AlarmScheduler.swift` |
| Modify | `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift` |
| Modify | `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Persistence.swift` |
| Modify | `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift` |
| Modify | `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift` |
| Modify | `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockAlarmScheduler.swift` |
| Modify | `BlinkBreak/AlarmKitScheduler.swift` |
| Modify | `BlinkBreak/Preview/PreviewSessionController.swift` |
| Modify | `BlinkBreak/Views/RunningView.swift` |
| Modify | `BlinkBreak/Views/IdleView.swift` |
| Create | `BlinkBreak/Views/Components/SoundToggleRow.swift` |

---

## Task 1: Generate the silent audio file

**Files:**
- Create: `BlinkBreak/Resources/Sounds/break-alarm-silent.caf`

- [ ] **Step 1: Generate the file using macOS built-in tools**

```bash
python3 -c "
import wave
with wave.open('/tmp/silence.wav', 'w') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(44100)
    wf.writeframes(b'\x00\x00' * 44100)
"
afconvert -f caff -d LEI16@44100 /tmp/silence.wav BlinkBreak/Resources/Sounds/break-alarm-silent.caf
```

- [ ] **Step 2: Verify the file was created**

```bash
ls -lh BlinkBreak/Resources/Sounds/
```

Expected: both `break-alarm.caf` and `break-alarm-silent.caf` present.

- [ ] **Step 3: Commit**

```bash
git add BlinkBreak/Resources/Sounds/break-alarm-silent.caf
git commit -m "feat: add silent alarm audio file for mute setting"
```

---

## Task 2: Add mute sound persistence to `PersistenceProtocol`

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Persistence.swift`
- Test: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift`

- [ ] **Step 1: Add the UserDefaults key to Constants**

In `Constants.swift`, add after `weeklyScheduleKey`:

```swift
/// UserDefaults key for the persisted alarm-sound mute preference. Stored
/// separately from the session record so it survives session resets.
public static let alarmSoundMutedKey = "BlinkBreak.MuteAlarmSound"
```

- [ ] **Step 2: Write the failing test**

Open `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift` and add at the end of the file (before the closing `}`):

```swift
// MARK: - Alarm sound mute

@Test("InMemoryPersistence.loadAlarmSoundMuted() defaults to false")
func inMemoryMutedDefaultsFalse() {
    let p = InMemoryPersistence()
    #expect(p.loadAlarmSoundMuted() == false)
}

@Test("InMemoryPersistence round-trips alarm sound muted flag")
func inMemoryMutedRoundTrip() {
    let p = InMemoryPersistence()
    p.saveAlarmSoundMuted(true)
    #expect(p.loadAlarmSoundMuted() == true)
    p.saveAlarmSoundMuted(false)
    #expect(p.loadAlarmSoundMuted() == false)
}
```

- [ ] **Step 3: Run tests to confirm compile failure**

```bash
./scripts/test.sh
```

Expected: compile error — `value of type 'InMemoryPersistence' has no member 'loadAlarmSoundMuted'`

- [ ] **Step 4: Add the methods to `PersistenceProtocol` and both implementations**

In `Persistence.swift`, add to `PersistenceProtocol` after `saveSchedule`:

```swift
/// Load the persisted alarm-sound mute preference. Returns `false` (sound on) if
/// never saved.
func loadAlarmSoundMuted() -> Bool

/// Persist the alarm-sound mute preference.
func saveAlarmSoundMuted(_ muted: Bool)
```

In `UserDefaultsPersistence`, add after `saveSchedule`:

```swift
public func loadAlarmSoundMuted() -> Bool {
    defaults.bool(forKey: BlinkBreakConstants.alarmSoundMutedKey)
}

public func saveAlarmSoundMuted(_ muted: Bool) {
    defaults.set(muted, forKey: BlinkBreakConstants.alarmSoundMutedKey)
}
```

In `InMemoryPersistence`, add the stored property after `private var schedule: WeeklySchedule?`:

```swift
private var alarmSoundMuted: Bool = false
```

Then add the methods after `saveSchedule`:

```swift
public func loadAlarmSoundMuted() -> Bool {
    lock.lock(); defer { lock.unlock() }
    return alarmSoundMuted
}

public func saveAlarmSoundMuted(_ muted: Bool) {
    lock.lock(); defer { lock.unlock() }
    alarmSoundMuted = muted
}
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
./scripts/test.sh
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift \
        Packages/BlinkBreakCore/Sources/BlinkBreakCore/Persistence.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift
git commit -m "feat: add alarm sound mute persistence to PersistenceProtocol"
```

---

## Task 3: Add `muteSound` parameter to `scheduleCountdown()` across the stack

This is a breaking change to `AlarmSchedulerProtocol`. All conformances must be updated in the same commit or the build won't compile. There are no new tests in this task — the change is structural. Existing tests must still pass after this step.

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/AlarmScheduler.swift`
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockAlarmScheduler.swift`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`
- Modify: `BlinkBreak/AlarmKitScheduler.swift`

- [ ] **Step 1: Update `AlarmSchedulerProtocol.scheduleCountdown()` signature**

In `AlarmScheduler.swift`, change the `scheduleCountdown` declaration:

```swift
/// Schedule a countdown alarm that fires after `duration` seconds.
/// Returns the UUID assigned to the new alarm (callers should persist this
/// for cancellation and event-correlation).
/// - Parameter muteSound: When true, the alarm fires silently (full-screen UI
///   still appears, no audio). Uses the bundled silent CAF file.
func scheduleCountdown(duration: TimeInterval, kind: AlarmKind, muteSound: Bool) async throws -> UUID
```

- [ ] **Step 2: Update `MockAlarmScheduler`**

In `MockAlarmScheduler.swift`, update `ScheduleCall` to include `muteSound`:

```swift
struct ScheduleCall: Equatable {
    let alarmId: UUID
    let duration: TimeInterval
    let kind: AlarmKind
    let muteSound: Bool
}
```

Update the `scheduleCountdown` implementation:

```swift
func scheduleCountdown(duration: TimeInterval, kind: AlarmKind, muteSound: Bool) async throws -> UUID {
    lock.lock()
    let id = _nextAssignedId ?? UUID()
    _nextAssignedId = nil
    _scheduled.append(ScheduleCall(alarmId: id, duration: duration, kind: kind, muteSound: muteSound))
    _currentAlarms.append(ScheduledAlarmInfo(alarmId: id, kind: kind))
    lock.unlock()
    return id
}
```

- [ ] **Step 3: Update all three `scheduleCountdown` call sites in `SessionController`**

In `SessionController.swift`, find `startSession(wasAutoStarted:)` and update the call:

```swift
alarmId = try await self.alarmScheduler.scheduleCountdown(
    duration: BlinkBreakConstants.breakInterval,
    kind: .breakDue,
    muteSound: self.muteAlarmSound
)
```

**Note:** `self.muteAlarmSound` doesn't exist yet — you'll add it in Task 4. For now, use `false` as a placeholder:

```swift
alarmId = try await self.alarmScheduler.scheduleCountdown(
    duration: BlinkBreakConstants.breakInterval,
    kind: .breakDue,
    muteSound: false
)
```

In `handleDismissed(alarmId:kind:)`, update the `.breakDue` case's scheduling call:

```swift
lookAwayAlarmId = try await self.alarmScheduler.scheduleCountdown(
    duration: BlinkBreakConstants.lookAwayDuration,
    kind: .lookAwayDone,
    muteSound: false
)
```

In `handleDismissed(alarmId:kind:)`, update the `.lookAwayDone` case's scheduling call:

```swift
nextAlarmId = try await self.alarmScheduler.scheduleCountdown(
    duration: BlinkBreakConstants.breakInterval,
    kind: .breakDue,
    muteSound: false
)
```

- [ ] **Step 4: Update `AlarmKitScheduler`**

In `AlarmKitScheduler.swift`, update the `scheduleCountdown` signature and sound selection:

```swift
public func scheduleCountdown(duration: TimeInterval, kind: AlarmKind, muteSound: Bool) async throws -> UUID {
    let authorized = (try? await requestAuthorizationIfNeeded()) ?? false
    guard authorized else {
        throw AlarmSchedulerError.authorizationDenied
    }

    let id = UUID()
    let (alert, secondaryIntent) = Self.presentation(for: kind, alarmID: id)
    let attributes = AlarmAttributes<BlinkBreakAlarmMetadata>(
        presentation: AlarmPresentation(alert: alert),
        tintColor: .blue
    )
    let sound: AlertConfiguration.AlertSound
    if muteSound {
        sound = .named("break-alarm-silent.caf")
    } else {
        sound = BlinkBreakConstants.breakSoundFileName.map { .named($0) } ?? .default
    }
    let configuration = AlarmManager.AlarmConfiguration<BlinkBreakAlarmMetadata>.alarm(
        schedule: .fixed(Date().addingTimeInterval(duration)),
        attributes: attributes,
        stopIntent: nil,
        secondaryIntent: secondaryIntent,
        sound: sound
    )

    do {
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    } catch {
        throw AlarmSchedulerError.schedulingFailed(reason: String(describing: error))
    }

    rememberMapping(id: id, kind: kind)
    return id
}
```

- [ ] **Step 5: Run tests**

```bash
./scripts/test.sh
```

Expected: all existing tests pass (the `muteSound: false` placeholders are wired up; no behavior has changed yet).

- [ ] **Step 6: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/AlarmScheduler.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockAlarmScheduler.swift \
        Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift \
        BlinkBreak/AlarmKitScheduler.swift
git commit -m "refactor: add muteSound param to scheduleCountdown across the stack"
```

---

## Task 4: Add `muteAlarmSound` property and `updateAlarmSound(muted:)` to the controller

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`
- Modify: `BlinkBreak/Preview/PreviewSessionController.swift`
- Test: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `SessionControllerTests.swift` (before the final closing `}`):

```swift
// MARK: - muteAlarmSound / updateAlarmSound(muted:)

@Test("muteAlarmSound defaults to false")
func muteAlarmSoundDefaultsFalse() {
    let f = Fixture()
    #expect(f.controller.muteAlarmSound == false)
}

@Test("updateAlarmSound(muted:) updates the published property and persists")
func updateAlarmSoundPersists() async {
    let f = Fixture()
    f.controller.updateAlarmSound(muted: true)
    #expect(f.controller.muteAlarmSound == true)
    #expect(f.persistence.loadAlarmSoundMuted() == true)

    f.controller.updateAlarmSound(muted: false)
    #expect(f.controller.muteAlarmSound == false)
    #expect(f.persistence.loadAlarmSoundMuted() == false)
}

@Test("updateAlarmSound(muted:) while idle does not schedule or cancel any alarms")
func updateAlarmSoundWhileIdleIsNoOp() async {
    let f = Fixture()
    f.controller.updateAlarmSound(muted: true)
    await settle()
    #expect(f.alarmScheduler.scheduled.isEmpty)
    #expect(f.alarmScheduler.cancelledIds.isEmpty)
}

@Test("updateAlarmSound(muted:) while running cancels current alarm and reschedules with new muteSound")
func updateAlarmSoundWhileRunningReschedules() async {
    let f = Fixture()
    f.controller.start()
    await settle()

    let originalId = f.alarmScheduler.scheduled.last!.alarmId
    f.advance(by: 5 * 60)  // 5 minutes into the 20-minute cycle

    f.controller.updateAlarmSound(muted: true)
    await settle()

    // Original alarm cancelled
    #expect(f.alarmScheduler.cancelledIds.contains(originalId))

    // New alarm scheduled with muteSound: true and remaining duration ≈ 15 minutes
    let newCall = f.alarmScheduler.scheduled.last!
    #expect(newCall.muteSound == true)
    #expect(newCall.kind == .breakDue)
    #expect(abs(newCall.duration - 15 * 60) < 2)
}

@Test("start() passes muteAlarmSound preference through to scheduleCountdown")
func startPassesMuteSoundPreference() async {
    let f = Fixture()
    f.controller.updateAlarmSound(muted: true)
    f.controller.start()
    await settle()

    let call = f.alarmScheduler.scheduled.last!
    #expect(call.muteSound == true)
}
```

- [ ] **Step 2: Run tests to confirm compile failure**

```bash
./scripts/test.sh
```

Expected: compile error — `value of type 'SessionController' has no member 'muteAlarmSound'`

- [ ] **Step 3: Add `muteAlarmSound` and `updateAlarmSound(muted:)` to `SessionControllerProtocol`**

In `SessionControllerProtocol.swift`, add after `updateSchedule`:

```swift
/// Whether the alarm sound is muted. When true, AlarmKit alarms fire silently
/// (full-screen UI still appears). Persisted across launches.
var muteAlarmSound: Bool { get }

/// Update and persist the alarm-sound mute preference. If a session is currently
/// running, the scheduled alarm is cancelled and rescheduled immediately with the
/// new sound setting (within a few seconds).
func updateAlarmSound(muted: Bool)
```

- [ ] **Step 4: Implement in `SessionController`**

In `SessionController.swift`, add the published property after `weeklySchedule`:

```swift
/// Whether the alarm sound is muted. Loaded from persistence on init.
@Published public private(set) var muteAlarmSound: Bool = false
```

In `SessionController.init()`, after `self.weeklySchedule = persistence.loadSchedule() ?? .empty`, add:

```swift
self.muteAlarmSound = persistence.loadAlarmSoundMuted()
```

Add the `updateAlarmSound(muted:)` method after `updateSchedule`:

```swift
/// Update the alarm-sound mute preference. Reschedules the current alarm if running.
public func updateAlarmSound(muted: Bool) {
    persistence.saveAlarmSoundMuted(muted)
    muteAlarmSound = muted
    guard case .running(let cycleStartedAt) = state,
          let currentAlarmId = persistence.load().currentAlarmId else { return }
    let now = clock()
    let remaining = max(1, cycleStartedAt
        .addingTimeInterval(BlinkBreakConstants.breakInterval)
        .timeIntervalSince(now))
    Task { [weak self] in
        guard let self else { return }
        await self.alarmScheduler.cancel(alarmId: currentAlarmId)
        let newId: UUID
        do {
            newId = try await self.alarmScheduler.scheduleCountdown(
                duration: remaining,
                kind: .breakDue,
                muteSound: muted
            )
        } catch { return }
        var record = self.persistence.load()
        record.currentAlarmId = newId
        self.persistence.save(record)
    }
}
```

Replace the three `muteSound: false` placeholders added in Task 3 with `muteSound: self.muteAlarmSound`:

In `startSession(wasAutoStarted:)`:
```swift
alarmId = try await self.alarmScheduler.scheduleCountdown(
    duration: BlinkBreakConstants.breakInterval,
    kind: .breakDue,
    muteSound: self.muteAlarmSound
)
```

In `handleDismissed` `.breakDue` case:
```swift
lookAwayAlarmId = try await self.alarmScheduler.scheduleCountdown(
    duration: BlinkBreakConstants.lookAwayDuration,
    kind: .lookAwayDone,
    muteSound: self.muteAlarmSound
)
```

In `handleDismissed` `.lookAwayDone` case:
```swift
nextAlarmId = try await self.alarmScheduler.scheduleCountdown(
    duration: BlinkBreakConstants.breakInterval,
    kind: .breakDue,
    muteSound: self.muteAlarmSound
)
```

- [ ] **Step 5: Add stubs to `PreviewSessionController`**

In `PreviewSessionController.swift`, add after `@Published var weeklySchedule`:

```swift
@Published var muteAlarmSound: Bool = false
```

Add after `updateSchedule`:

```swift
func updateAlarmSound(muted: Bool) {
    muteAlarmSound = muted
}
```

- [ ] **Step 6: Run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass including the five new ones.

- [ ] **Step 7: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift \
        Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift \
        BlinkBreak/Preview/PreviewSessionController.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift
git commit -m "feat: add muteAlarmSound setting with mid-session rescheduling"
```

---

## Task 5: Add `triggerBreakNow()` to the controller

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`
- Modify: `BlinkBreak/Preview/PreviewSessionController.swift`
- Test: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `SessionControllerTests.swift`:

```swift
// MARK: - triggerBreakNow()

@Test("triggerBreakNow() while running cancels current alarm and schedules 1-second breakDue alarm")
func triggerBreakNowWhileRunning() async {
    let f = Fixture()
    f.controller.start()
    await settle()

    let originalId = f.alarmScheduler.scheduled.last!.alarmId
    f.controller.triggerBreakNow()
    await settle()

    #expect(f.alarmScheduler.cancelledIds.contains(originalId))

    let newCall = f.alarmScheduler.scheduled.last!
    #expect(newCall.duration == 1)
    #expect(newCall.kind == .breakDue)
}

@Test("triggerBreakNow() while running updates SessionRecord.currentAlarmId")
func triggerBreakNowUpdatesRecord() async {
    let f = Fixture()
    f.controller.start()
    await settle()

    let idBefore = f.persistence.load().currentAlarmId!
    f.controller.triggerBreakNow()
    await settle()

    let idAfter = f.persistence.load().currentAlarmId!
    #expect(idAfter != idBefore)
}

@Test("triggerBreakNow() while idle is a no-op")
func triggerBreakNowWhileIdleIsNoOp() async {
    let f = Fixture()
    f.controller.triggerBreakNow()
    await settle()
    #expect(f.alarmScheduler.scheduled.isEmpty)
    #expect(f.alarmScheduler.cancelledIds.isEmpty)
    #expect(f.controller.state == .idle)
}
```

- [ ] **Step 2: Run tests to confirm compile failure**

```bash
./scripts/test.sh
```

Expected: compile error — `value of type 'SessionController' has no member 'triggerBreakNow'`

- [ ] **Step 3: Add `triggerBreakNow()` to `SessionControllerProtocol`**

In `SessionControllerProtocol.swift`, add after `updateAlarmSound(muted:)`:

```swift
/// Immediately cancel the current break alarm and reschedule it to fire in
/// 1 second. Only meaningful in the `.running` state; no-op otherwise.
/// Intended for manually testing the full break-alarm transition.
func triggerBreakNow()
```

- [ ] **Step 4: Implement in `SessionController`**

Add after `updateAlarmSound(muted:)`:

```swift
/// Cancel the current alarm and reschedule it to fire in 1 second.
public func triggerBreakNow() {
    guard case .running = state,
          let currentAlarmId = persistence.load().currentAlarmId else { return }
    Task { [weak self] in
        guard let self else { return }
        await self.alarmScheduler.cancel(alarmId: currentAlarmId)
        let newId: UUID
        do {
            newId = try await self.alarmScheduler.scheduleCountdown(
                duration: 1,
                kind: .breakDue,
                muteSound: self.muteAlarmSound
            )
        } catch { return }
        var record = self.persistence.load()
        record.currentAlarmId = newId
        self.persistence.save(record)
    }
}
```

- [ ] **Step 5: Add stub to `PreviewSessionController`**

In `PreviewSessionController.swift`, add after `updateAlarmSound(muted:)`:

```swift
func triggerBreakNow() {
    // No-op in previews.
}
```

- [ ] **Step 6: Run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass including the three new ones.

- [ ] **Step 7: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift \
        Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift \
        BlinkBreak/Preview/PreviewSessionController.swift \
        Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift
git commit -m "feat: add triggerBreakNow() for immediate break triggering"
```

---

## Task 6: Create the `SoundToggleRow` component

**Files:**
- Create: `BlinkBreak/Views/Components/SoundToggleRow.swift`

- [ ] **Step 1: Create the component**

Create `BlinkBreak/Views/Components/SoundToggleRow.swift`:

```swift
//
//  SoundToggleRow.swift
//  BlinkBreak
//
//  Stateless toggle row for the alarm sound setting. Binds to the controller's
//  `muteAlarmSound` property via `updateAlarmSound(muted:)`. Toggle ON = sound enabled.
//
//  Flutter analogue: a stateless SwitchListTile-style widget that takes callbacks.
//

import SwiftUI
import BlinkBreakCore

struct SoundToggleRow<Controller: SessionControllerProtocol>: View {
    @ObservedObject var controller: Controller

    var body: some View {
        HStack {
            Text("Alarm Sound")
                .font(.subheadline.weight(.medium))
            Spacer()
            Toggle("Alarm Sound", isOn: Binding(
                get: { !controller.muteAlarmSound },
                set: { controller.updateAlarmSound(muted: !$0) }
            ))
            .labelsHidden()
            .tint(.green)
        }
    }
}

#Preview("Sound On") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        SoundToggleRow(controller: PreviewSessionController(state: .idle))
            .foregroundStyle(.white)
            .padding(24)
    }
}

#Preview("Sound Off") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        SoundToggleRow(controller: {
            let c = PreviewSessionController(state: .idle)
            c.muteAlarmSound = true
            return c
        }())
        .foregroundStyle(.white)
        .padding(24)
    }
}
```

**Note on toggle semantics:** The Toggle's `isOn` is `!controller.muteAlarmSound` because the label says "Alarm Sound" (positive framing). Toggle ON = sound enabled = `muteAlarmSound: false`.

- [ ] **Step 2: Verify the build compiles**

```bash
./scripts/test.sh
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add BlinkBreak/Views/Components/SoundToggleRow.swift
git commit -m "feat: add SoundToggleRow component for alarm sound setting"
```

---

## Task 7: Update `RunningView` with sound toggle and "Take break now" button

**Files:**
- Modify: `BlinkBreak/Views/RunningView.swift`

- [ ] **Step 1: Replace the `VStack` body in `RunningView`**

The current `VStack` contains: EyebrowLabel → CountdownRing → fire-time footnote → Spacer → Stop button.

Replace the entire `VStack(spacing: 20)` content with:

```swift
VStack(spacing: 20) {
    EyebrowLabel(text: "Next break in")

    CountdownRing(progress: progress, label: countdownLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(a11yDurationFormatter.string(from: remainingSeconds) ?? countdownLabel)
        .accessibilityIdentifier("label.running.countdown")

    Text("Fires at \(breakFireTimeFormatted)")
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.6))

    SoundToggleRow(controller: controller)
        .padding(.top, 4)

    Spacer()

    Button("Take break now") {
        controller.triggerBreakNow()
    }
    .font(.subheadline)
    .foregroundStyle(.white.opacity(0.7))
    .accessibilityIdentifier("button.running.takeBreakNow")

    Button(role: .destructive) {
        controller.stop()
    } label: {
        Text("Stop")
            .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .controlSize(.large)
    .tint(.white)
    .accessibilityIdentifier("button.running.stop")
}
.padding(24)
```

- [ ] **Step 2: Run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add BlinkBreak/Views/RunningView.swift
git commit -m "feat: add sound toggle and take-break-now button to RunningView"
```

---

## Task 8: Update `IdleView` with sound toggle

**Files:**
- Modify: `BlinkBreak/Views/IdleView.swift`

- [ ] **Step 1: Add `SoundToggleRow` below `ScheduleSection`**

In `IdleView.swift`, find the `ScheduleSection(controller: controller)` line and add the toggle row immediately after it:

```swift
ScheduleSection(controller: controller)
    .padding(.top, 12)

SoundToggleRow(controller: controller)
    .padding(.top, 8)
```

The full relevant section of `IdleView.body` should now read:

```swift
ScheduleSection(controller: controller)
    .padding(.top, 12)

SoundToggleRow(controller: controller)
    .padding(.top, 8)

Spacer()
```

- [ ] **Step 2: Run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add BlinkBreak/Views/IdleView.swift
git commit -m "feat: add sound toggle to IdleView"
```

---

## Final verification

- [ ] **Run the full unit test suite one more time**

```bash
./scripts/test.sh
```

Expected: all ~80+ tests pass.

- [ ] **Manual on-device verification checklist**

1. Toggle "Alarm Sound" off on the idle screen → start → wait for break alarm → alarm fires silently (full-screen UI, no sound)
2. Toggle "Alarm Sound" on during a running session → alarm time resets within a few seconds → next break fires with sound
3. Tap "Take break now" in RunningView → AlarmKit full-screen alarm appears within ~1 second → tap Stop → app transitions through breakActive → resumes running
4. Toggle sound off → tap "Take break now" → alarm fires silently
