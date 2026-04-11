# BlinkBreak

> A 20-20-20 rule eye-rest reminder for iOS and Apple Watch.

Every 20 minutes, BlinkBreak tells you to look at something 20 feet away for 20 seconds. The reminder is delivered as a 30-second alarm-style haptic cascade on your wrist so it's hard to miss while you're gaming or working at a PC.

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
| `UNUserNotificationCenter` | `flutter_local_notifications` |
| `WatchConnectivity` / `WCSession` | Platform channel between a Flutter app and a WearOS companion |

## Architecture

Three software units, each with one clear purpose:

```
BlinkBreak/
├── Packages/BlinkBreakCore/        ← all business logic (Swift Package)
├── BlinkBreak/                     ← iOS app target (SwiftUI views + glue)
├── BlinkBreak Watch App/           ← watchOS app target (SwiftUI views + glue)
└── BlinkBreakTests/                ← iOS-scheme test target (hosts BlinkBreakCore tests)
```

**`BlinkBreakCore`** is a local Swift Package that contains everything non-UI: the session state machine, the notification scheduler wrapper, the WatchConnectivity wrapper, persistence, and the `SessionController` that coordinates them. It has **zero UI framework imports** — no `SwiftUI`, no `UIKit`, no `WatchKit`. This is a hard rule enforced by `scripts/lint.sh`.

**`BlinkBreak`** (iOS) and **`BlinkBreak Watch App`** (watchOS) import `BlinkBreakCore` and contain only SwiftUI views + tiny `AppDelegate` plumbing. Views depend on the `SessionControllerProtocol`, never on the concrete class, so `PreviewSessionController` can render any state in SwiftUI previews without running real timers.

See [`docs/superpowers/specs/2026-04-10-blinkbreak-design.md`](docs/superpowers/specs/2026-04-10-blinkbreak-design.md) for the full design document — state machine, notification cascade mechanics, WatchConnectivity sync, error handling, testing strategy.

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

On first launch, the app asks for notification permission. Grant it — BlinkBreak does not work without notifications.

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

TestFlight uploads are scaffolded in `.github/workflows/deploy-testflight.yml` but **disabled by default** — only `workflow_dispatch` is wired up. To enable automatic deploys on push to `main`:

1. **Enroll in the Apple Developer Program.** $99/yr via [developer.apple.com/programs](https://developer.apple.com/programs/).
2. **Create an App Store Connect API key.** In [App Store Connect → Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/api), create a new key with "App Manager" access. Download the `.p8` file (you only get one chance).
3. **Export your Distribution certificate.** From Xcode's Signing & Capabilities tab or from Keychain Access, export the distribution certificate as a `.p12` file with a password.
4. **Base64-encode both files:**
   ```bash
   base64 -i AuthKey_XXX.p8 | pbcopy      # paste into APPSTORE_API_KEY_P8
   base64 -i Certificate.p12 | pbcopy     # paste into BUILD_CERTIFICATE_P12
   ```
5. **Set the four required secrets** in your repo: `Settings → Secrets and variables → Actions → New repository secret`:
   - `APPSTORE_API_KEY_ID` — the Key ID shown in ASC (e.g. `ABC1234567`)
   - `APPSTORE_API_ISSUER_ID` — the Issuer ID shown at the top of the Integrations page
   - `APPSTORE_API_KEY_P8` — the base64-encoded `.p8` contents
   - `BUILD_CERTIFICATE_P12` — the base64-encoded `.p12` contents
   - `BUILD_CERTIFICATE_PASSWORD` — the password you set on the `.p12` export
6. **Set your Team ID in `project.yml`.** Find it in [Apple Developer → Membership](https://developer.apple.com/account). Update the `DEVELOPMENT_TEAM` setting.
7. **Enable the deploy workflow.** In `.github/workflows/deploy-testflight.yml`, add `push: { branches: [main] }` under `on:`, and in `release.yml` uncomment the `gh workflow run deploy-testflight.yml` line in `trigger-deploy`.

After enrollment, every push to `main` will run CI, then TestFlight upload.

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
  │      │ 20-min notification fires
  │      ▼            │
  │  ┌──────────────┐ │
  │  │ breakActive  │─┤
  │  └──────────────┘ │
  │      │            │
  │      │ user taps "Start break"
  │      ▼            │
  │  ┌───────────┐    │
  │  │ lookAway  │────┘
  │  └───────────┘
  │      │
  │      │ 20-sec "done" notification fires
  │      ▼
  └──────┘
```

## Directory layout

```
BlinkBreak/
├── .github/workflows/              GitHub Actions CI/CD
├── scripts/                        lint.sh, build.sh, test.sh
├── project.yml                     xcodegen spec (source of truth for Xcode project)
├── BlinkBreak/                     iOS app target (SwiftUI)
│   ├── BlinkBreakApp.swift         @main entry point
│   ├── AppDelegate.swift           UNUserNotificationCenterDelegate
│   ├── Preview/
│   │   └── PreviewSessionController.swift   mock for SwiftUI previews
│   └── Views/
│       ├── RootView.swift                   state router
│       ├── IdleView.swift
│       ├── RunningView.swift
│       ├── BreakActiveView.swift
│       ├── LookAwayView.swift
│       ├── PermissionDeniedView.swift
│       └── Components/                      reusable small components
├── BlinkBreak Watch App/           watchOS app target
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
