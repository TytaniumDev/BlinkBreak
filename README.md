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
| `@Observable` class | `ChangeNotifier` (views rebuild when a property they read changes) |
| `@Environment` value | `Provider.of(context)` / `InheritedWidget` |
| App Intent (`LiveActivityIntent`) | A notification-action callback in a background isolate |
| Local Swift Package | Local `path:` dependency in `pubspec.yaml` |
| Swift Testing (`@Test`, `#expect`) | `flutter_test` with `test()` / `expect()` |
| SwiftUI `#Preview` | Flutter's `WidgetbookUseCase` / `flutter_preview` |
| `AlarmKit` / `AlarmManager.shared` | `flutter_local_notifications` with full-screen intent |

## Architecture

Two software units, each with one clear purpose:

```
BlinkBreak/
├── Packages/BlinkBreakCore/        ← all business logic (Swift Package)
└── BlinkBreak/                     ← iOS app target (SwiftUI views + glue)
```

**`BlinkBreakCore`** is a local Swift Package that contains everything non-UI: the session state machine (`SessionController`), the `AlarmSchedulerProtocol` abstraction, persistence, and the weekly-schedule math. It imports nothing Apple-platform-specific — no `SwiftUI`, `UIKit`, `AlarmKit`, `AppIntents`, or `Sentry` — so it builds and tests anywhere Swift runs, including Linux. This is a hard rule enforced by `scripts/lint.sh`. It compiles in the Swift 6 language mode, so data races are compile errors.

**`BlinkBreak`** (iOS) imports `BlinkBreakCore` and contains SwiftUI views, the concrete `AlarmKitScheduler`, the two alarm-button App Intents, and the composition root (`AppEnvironment`). Views depend on `SessionControllerProtocol`, never on the concrete class, so `PreviewSessionController` can render any state in SwiftUI previews without running real alarms.

The app runs on iPhone (portrait and landscape), iPad (any size: Split View, Slide Over, Stage Manager), and Apple silicon Macs as the iPad app ("Designed for iPad"). Every screen is built on `AdaptiveScreen`, which caps content at a readable width, scrolls when the window is short, and keeps the action buttons pinned at the bottom.

See [`docs/superpowers/specs/`](docs/superpowers/specs/) for historical design documents. Parts of them describe earlier architectures (WatchConnectivity, notification cascade, event-driven cycle chaining); the "Alarming system" section below is the up-to-date description.

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

The first time you tap Start (or turn on the schedule), the app asks for AlarmKit permission. Grant it — BlinkBreak does not work without alarms.

## Running tests

### Unit tests (fast — use while iterating)

```bash
./scripts/test.sh
```

Runs `swift test` inside `Packages/BlinkBreakCore/`. Tests finish in well under a second, need no simulator, and work with Command Line Tools only — or on Linux with a Swift 6 toolchain.

### Xcode-scheme level (requires full Xcode)

```bash
BLINKBREAK_FULL_TESTS=1 ./scripts/test.sh
```

Also runs `xcodebuild test` on the `BlinkBreak` scheme in an iOS 26.1+ simulator. This is what CI runs.

### Integration tests (slow — final verification)

```bash
./scripts/test-integration.sh
```

The XCUITest suite drives the real app through a simulator (~4 minutes). See `CLAUDE.md` for what it covers.

## Linting

```bash
./scripts/lint.sh
```

Two checks:
1. **Forbidden import scan** — fails if any file under `Packages/BlinkBreakCore/Sources/` imports `SwiftUI`, `UIKit`, `WatchKit`, `AlarmKit`, `ActivityKit`, `AppIntents`, or `Sentry`. This is the structural guarantee that business logic stays platform-agnostic.
2. **SwiftLint** — runs if installed; skipped with a note if not.

## TestFlight deployment

TestFlight deploys run automatically on push to `main` via `.github/workflows/deploy-testflight.yml`. The workflow uses Fastlane + match + pilot; secrets are centralized in Doppler (project `blinkbreak`, config `prd`) and pulled into the job at runtime.

The only GitHub repo secret required is `DOPPLER_TOKEN`. Doppler holds everything else:

- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_CONTENT`, `ASC_API_KEY_IS_BASE64` — App Store Connect API key (App Manager role)
- `MATCH_PASSWORD` — AES key for the `TytaniumDev/TytaniumDev-certificates` repo
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
  │      │ break alarm fires (20 min)
  │      ▼            │
  │  ┌───────────────┐│
  │  │ breakPending  ├┤──── Stop on the alarm (skip) ──► running
  │  └───────────────┘│
  │      │            │
  │      │ "Start break" (alarm button or in-app)
  │      ▼            │
  │  ┌──────────────┐ │
  │  │ breakActive  │─┘
  │  └──────────────┘
  │      │
  │      │ look-away alarm fires (20 sec)
  │      ▼
  └──────┘
```

Inside a weekly-schedule window, a running session can also be **paused** (e.g. for a nap): no alarms ring until you tap Resume, and when the window ends the pause lapses and the schedule starts the next window as usual. Manually started sessions (and Resume) stop at the end of the current or next schedule window when the schedule is on.

`SessionState` is what the UI shows. It is derived from the persisted `SessionRecord` (phase, owned alarm ID, fire time) and the clock — never stored on its own.

## Alarming system

BlinkBreak's alarming is a two-beat cycle driven by **AlarmKit** (iOS 26.1+). The full-screen alarm takeover fires at alarm volume regardless of silent switch, Focus, or DND. There are two alarm kinds:

- `.breakDue` — fires at the end of a 20-minute `running` cycle. Buttons: **Start break** and the system **Stop** (skip this break).
- `.lookAwayDone` — fires at the end of the 20-second look-away. Buttons: **End break** and **Stop** (both continue to the next cycle).

A session owns exactly one alarm at a time.

### Who moves the cycle forward

The key design goal is that **the cycle keeps going even when iOS has killed the app**:

1. **Alarm buttons run App Intents** (`BreakButtonIntent`, `StopButtonIntent` in `AlarmIntents.swift`). iOS runs these when the user taps, launching the app process in the background if needed. They call `SessionController.respond(to:alarmId:)`, which books the next alarm immediately.
2. **While the app is alive**, `AlarmKitScheduler` diffs `AlarmManager.shared.alarmUpdates` into `.alerting` / `.removed` events. The look-away alarm ringing rolls the cycle forward on its own. An alarm that disappears with no intent reporting a tap is treated as "skipped", after a 5-second grace period so a slightly late intent still wins.
3. **`reconcile()`** runs whenever the app becomes active. It catches up on anything missed while the app was dead, cancels alarms the session doesn't own, and applies the weekly schedule.
4. **The weekly schedule pre-books** the first break alarm of the next window (e.g. 9:20 for a 9:00 start). No background execution is needed for automatic starts. When a schedule-started session reaches the end of its window, it stops and pre-books the next window.

Every transition runs on one serial queue inside `SessionController`, so a Stop tap, an intent, an alarm event, and a reconcile can never interleave across `await`s.

### Layer map

```
┌────────────────────────────────────────────┐   ┌──────────────────────────────┐
│ SwiftUI views (RootView → Idle/Running/…)  │   │ App Intents (alarm buttons)  │
│   read state; call start/stop/startBreak   │   │   respond(to:alarmId:)       │
└───────────────────┬────────────────────────┘   └──────────────┬───────────────┘
                    ▼                                           ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ SessionController (BlinkBreakCore, @Observable, one per process)             │
│   serial queue · SessionRecord in UserDefaults · derived SessionState        │
└───────────────────┬──────────────────────────────────────────▲───────────────┘
                    │ schedule / cancel / currentAlarms         │ .alerting / .removed
                    ▼                                           │
┌──────────────────────────────────────────────────────────────────────────────┐
│ AlarmKitScheduler (app target) → AlarmManager.shared (system alarm daemon)   │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Where the source of truth lives

1. **AlarmKit (`AlarmManager.shared.alarms`)** — what's actually scheduled or ringing. Survives app kill and reboot. An alarm that has fired and been stopped is deleted from it.
2. **`SessionRecord` in UserDefaults** — the session's phase, the one alarm it owns, and when that alarm fires. Enough to interpret what AlarmKit reports.
3. **`SessionState`** — derived from the two above plus the clock; never stored.

## Directory layout

```
BlinkBreak/
├── .github/workflows/              GitHub Actions CI/CD
├── scripts/                        lint.sh, build.sh, test.sh, test-integration.sh
├── project.yml                     xcodegen spec (source of truth for Xcode project)
├── BlinkBreak/                     iOS app target (SwiftUI)
│   ├── BlinkBreakApp.swift         @main entry point
│   ├── AppEnvironment.swift        composition root (the shared SessionController)
│   ├── AlarmKitScheduler.swift     AlarmKit wrapper
│   ├── AlarmIntents.swift          alarm-button App Intents
│   ├── Feedback/                   feedback reporting (Sentry)
│   ├── Preview/                    PreviewSessionController for SwiftUI previews
│   └── Views/                      screens, Theme.swift, Components/
├── BlinkBreakUITests/              XCUITest integration suite
├── Packages/
│   └── BlinkBreakCore/             local Swift Package (all business logic)
│       ├── Package.swift
│       ├── Sources/BlinkBreakCore/
│       └── Tests/BlinkBreakCoreTests/
└── docs/superpowers/               historical specs and plans
```

## License

MIT — see [LICENSE](LICENSE).
