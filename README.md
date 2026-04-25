# BlinkBreak

> A 20-20-20 rule eye-rest reminder for iOS.

Every 20 minutes, BlinkBreak tells you to look at something 20 feet away for 20 seconds. The reminder is delivered as a full-screen AlarmKit takeover that plays at alarm volume regardless of silent switch, Focus, or DND — so it's hard to miss while you're gaming or working at a PC.

## For Flutter developers new to iOS

The project is deliberately structured to make Swift/SwiftUI easier to learn if you're coming from Flutter. The map of rough analogues:

| Swift/SwiftUI concept | Flutter analogue |
| --- | --- |
| `@main App` struct | `void main() { runApp(MyApp()); }` + `MaterialApp` |
| `View` protocol (struct with a `body`) | `StatelessWidget` with a `build` method |
| `@State` | `setState` in a `StatefulWidget` |
| `@StateObject` / `@ObservedObject` + `@Published` | `ChangeNotifier` + `Provider` + `Consumer` |
| `@EnvironmentObject` | Top-level `InheritedWidget` / `Provider.of(context)` |
| Local Swift Package | Local `path:` dependency in `pubspec.yaml` |
| XCTest / Swift Testing | `flutter_test` with `test()` / `expect()` |
| SwiftUI `#Preview` | Flutter's `WidgetbookUseCase` / `flutter_preview` |
| `AlarmKit` / `AlarmManager.shared` | `flutter_local_notifications` with full-screen intent |

## Architecture

Two software units, each with one clear purpose:

```
BlinkBreak/
├── Packages/BlinkBreakCore/        ← all business logic (Swift Package)
├── BlinkBreak/                     ← iOS app target (SwiftUI views + glue)
└── BlinkBreakTests/                ← iOS-scheme test target (hosts BlinkBreakCore tests)
```

**`BlinkBreakCore`** is a local Swift Package that contains everything non-UI: the session state machine, the `AlarmSchedulerProtocol` abstraction, persistence, and the `SessionController` that coordinates them. It has **zero UI framework imports** — no `SwiftUI`, no `UIKit`, no `WatchKit`, and no `AlarmKit`. This is a hard rule enforced by `scripts/lint.sh`.

**`BlinkBreak`** (iOS) imports `BlinkBreakCore` and contains only SwiftUI views, the concrete `AlarmKitScheduler`, and tiny `AppDelegate` plumbing. Views depend on `SessionControllerProtocol`, never on the concrete class, so `PreviewSessionController` can render any state in SwiftUI previews without running real alarms.

See [`docs/superpowers/specs/2026-04-10-blinkbreak-design.md`](docs/superpowers/specs/2026-04-10-blinkbreak-design.md) for the original design document. Note that parts of it describe the pre-AlarmKit architecture (WatchConnectivity, notification cascade); the current implementation is AlarmKit-driven — see the "Alarming system" section below for the up-to-date description.

## Prerequisites

### Required

- **Full Xcode.app** (not just Command Line Tools). Install from the Mac App Store, then:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app
  ```
  You can verify with `xcode-select -p` — it should say `/Applications/Xcode.app/Contents/Developer`, NOT `/Library/Developer/CommandLineTools`.

- **[xcodegen](https://github.com/yonaskolb/XcodeGen)** for generating the Xcode project:
  ```bash
  brew install xcodegen
  ```

- **[SwiftLint](https://github.com/realm/SwiftLint)** (optional but recommended):
  ```bash
  brew install swiftlint
  ```

### Apple Developer Program

You'll need an [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/yr) to use TestFlight and to get 1-year provisioning profiles. Free personal-team signing works for local development but the app stops running after 7 days — not a good fit for a daily-driver tool.

## Getting started

```bash
# 1. Clone the repo
git clone https://github.com/TytaniumDev/BlinkBreak.git
cd BlinkBreak

# 2. Generate the Xcode project
xcodegen generate

# 3. Open in Xcode
open BlinkBreak.xcodeproj

# 4. In Xcode: select the BlinkBreak scheme, pick a simulator or device, and hit ▶
```

On first launch, the app asks for AlarmKit permission. Grant it — BlinkBreak does not work without alarms.

## Running tests

BlinkBreakCore tests can run two ways:

### Package-level (works with Command Line Tools only)

```bash
./scripts/test.sh
```

This runs `swift test` inside `Packages/BlinkBreakCore/`. It's fast (tests complete in under a second) and doesn't need a simulator. Use this while iterating on business logic.

### Xcode-scheme level (requires full Xcode)

```bash
xcodegen generate
xcodebuild test -project BlinkBreak.xcodeproj -scheme BlinkBreak \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

This is what CI runs. Requires a full Xcode install and an iOS simulator.

## Linting

```bash
./scripts/lint.sh
```

Two checks:
1. **Forbidden import scan** — fails if any file under `Packages/BlinkBreakCore/Sources/` imports `SwiftUI`, `UIKit`, or `WatchKit`. This is the structural guarantee that business logic never touches UI frameworks.
2. **SwiftLint** — runs if installed; skipped with a note if not.

## TestFlight deployment

TestFlight deploys run automatically on push to `main` via `.github/workflows/deploy-testflight.yml`. The workflow uses Fastlane + match + pilot; secrets are centralized in Doppler (project `blinkbreak`, config `prd`) and pulled into the job at runtime.

The only GitHub repo secret required is `DOPPLER_TOKEN`. Doppler holds everything else:

- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_CONTENT`, `ASC_API_KEY_IS_BASE64` — App Store Connect API key (App Manager role)
- `MATCH_PASSWORD` — AES key for the `TytaniumDev/BlinkBreak-certificates` repo
- `MATCH_SSH_PRIVATE_KEY` — deploy key for that certs repo
- `MATCH_KEYCHAIN_PASSWORD` — ephemeral CI keychain password
- `SENTRY_AUTH_TOKEN` — Sentry release/dSYM upload token (used by fastlane-plugin-sentry)

To seed signing assets the first time, run `fastlane seed_certs` locally (see `fastlane/Fastfile`). After that, every push to `main` archives with the Distribution profile from match and uploads to TestFlight.

## State machine

```
       ┌──────┐
       │ idle │◄──────┐
       └──────┘       │
          │           │
        Start      Stop (from any state)
          │           │
          ▼           │
      ┌─────────┐     │
  ┌──►│ running │─────┤
  │   └─────────┘     │
  │      │            │
  │      │ break-due alarm fires (20 min)
  │      ▼            │
  │  ┌───────────────┐│
  │  │ breakPending  ├┤
  │  └───────────────┘│
  │      │            │
  │      │ user taps "Start break"
  │      ▼            │
  │  ┌──────────────┐ │
  │  │ breakActive  │─┘
  │  └──────────────┘
  │      │
  │      │ look-away alarm fires (20 sec) + dismissed
  │      ▼
  └──────┘
```

## Alarming system

BlinkBreak's alarming is a two-beat cycle driven by **AlarmKit** (iOS 26.1+). The full-screen alarm takeover fires at alarm volume regardless of silent switch, Focus, or DND. There are only ever two alarm kinds:

- `.breakDue` — a 20-minute countdown. Fires at the end of a `running` cycle.
- `.lookAwayDone` — a 20-second countdown. Fires at the end of a `breakActive` window.

Only one alarm is scheduled at a time. Each beat ends in dismissal, which schedules the next beat.

### Layer map

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              SwiftUI Views                                 │
│  RunningView / BreakPendingView / BreakActiveView / IdleView               │
│       │                                             ▲                      │
│       │ start() / stop() /                          │ state (@Published)  │
│       │ acknowledgeCurrentBreak()                   │                      │
└───────┼─────────────────────────────────────────────┼──────────────────────┘
        ▼                                             │
┌────────────────────────────────────────────────────────────────────────────┐
│                   SessionController (BlinkBreakCore)                       │
│   - Owns SessionState, publishes to views                                  │
│   - Subscribes once to alarmScheduler.events at init                       │
│   - Persists SessionRecord to UserDefaults on every transition             │
│   - reconcile() rebuilds state from persistence + scheduler + clock        │
└───────┬───────────────────────────────────────────────────▲────────────────┘
        │ scheduleCountdown / cancel / cancelAll            │ AlarmEvent stream
        ▼                                                   │ (.fired / .dismissed)
┌────────────────────────────────────────────────────────────────────────────┐
│               AlarmKitScheduler (iOS app target)                           │
│   - The only file that imports AlarmKit                                    │
│   - Observer task: `for await alarms in AlarmManager.shared.alarmUpdates`  │
│   - Maintains id→kind mapping persisted to UserDefaults (survives kill)    │
│   - Translates AlarmKit snapshots → AlarmEvent vocabulary                  │
└───────┬──────────────────────────────────────────▲─────────────────────────┘
        │ schedule / cancel                        │ alarmUpdates AsyncSequence
        ▼                                          │
┌────────────────────────────────────────────────────────────────────────────┐
│                      iOS / AlarmKit (system)                               │
│   AlarmManager.shared — the actual alarm daemon. Persists across app kill. │
└────────────────────────────────────────────────────────────────────────────┘
```

### Happy path: full cycle from Start to next Start

```
User taps Start on IdleView
  │
  ▼
SessionController.start()
  │
  ├─► alarmScheduler.cancelAll()                    (clears any lingering alarms)
  ├─► alarmScheduler.scheduleCountdown(
  │       duration: 20 min, kind: .breakDue)        → AlarmManager.schedule(.fixed(now+20min))
  │       returns alarmId
  ├─► persistence.save(SessionRecord{ sessionActive, cycleStartedAt=now,
  │                                   currentAlarmId=alarmId })
  └─► state = .running(cycleStartedAt: now)         (view → RunningView with countdown ring)

  ... 20 minutes elapse, AlarmKit fires the alarm ...

AlarmKit: full-screen takeover appears (Stop slider + "Start break" secondary button)
AlarmKit: AlarmManager.shared.alarmUpdates emits snapshot where the alarm state=alerting
  │
  ▼
AlarmKitScheduler observer sees nowAlerting grew by alarmId
  └─► eventContinuation.yield(.fired(alarmId, .breakDue))
        │
        ▼
SessionController.handleAlarmEvent(.fired(_, .breakDue))
  └─► state = .breakPending(cycleStartedAt)         (if app foregrounded → BreakPendingView)

  User taps "Start break" — two equivalent paths:
  ┌──────────────────────────────────────┬────────────────────────────────────────┐
  │  Path A: on the AlarmKit alarm UI    │  Path B: on the in-app BreakPendingView │
  │                                      │                                         │
  │  StartBreakIntent.perform() runs     │  View calls                             │
  │  AlarmManager.shared.cancel(id)      │  controller.acknowledgeCurrentBreak()   │
  │                                      │    └─► alarmScheduler.cancel(alarmId)   │
  │                                      │    └─► synthesize .dismissed event      │
  └──────────────────────────────────────┴────────────────────────────────────────┘
        │
        ▼ (either path)
AlarmKit: alarmUpdates emits snapshot without the alarm
AlarmKitScheduler observer sees lastKnown - nowKnown = { alarmId }
  └─► eventContinuation.yield(.dismissed(alarmId, .breakDue))
        │
        ▼
SessionController.handleAlarmEvent(.dismissed(_, .breakDue))
  │
  ├─► alarmScheduler.scheduleCountdown(
  │       duration: 20 sec, kind: .lookAwayDone)    → AlarmManager.schedule(.fixed(now+20s))
  │       returns lookAwayAlarmId
  ├─► persistence.save(record with breakActiveStartedAt=now, currentAlarmId=lookAwayId)
  └─► state = .breakActive(startedAt: now)          (view → BreakActiveView)

  ... 20 seconds elapse, AlarmKit fires the look-away alarm ...

AlarmKit: full-screen takeover appears (Stop slider only — no secondary button)
Observer yields .fired(lookAwayId, .lookAwayDone)
  └─► SessionController.handleFired(.lookAwayDone) is a no-op;
      state stays .breakActive until dismissal

User slides Stop (or app dismisses programmatically via stop())
Observer yields .dismissed(lookAwayId, .lookAwayDone)
  │
  ▼
SessionController.handleAlarmEvent(.dismissed(_, .lookAwayDone))
  │
  ├─► alarmScheduler.scheduleCountdown(
  │       duration: 20 min, kind: .breakDue)        → next cycle's alarm
  ├─► persistence.save(new cycle record)
  └─► state = .running(cycleStartedAt: now)         (loop back to top)
```

### Where the source of truth lives

The app trusts three collaborators in a strict hierarchy:

1. **AlarmKit (`AlarmManager.shared`)** — source of truth for *"what's scheduled right now."* Survives app kill, OS reboot, and background termination. `reconcile()` always asks the scheduler first.
2. **`SessionRecord` in UserDefaults** — source of truth for *"what cycle is this."* Stores `cycleStartedAt`, `breakActiveStartedAt`, `currentAlarmId`, `wasAutoStarted`. Lets reconciliation interpret what the scheduler reports.
3. **`@Published state`** — derived, ephemeral, never trusted. Rebuilt by `reconcile()` on launch / foreground / periodic tick from the two sources above.

### Reconciliation on launch

`SessionController.reconcile()` runs on app launch, on foreground, and when a BGTask schedule-check fires. It never trusts in-memory state; it asks:

- Is there a persisted record with `sessionActive == true`?
- What does `alarmScheduler.currentAlarms()` report?
- Does the persisted `currentAlarmId` match one of those? Is it alerting?

From those three bits it derives the correct `SessionState`. Edge cases:

- **Alarm alerting, not dismissed** → `.breakPending` (if `.breakDue`) or stay in `.breakActive` (if `.lookAwayDone`).
- **Alarm scheduled, not yet fired** → `.running` or `.breakActive` based on `breakActiveStartedAt`.
- **Alarm missing, inside breakActive window per persistence** → `.breakActive` (we were killed mid-break, recover).
- **Alarm missing, past the break-fire time** → `.breakPending` (alarm fired while we were dead, user never ack'd).
- **Alarm missing, no recovery signal** → hard reset to `.idle` (system lost the alarm somehow).

### Why the AlarmKit observer is the pivot

Both the system (user slides Stop) and the app (programmatic `cancel`) dismiss alarms through the same funnel: the alarm disappears from `AlarmManager.shared.alarmUpdates`. The observer in `AlarmKitScheduler` converges every source of dismissal into one `.dismissed` event on its `AsyncStream`. `SessionController` only listens to that stream; it never cares *who* dismissed the alarm, just that it was dismissed. This is how the in-app button, the system Stop slider, and the Start-break secondary button all end up driving the same state machine.

One consequence worth noting: because the observer is the authoritative dismissal source, `acknowledgeCurrentBreak()` (which is called from the in-app `BreakPendingView` button) cancels the alarm *and* synthesizes its own `.dismissed` event, because the observer and the synthesized event race — the guard in `handleDismissed` (matching `record.currentAlarmId`) swallows whichever one loses.

## Directory layout

```
BlinkBreak/
├── .github/workflows/              GitHub Actions CI/CD
├── scripts/                        lint.sh, build.sh, test.sh
├── project.yml                     xcodegen spec (source of truth for Xcode project)
├── BlinkBreak/                     iOS app target (SwiftUI)
│   ├── BlinkBreakApp.swift         @main entry point
│   ├── AppDelegate.swift           BGTaskScheduler handler (UIApplicationDelegate)
│   ├── Preview/
│   │   └── PreviewSessionController.swift   mock for SwiftUI previews
│   └── Views/
│       ├── RootView.swift                   state router
│       ├── IdleView.swift
│       ├── RunningView.swift
│       ├── BreakPendingView.swift
│       ├── BreakActiveView.swift
│       ├── PermissionDeniedView.swift
│       └── Components/                      reusable small components
├── BlinkBreakTests/                iOS scheme test target
├── Packages/
│   └── BlinkBreakCore/             local Swift Package (all business logic)
│       ├── Package.swift
│       ├── Sources/BlinkBreakCore/
│       └── Tests/BlinkBreakCoreTests/
└── docs/superpowers/
    ├── specs/                      design documents
    └── plans/                      implementation plans
```

## License

MIT — see [LICENSE](LICENSE).
