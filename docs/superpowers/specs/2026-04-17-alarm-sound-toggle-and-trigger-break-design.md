# Design: Alarm Sound Toggle + "Take Break Now" Button

**Date:** 2026-04-17
**Status:** Approved

---

## Overview

Two features:

1. **Alarm Sound Toggle** — a `Bool` setting that mutes the AlarmKit alarm sound. When changed during a running session, the current alarm is cancelled and rescheduled with the updated sound preference so it takes effect immediately (within a few seconds).

2. **"Take Break Now" button** — visible in `RunningView`, cancels the current alarm and reschedules it to fire in 1 second. Visible to all users (not debug-only), allowing manual testing of the full break transition.

---

## Architecture

### BlinkBreakCore changes

**`AlarmSchedulerProtocol.scheduleCountdown()`** gains a `muteSound: Bool` parameter:

```swift
func scheduleCountdown(duration: TimeInterval, kind: AlarmKind, muteSound: Bool) async throws -> UUID
```

`SessionController` passes its persisted preference through at call sites. This keeps the scheduler stateless with respect to settings.

**`BlinkBreakConstants`** gains a new persistence key:

```swift
public static let alarmSoundMutedKey = "BlinkBreak.MuteAlarmSound"
```

**`SessionControllerProtocol`** gains three additions:

```swift
var muteAlarmSound: Bool { get }
func updateAlarmSound(muted: Bool)
func triggerBreakNow()
```

**`SessionController`** implementation:

- `muteAlarmSound` — `@Published` property, loaded from `UserDefaults` on init using `alarmSoundMutedKey` (defaults to `false`).
- `updateAlarmSound(muted:)` — persists to `UserDefaults`, updates `muteAlarmSound`. If state is `.running(let cycleStartedAt)`, computes `remainingDuration = max(1, cycleStartedAt + breakInterval - now)`, cancels the current alarm by ID from `SessionRecord.currentAlarmId`, schedules a new alarm for `remainingDuration` with the new sound setting, and updates `SessionRecord.currentAlarmId`.
- `triggerBreakNow()` — guard: only acts when state is `.running`. Cancels the current alarm and calls `scheduleCountdown(duration: 1, kind: .breakDue, muteSound: muteAlarmSound)`. Updates `SessionRecord.currentAlarmId` with the new alarm ID.

**`PreviewSessionController`** — stub implementations: `muteAlarmSound` returns `false`, `updateAlarmSound(muted:)` and `triggerBreakNow()` are no-ops.

**`MockAlarmScheduler`** (used in unit tests) — `scheduleCountdown()` signature updated to accept `muteSound: Bool`; mock records the value for test assertions.

---

### iOS app target changes

**`AlarmKitScheduler.scheduleCountdown()`** — updated signature. When `muteSound` is `true`, sets:

```swift
let sound: AlertConfiguration.AlertSound = .named("break-alarm-silent.caf")
```

When `false`, uses the existing logic (`.named("break-alarm.caf")` or `.default` in test environments).

**Silent audio file** — `break-alarm-silent.caf` is a 1-second silent CAF file bundled in the app target. It must be listed in the Xcode target's "Copy Bundle Resources" phase (handled via `project.yml`).

> **Risk/assumption:** AlarmKit will render the alarm's full-screen UI even when the audio file contains silence. The alarm will still vibrate. This is the expected and desired behavior.

**`SoundToggleRow`** — new component in `Views/Components/`. Generic over `Controller: SessionControllerProtocol` (same pattern as all other views); takes `@ObservedObject var controller: Controller` and reads `controller.muteAlarmSound` / calls `controller.updateAlarmSound(muted:)` directly. Under 50 lines. Has a `#Preview`.

```
HStack {
    Text("Alarm Sound")
    Spacer()
    Toggle("Alarm Sound", isOn: ...)
        .labelsHidden()
        .tint(.green)
}
```

**`IdleView`** — adds `SoundToggleRow` below `ScheduleSection`.

**`RunningView`** — adds `SoundToggleRow` below the countdown ring, above the "Take break now" button and Stop button.

**"Take break now" button** — secondary text-style button in `RunningView`, between `SoundToggleRow` and the Stop button:

```swift
Button("Take break now") {
    controller.triggerBreakNow()
}
.font(.subheadline)
.foregroundStyle(.white.opacity(0.7))
```

---

## Data flow

```
User taps sound toggle
  → SoundToggleRow.onToggle(muted)
  → controller.updateAlarmSound(muted:)
    → UserDefaults write
    → if .running: cancel alarm → scheduleCountdown(remaining, muteSound: muted)
    → SessionRecord.currentAlarmId updated

User taps "Take break now"
  → controller.triggerBreakNow()
    → cancel current alarm
    → scheduleCountdown(duration: 1, .breakDue, muteSound: muteAlarmSound)
    → SessionRecord.currentAlarmId updated
    → AlarmKit fires in ~1 second → existing dismissed event handling takes over
```

---

## Testing

**Unit tests** (BlinkBreakCore):
- `updateAlarmSound(muted: true)` while running → `MockAlarmScheduler` receives cancel + new schedule with `muteSound: true`
- `updateAlarmSound(muted: false)` while idle → only persists preference, no alarm ops
- `triggerBreakNow()` while running → `MockAlarmScheduler` receives cancel + 1-second schedule
- `triggerBreakNow()` while idle → no-op, state unchanged

**Manual verification** (on device):
- Toggle sound off, let a break fire → alarm screen appears silently
- Toggle sound on during a running session → within a few seconds the alarm time resets; next break fires with sound
- "Take break now" → AlarmKit full-screen alarm appears within ~1 second

**No integration test changes needed** — `BB_BREAK_INTERVAL` env var tests already run with `muteSound: false` default, so the XCUITest suite is unaffected.
