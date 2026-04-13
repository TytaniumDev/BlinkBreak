# Bug Report Feature — Design Spec

**Date:** 2026-04-12
**Status:** Approved

## Overview

Add shake-to-report bug reporting to BlinkBreak's TestFlight builds. On shake, the user enters a description, and the app automatically creates a GitHub issue with PII-free diagnostic data attached. Production App Store builds ignore the shake gesture entirely.

## Requirements

- Triggered by shake gesture (iOS only, no UI changes)
- TestFlight-only — gated at runtime via sandbox receipt URL check
- Automatically creates a GitHub issue on `TytaniumDev/BlinkBreak`
- Diagnostic payload is PII-free: no user name, Apple ID, device name, IP, location, or notification content
- Includes an extensible in-memory log buffer so future logging calls are automatically captured
- Fire-and-forget UX: description prompt → send → brief confirmation toast

## Architecture

### 1. LogBuffer (BlinkBreakCore)

Thread-safe in-memory ring buffer. Fixed capacity of 500 entries. Each entry:

```swift
public struct LogEntry: Codable, Sendable {
    public let timestamp: Date
    public let level: LogLevel  // debug, info, warning, error
    public let message: String
}
```

Static `LogBuffer.shared` instance for convenience. Code throughout BlinkBreakCore writes to it:

```swift
LogBuffer.shared.log(.info, "reconcile: rebuilt state from persisted record")
```

`drain() -> [LogEntry]` returns all buffered entries. Oldest entries evict when the buffer is full.

No PII by convention — log messages are developer-written strings about app behavior. Enforced by code review, not runtime scrubbing.

Injectable for tests: `LogBuffer(capacity:)` creates isolated instances.

### 2. DiagnosticCollector (BlinkBreakCore)

Pure function: dependencies in, `DiagnosticReport` out.

```swift
public struct DiagnosticReport: Codable, Sendable {
    public let timestamp: Date
    public let appVersion: String
    public let buildNumber: String
    public let isTestFlight: Bool
    public let iosVersion: String
    public let deviceModel: String
    public let sessionState: String
    public let sessionRecord: SessionRecord
    public let weeklySchedule: WeeklySchedule
    public let pendingNotifications: [PendingNotificationInfo]
    public let watchIsPaired: Bool
    public let watchIsReachable: Bool
    public let watchLastSyncedAt: Date?
    public let logEntries: [LogEntry]
}

public struct PendingNotificationInfo: Codable, Sendable {
    public let identifier: String
    public let fireDate: Date?
}
```

**Data sources:**
- `SessionControllerProtocol` → current state, session record, weekly schedule
- `NotificationSchedulerProtocol.pendingRequests()` → new method returning identifiers + fire dates only (no content)
- `WatchConnectivityProtocol` → paired/reachable status
- `LogBuffer.shared.drain()` → log entries
- Device info from `UIDevice` / `Bundle.main` (injected as closures or a protocol to keep Core UI-free)

**PII exclusions:** No device name (`UIDevice.current.name`), no user name, no Apple ID, no notification body text, no location, no IP address. UUIDs (cycle IDs) are random and untraceable.

### 3. BugReporterProtocol + GitHubIssueReporter (BlinkBreakCore)

```swift
public protocol BugReporterProtocol: Sendable {
    func submit(report: DiagnosticReport, userDescription: String) async throws
}
```

`GitHubIssueReporter` implementation:
- Initialized with PAT string + repo string (`owner/repo`), injected from the app target
- **Issue title:** `[Bug Report] <first ~60 chars of user description>`
- **Issue body:** Markdown with sections:
  - User description
  - App state (session state, record fields)
  - Device info (iOS version, model, app version, build, TestFlight flag)
  - Pending notifications (identifier + fire date table)
  - Watch connectivity (paired, reachable, last sync)
  - Log buffer (in a collapsible `<details>` block)
- **Label:** `bug-report` (pre-created on the repo)
- POSTs to `https://api.github.com/repos/{owner}/{repo}/issues`
- Throws on failure; caller handles error display

PAT is a fine-grained GitHub token scoped to `issues: write` on `TytaniumDev/BlinkBreak` only. Stored as a string constant in the iOS app target, not in BlinkBreakCore. Acceptable risk for TestFlight where all users are trusted testers.

`NoopBugReporter` conforms to the protocol for tests and previews.

### 4. Shake Detection + Submission Flow (iOS app target)

A `ShakeDetectingViewController` wrapped in `UIViewControllerRepresentable`, layered into the root SwiftUI view hierarchy. Overrides `motionEnded(.motionShake, ...)`.

**Flow:**
1. Shake detected → check `isTestFlight` (`Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"`). If false, ignore.
2. Present `UIAlertController` with text field ("Describe the issue") + Cancel / Send buttons.
3. On Send: `DiagnosticCollector` gathers report (async), `GitHubIssueReporter.submit()` fires.
4. Brief toast: "Report sent" on success, "Failed to send report" on error.

**Not included:** watchOS. Bug reports are iOS-only. Watch-side bugs manifest in the state sync data captured by the iOS report.

### 5. Device Info Without UI Imports in Core

`DiagnosticCollector` needs device model, iOS version, app version, and `isTestFlight`. These come from `UIDevice` and `Bundle.main` which are UIKit/Foundation APIs.

To keep BlinkBreakCore free of UI imports:
- Device info is passed in as a `DeviceInfo` struct parameter to the collector
- The iOS app target constructs `DeviceInfo` from `UIDevice`/`Bundle.main` and passes it in
- `DeviceInfo` is a simple Codable struct in Core — no UI framework dependency

```swift
public struct DeviceInfo: Codable, Sendable {
    public let iosVersion: String
    public let deviceModel: String
    public let appVersion: String
    public let buildNumber: String
    public let isTestFlight: Bool
}
```

## Testing Strategy

**Unit tests (BlinkBreakCore):**
- `LogBuffer`: write, drain, capacity eviction, thread safety (concurrent writes)
- `DiagnosticCollector`: inject mocks for all dependencies, verify output report contains expected fields
- `GitHubIssueReporter`: test Markdown formatting logic (title truncation, body structure) as a pure function. The POST itself is trivial and verified by construction.
- `NoopBugReporter`: trivial conformance for previews/tests

**No new integration tests.** Shake gesture is hard to simulate in XCUITest, the feature is TestFlight-only, and unit tests cover the logic.

**Manual verification checklist (on device with TestFlight build):**
- [ ] Shake triggers description alert
- [ ] Typing description and tapping Send creates GitHub issue with correct formatting
- [ ] All diagnostic sections populated in the issue body
- [ ] Error case (airplane mode) shows failure toast
- [ ] Non-TestFlight build (production) ignores shake gesture

## Security Considerations

- Fine-grained PAT scoped to `issues: write` on a single repo — minimal blast radius
- PAT is extractable from the TestFlight binary by a motivated actor, but audience is trusted testers
- No PII in reports by design — UUIDs are random, timestamps are relative to cycle start
- If the PAT is compromised, worst case is spam issues on the repo (easily revocable)

## Files Changed

**New files in BlinkBreakCore:**
- `LogBuffer.swift` — ring buffer
- `DiagnosticCollector.swift` — report assembly
- `DiagnosticReport.swift` — report + related Codable structs
- `BugReporterProtocol.swift` — protocol + `GitHubIssueReporter` + `NoopBugReporter`

**Modified in BlinkBreakCore:**
- `NotificationSchedulerProtocol.swift` — add `pendingRequests()` method
- `MockNotificationScheduler.swift` — conform to new method

**New files in iOS app target:**
- `BugReport/ShakeDetector.swift` — `UIViewControllerRepresentable` shake handler
- `BugReport/BugReportConfig.swift` — PAT constant + repo string

**Modified in iOS app target:**
- `RootView.swift` — layer in `ShakeDetector`
- `BlinkBreakApp.swift` — wire up `GitHubIssueReporter` dependency

**New test files:**
- `LogBufferTests.swift`
- `DiagnosticCollectorTests.swift`
- `GitHubIssueFormatterTests.swift`
