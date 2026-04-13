# Bug Report Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shake-to-report bug reporting to TestFlight builds that auto-creates PII-free GitHub issues with diagnostic data and an extensible log buffer.

**Architecture:** New files in BlinkBreakCore (`LogBuffer`, `DiagnosticCollector`, `BugReporterProtocol`) follow the existing protocol-injection pattern. The iOS app target adds shake detection and wires the GitHub reporter with a scoped PAT. All diagnostic data is value types, fully testable with mocks.

**Tech Stack:** Swift 5.9, Foundation, URLSession (single POST), Swift Testing framework for tests.

---

### Task 1: LogBuffer — ring buffer for in-memory logs

**Files:**
- Create: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/LogBuffer.swift`
- Test: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/LogBufferTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/LogBufferTests.swift`:

```swift
//
//  LogBufferTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the in-memory log ring buffer used by bug reports.
//

import Testing
@testable import BlinkBreakCore

@Suite("LogBuffer")
struct LogBufferTests {

    @Test("log appends entries with correct level and message")
    func logAppendsEntries() {
        let buffer = LogBuffer(capacity: 10)
        buffer.log(.info, "hello")
        buffer.log(.error, "oops")

        let entries = buffer.drain()
        #expect(entries.count == 2)
        #expect(entries[0].level == .info)
        #expect(entries[0].message == "hello")
        #expect(entries[1].level == .error)
        #expect(entries[1].message == "oops")
    }

    @Test("drain returns entries in insertion order with timestamps")
    func drainReturnsInOrder() {
        let buffer = LogBuffer(capacity: 10)
        buffer.log(.debug, "first")
        buffer.log(.warning, "second")

        let entries = buffer.drain()
        #expect(entries[0].timestamp <= entries[1].timestamp)
    }

    @Test("oldest entries evict when capacity is exceeded")
    func evictsOldestWhenFull() {
        let buffer = LogBuffer(capacity: 3)
        buffer.log(.info, "a")
        buffer.log(.info, "b")
        buffer.log(.info, "c")
        buffer.log(.info, "d")

        let entries = buffer.drain()
        #expect(entries.count == 3)
        #expect(entries[0].message == "b")
        #expect(entries[1].message == "c")
        #expect(entries[2].message == "d")
    }

    @Test("drain does not clear the buffer")
    func drainDoesNotClear() {
        let buffer = LogBuffer(capacity: 10)
        buffer.log(.info, "persistent")

        _ = buffer.drain()
        let entries = buffer.drain()
        #expect(entries.count == 1)
        #expect(entries[0].message == "persistent")
    }

    @Test("concurrent writes do not crash")
    func threadSafety() async {
        let buffer = LogBuffer(capacity: 100)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    buffer.log(.info, "msg-\(i)")
                }
            }
        }
        let entries = buffer.drain()
        #expect(entries.count == 100)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: Compilation error — `LogBuffer` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `Packages/BlinkBreakCore/Sources/BlinkBreakCore/LogBuffer.swift`:

```swift
//
//  LogBuffer.swift
//  BlinkBreakCore
//
//  Thread-safe in-memory ring buffer for diagnostic logs. Code throughout BlinkBreakCore
//  writes short messages here; the bug report collector drains the buffer when submitting.
//
//  Flutter analogue: similar to a bounded List<LogEntry> behind a mutex, read by a
//  diagnostics screen or crash reporter.
//

import Foundation

/// Severity level for a log entry.
public enum LogLevel: String, Codable, Sendable {
    case debug, info, warning, error
}

/// A single log entry with a timestamp, severity, and developer-written message.
public struct LogEntry: Codable, Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
}

/// Thread-safe ring buffer that holds up to `capacity` log entries. When full, the oldest
/// entry is evicted to make room for the new one.
///
/// Usage:
/// ```swift
/// LogBuffer.shared.log(.info, "reconcile: rebuilt state from persisted record")
/// ```
public final class LogBuffer: @unchecked Sendable {

    /// Shared instance used throughout BlinkBreakCore. Capacity of 500 entries.
    public static let shared = LogBuffer(capacity: 500)

    private let lock = NSLock()
    private var storage: [LogEntry]
    private let capacity: Int

    /// Create a buffer with the given maximum capacity. Use `LogBuffer.shared` in production;
    /// create isolated instances in tests.
    public init(capacity: Int) {
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    /// Append a log entry at the current time. If the buffer is full, the oldest entry
    /// is evicted.
    public func log(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        lock.lock()
        defer { lock.unlock() }
        if storage.count >= capacity {
            storage.removeFirst()
        }
        storage.append(entry)
    }

    /// Return all buffered entries in insertion order. Does not clear the buffer.
    public func drain() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: All tests pass, including the 5 new LogBuffer tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/LogBuffer.swift \
       Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/LogBufferTests.swift
git commit -m "feat: add LogBuffer ring buffer for diagnostic logs"
```

---

### Task 2: DiagnosticReport and DeviceInfo structs

**Files:**
- Create: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/DiagnosticReport.swift`

- [ ] **Step 1: Write the data types**

Create `Packages/BlinkBreakCore/Sources/BlinkBreakCore/DiagnosticReport.swift`:

```swift
//
//  DiagnosticReport.swift
//  BlinkBreakCore
//
//  Value types for the bug report payload. All fields are Codable and PII-free.
//  The iOS app target constructs DeviceInfo from UIDevice/Bundle.main and passes it
//  to DiagnosticCollector; Core never imports UIKit.
//
//  Flutter analogue: a data class that a diagnostics service serializes to JSON
//  before sending to a crash/bug reporting backend.
//

import Foundation

/// Device and app metadata. Constructed by the iOS app target (which has access to UIDevice
/// and Bundle.main) and passed into DiagnosticCollector. Keeps BlinkBreakCore free of UI
/// framework imports.
public struct DeviceInfo: Codable, Sendable {
    public let iosVersion: String
    public let deviceModel: String
    public let appVersion: String
    public let buildNumber: String
    public let isTestFlight: Bool

    public init(
        iosVersion: String,
        deviceModel: String,
        appVersion: String,
        buildNumber: String,
        isTestFlight: Bool
    ) {
        self.iosVersion = iosVersion
        self.deviceModel = deviceModel
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.isTestFlight = isTestFlight
    }
}

/// Identifier and fire date for a pending notification. Content/body is deliberately
/// excluded to keep the report PII-free.
public struct PendingNotificationInfo: Codable, Sendable {
    public let identifier: String
    public let fireDate: Date?

    public init(identifier: String, fireDate: Date?) {
        self.identifier = identifier
        self.fireDate = fireDate
    }
}

/// The complete diagnostic payload attached to a bug report GitHub issue.
/// Every field is a value type, Codable, and contains no PII.
public struct DiagnosticReport: Codable, Sendable {
    public let timestamp: Date
    public let deviceInfo: DeviceInfo
    public let sessionState: String
    public let sessionRecord: SessionRecord
    public let weeklySchedule: WeeklySchedule
    public let pendingNotifications: [PendingNotificationInfo]
    public let watchIsPaired: Bool
    public let watchIsReachable: Bool
    public let watchLastSyncedAt: Date?
    public let logEntries: [LogEntry]

    public init(
        timestamp: Date,
        deviceInfo: DeviceInfo,
        sessionState: String,
        sessionRecord: SessionRecord,
        weeklySchedule: WeeklySchedule,
        pendingNotifications: [PendingNotificationInfo],
        watchIsPaired: Bool,
        watchIsReachable: Bool,
        watchLastSyncedAt: Date?,
        logEntries: [LogEntry]
    ) {
        self.timestamp = timestamp
        self.deviceInfo = deviceInfo
        self.sessionState = sessionState
        self.sessionRecord = sessionRecord
        self.weeklySchedule = weeklySchedule
        self.pendingNotifications = pendingNotifications
        self.watchIsPaired = watchIsPaired
        self.watchIsReachable = watchIsReachable
        self.watchLastSyncedAt = watchLastSyncedAt
        self.logEntries = logEntries
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: All existing tests pass (the new file is just data types, no tests needed for structs with no logic).

- [ ] **Step 3: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/DiagnosticReport.swift
git commit -m "feat: add DiagnosticReport and DeviceInfo value types"
```

---

### Task 3: Add `pendingRequests()` to NotificationSchedulerProtocol

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift:78-95` (protocol) and `:239-246` (UNNotificationScheduler)
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockNotificationScheduler.swift`
- Test: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift`

- [ ] **Step 1: Write the failing test**

Add to the bottom of `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift`:

```swift
@Suite("MockNotificationScheduler — pendingRequests")
struct MockPendingRequestsTests {

    @Test("pendingRequests returns identifier and fireDate for scheduled notifications")
    func pendingRequestsReturnsScheduledInfo() async {
        let mock = MockNotificationScheduler()
        mock.schedule(ScheduledNotification(
            identifier: "test.1",
            title: "T",
            body: "B",
            fireDate: Date(timeIntervalSince1970: 1_700_001_000),
            isTimeSensitive: false,
            threadIdentifier: "thread",
            categoryIdentifier: nil
        ))

        let requests = await mock.pendingRequests()
        #expect(requests.count == 1)
        #expect(requests[0].identifier == "test.1")
        #expect(requests[0].fireDate == Date(timeIntervalSince1970: 1_700_001_000))
    }

    @Test("pendingRequests returns empty array when nothing scheduled")
    func pendingRequestsEmptyWhenNothingScheduled() async {
        let mock = MockNotificationScheduler()
        let requests = await mock.pendingRequests()
        #expect(requests.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: Compilation error — `pendingRequests()` does not exist on the protocol.

- [ ] **Step 3: Add `pendingRequests()` to the protocol**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift`, add after the `pendingIdentifiers()` method (line 94), before the closing brace of the protocol:

```swift
    /// Return identifier + fire date for all currently-pending notifications.
    /// Used by DiagnosticCollector for bug reports. Async because UNUserNotificationCenter's
    /// API is async.
    func pendingRequests() async -> [PendingNotificationInfo]
```

- [ ] **Step 4: Add the real implementation to UNNotificationScheduler**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift`, add after the `pendingIdentifiers()` method in `UNNotificationScheduler` (after line 245):

```swift
    public func pendingRequests() async -> [PendingNotificationInfo] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let infos = requests.map { request in
                    PendingNotificationInfo(
                        identifier: request.identifier,
                        fireDate: (request.trigger as? UNTimeIntervalNotificationTrigger)
                            .flatMap { $0.nextTriggerDate() }
                    )
                }
                continuation.resume(returning: infos)
            }
        }
    }
```

- [ ] **Step 5: Add the mock implementation**

In `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockNotificationScheduler.swift`, add after the `pendingIdentifiers()` method (after line 74), before the `// MARK: - Test helpers` comment:

```swift
    func pendingRequests() async -> [PendingNotificationInfo] {
        lock.lock()
        defer { lock.unlock() }
        return scheduledNotifications.map {
            PendingNotificationInfo(identifier: $0.identifier, fireDate: $0.fireDate)
        }
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: All tests pass, including the 2 new pendingRequests tests.

- [ ] **Step 7: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/NotificationScheduler.swift \
       Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockNotificationScheduler.swift \
       Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/NotificationSchedulerTests.swift
git commit -m "feat: add pendingRequests() to NotificationSchedulerProtocol"
```

---

### Task 4: DiagnosticCollector

**Files:**
- Create: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/DiagnosticCollector.swift`
- Test: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/DiagnosticCollectorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/DiagnosticCollectorTests.swift`:

```swift
//
//  DiagnosticCollectorTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the diagnostic report assembly logic.
//

import Testing
@testable import BlinkBreakCore

@Suite("DiagnosticCollector")
struct DiagnosticCollectorTests {

    private static let testDeviceInfo = DeviceInfo(
        iosVersion: "17.4",
        deviceModel: "iPhone15,2",
        appVersion: "0.1.0",
        buildNumber: "42",
        isTestFlight: true
    )

    @Test("collect assembles a complete report from all sources")
    func collectAssemblesReport() async {
        let scheduler = MockNotificationScheduler()
        scheduler.schedule(ScheduledNotification(
            identifier: "break.primary.test",
            title: "T",
            body: "B",
            fireDate: Date(timeIntervalSince1970: 1_700_001_200),
            isTimeSensitive: true,
            threadIdentifier: "thread",
            categoryIdentifier: nil
        ))

        let persistence = InMemoryPersistence()
        let record = SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lookAwayStartedAt: nil,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        persistence.save(record)

        let logBuffer = LogBuffer(capacity: 10)
        logBuffer.log(.info, "test log entry")

        let collector = DiagnosticCollector(
            scheduler: scheduler,
            persistence: persistence,
            logBuffer: logBuffer,
            sessionState: "running",
            watchIsPaired: true,
            watchIsReachable: false
        )

        let report = await collector.collect(deviceInfo: Self.testDeviceInfo)

        #expect(report.deviceInfo.iosVersion == "17.4")
        #expect(report.deviceInfo.isTestFlight == true)
        #expect(report.sessionState == "running")
        #expect(report.sessionRecord.sessionActive == true)
        #expect(report.pendingNotifications.count == 1)
        #expect(report.pendingNotifications[0].identifier == "break.primary.test")
        #expect(report.watchIsPaired == true)
        #expect(report.watchIsReachable == false)
        #expect(report.logEntries.count == 1)
        #expect(report.logEntries[0].message == "test log entry")
    }

    @Test("collect includes weekly schedule from persistence")
    func collectIncludesSchedule() async {
        let persistence = InMemoryPersistence()
        var schedule = WeeklySchedule.empty
        schedule.isEnabled = true
        persistence.saveSchedule(schedule)

        let collector = DiagnosticCollector(
            scheduler: MockNotificationScheduler(),
            persistence: persistence,
            logBuffer: LogBuffer(capacity: 10),
            sessionState: "idle",
            watchIsPaired: false,
            watchIsReachable: false
        )

        let report = await collector.collect(deviceInfo: Self.testDeviceInfo)
        #expect(report.weeklySchedule.isEnabled == true)
    }

    @Test("collect uses watchLastSyncedAt from session record")
    func collectUsesWatchSyncTimestamp() async {
        let persistence = InMemoryPersistence()
        let syncDate = Date(timeIntervalSince1970: 1_700_000_500)
        let record = SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lookAwayStartedAt: nil,
            lastUpdatedAt: syncDate
        )
        persistence.save(record)

        let collector = DiagnosticCollector(
            scheduler: MockNotificationScheduler(),
            persistence: persistence,
            logBuffer: LogBuffer(capacity: 10),
            sessionState: "running",
            watchIsPaired: true,
            watchIsReachable: true
        )

        let report = await collector.collect(deviceInfo: Self.testDeviceInfo)
        #expect(report.watchLastSyncedAt == syncDate)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: Compilation error — `DiagnosticCollector` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `Packages/BlinkBreakCore/Sources/BlinkBreakCore/DiagnosticCollector.swift`:

```swift
//
//  DiagnosticCollector.swift
//  BlinkBreakCore
//
//  Gathers diagnostic data from all sources into a DiagnosticReport. Pure function:
//  dependencies in, report out. The iOS app target injects the real scheduler,
//  persistence, and device info; tests inject mocks.
//
//  Flutter analogue: a service class that reads from multiple repositories and
//  assembles a diagnostics payload for upload.
//

import Foundation

/// Assembles a `DiagnosticReport` from the current app state, persistence, pending
/// notifications, Watch connectivity status, and log buffer.
public struct DiagnosticCollector: Sendable {

    private let scheduler: NotificationSchedulerProtocol
    private let persistence: PersistenceProtocol
    private let logBuffer: LogBuffer
    private let sessionState: String
    private let watchIsPaired: Bool
    private let watchIsReachable: Bool

    public init(
        scheduler: NotificationSchedulerProtocol,
        persistence: PersistenceProtocol,
        logBuffer: LogBuffer,
        sessionState: String,
        watchIsPaired: Bool,
        watchIsReachable: Bool
    ) {
        self.scheduler = scheduler
        self.persistence = persistence
        self.logBuffer = logBuffer
        self.sessionState = sessionState
        self.watchIsPaired = watchIsPaired
        self.watchIsReachable = watchIsReachable
    }

    /// Collect all diagnostic data into a report. Async because fetching pending
    /// notifications is async.
    public func collect(deviceInfo: DeviceInfo) async -> DiagnosticReport {
        let record = persistence.load()
        let schedule = persistence.loadSchedule() ?? .empty
        let pending = await scheduler.pendingRequests()
        let logs = logBuffer.drain()

        return DiagnosticReport(
            timestamp: Date(),
            deviceInfo: deviceInfo,
            sessionState: sessionState,
            sessionRecord: record,
            weeklySchedule: schedule,
            pendingNotifications: pending,
            watchIsPaired: watchIsPaired,
            watchIsReachable: watchIsReachable,
            watchLastSyncedAt: record.lastUpdatedAt,
            logEntries: logs
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: All tests pass, including the 3 new DiagnosticCollector tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/DiagnosticCollector.swift \
       Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/DiagnosticCollectorTests.swift
git commit -m "feat: add DiagnosticCollector for assembling bug reports"
```

---

### Task 5: BugReporterProtocol + GitHubIssueReporter

**Files:**
- Create: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/BugReporter.swift`
- Test: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/BugReporterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/BugReporterTests.swift`:

```swift
//
//  BugReporterTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the GitHub issue Markdown formatting logic. The actual POST is not tested
//  (it's a single URLSession call verified by construction); we test the formatting
//  because that's where bugs hide.
//

import Testing
@testable import BlinkBreakCore

@Suite("GitHubIssueReporter — formatting")
struct BugReporterFormattingTests {

    private func makeReport(
        sessionState: String = "running",
        logCount: Int = 0
    ) -> DiagnosticReport {
        let logs = (0..<logCount).map { i in
            LogEntry(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)),
                level: .info,
                message: "log \(i)"
            )
        }
        return DiagnosticReport(
            timestamp: Date(timeIntervalSince1970: 1_700_000_100),
            deviceInfo: DeviceInfo(
                iosVersion: "17.4",
                deviceModel: "iPhone15,2",
                appVersion: "0.1.0",
                buildNumber: "42",
                isTestFlight: true
            ),
            sessionState: sessionState,
            sessionRecord: .idle,
            weeklySchedule: .empty,
            pendingNotifications: [
                PendingNotificationInfo(
                    identifier: "break.primary.abc",
                    fireDate: Date(timeIntervalSince1970: 1_700_001_200)
                )
            ],
            watchIsPaired: true,
            watchIsReachable: false,
            watchLastSyncedAt: nil,
            logEntries: logs
        )
    }

    @Test("title truncates long descriptions to ~60 chars")
    func titleTruncation() {
        let longDesc = String(repeating: "a", count: 100)
        let title = GitHubIssueReporter.formatTitle(userDescription: longDesc)
        #expect(title.count <= 75) // "[Bug Report] " prefix + 60 chars + "..."
        #expect(title.hasPrefix("[Bug Report] "))
        #expect(title.hasSuffix("..."))
    }

    @Test("title uses full description when short enough")
    func titleShortDescription() {
        let title = GitHubIssueReporter.formatTitle(userDescription: "Timer skips")
        #expect(title == "[Bug Report] Timer skips")
    }

    @Test("body contains all diagnostic sections")
    func bodyContainsAllSections() {
        let report = makeReport(logCount: 2)
        let body = GitHubIssueReporter.formatBody(
            userDescription: "Something broke",
            report: report
        )

        // User description section
        #expect(body.contains("Something broke"))
        // Device info section
        #expect(body.contains("iPhone15,2"))
        #expect(body.contains("17.4"))
        #expect(body.contains("0.1.0"))
        // App state section
        #expect(body.contains("running"))
        // Pending notifications
        #expect(body.contains("break.primary.abc"))
        // Watch section
        #expect(body.contains("Paired: true"))
        // Log entries in a details block
        #expect(body.contains("<details>"))
        #expect(body.contains("log 0"))
        #expect(body.contains("log 1"))
    }

    @Test("body omits log section when no entries")
    func bodyOmitsEmptyLogs() {
        let report = makeReport(logCount: 0)
        let body = GitHubIssueReporter.formatBody(
            userDescription: "Bug",
            report: report
        )
        #expect(!body.contains("<details>"))
    }

    @Test("NoopBugReporter does not throw")
    func noopDoesNotThrow() async throws {
        let noop = NoopBugReporter()
        try await noop.submit(
            report: makeReport(),
            userDescription: "test"
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: Compilation error — `BugReporterProtocol`, `GitHubIssueReporter`, `NoopBugReporter` do not exist.

- [ ] **Step 3: Write the implementation**

Create `Packages/BlinkBreakCore/Sources/BlinkBreakCore/BugReporter.swift`:

```swift
//
//  BugReporter.swift
//  BlinkBreakCore
//
//  Protocol for submitting bug reports, plus a GitHub Issues implementation and a
//  no-op mock. The protocol follows the same dependency-injection pattern as
//  NotificationSchedulerProtocol and WatchConnectivityProtocol.
//
//  Flutter analogue: an abstract BugReportService with a GitHubBugReportService
//  and a NoopBugReportService for tests/previews.
//

import Foundation

// MARK: - Protocol

/// Submits a bug report with diagnostic data. Tests and previews use `NoopBugReporter`.
public protocol BugReporterProtocol: Sendable {
    func submit(report: DiagnosticReport, userDescription: String) async throws
}

// MARK: - GitHub Issues implementation

/// Creates a GitHub issue via the REST API with formatted diagnostic data.
public final class GitHubIssueReporter: BugReporterProtocol, @unchecked Sendable {

    private let token: String
    private let repo: String  // "owner/repo"
    private let session: URLSession

    /// - Parameters:
    ///   - token: A fine-grained GitHub PAT scoped to `issues: write` on the target repo.
    ///   - repo: The repository in "owner/repo" format, e.g. "TytaniumDev/BlinkBreak".
    ///   - session: URLSession to use for the request. Defaults to `.shared`.
    public init(token: String, repo: String, session: URLSession = .shared) {
        self.token = token
        self.repo = repo
        self.session = session
    }

    public func submit(report: DiagnosticReport, userDescription: String) async throws {
        let url = URL(string: "https://api.github.com/repos/\(repo)/issues")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let title = Self.formatTitle(userDescription: userDescription)
        let body = Self.formatBody(userDescription: userDescription, report: report)

        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "labels": ["bug-report"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw BugReportError.submitFailed(statusCode: statusCode)
        }
    }

    // MARK: - Formatting (internal for testing)

    /// Format the issue title, truncating the user description to ~60 characters.
    static func formatTitle(userDescription: String) -> String {
        let maxLength = 60
        if userDescription.count <= maxLength {
            return "[Bug Report] \(userDescription)"
        }
        let truncated = String(userDescription.prefix(maxLength)) + "..."
        return "[Bug Report] \(truncated)"
    }

    /// Format the issue body as Markdown with all diagnostic sections.
    static func formatBody(userDescription: String, report: DiagnosticReport) -> String {
        let iso = ISO8601DateFormatter()

        var sections: [String] = []

        // User description
        sections.append("""
        ## Description

        \(userDescription)
        """)

        // Device info
        let d = report.deviceInfo
        sections.append("""
        ## Device

        | Field | Value |
        |-------|-------|
        | iOS Version | \(d.iosVersion) |
        | Device Model | \(d.deviceModel) |
        | App Version | \(d.appVersion) (\(d.buildNumber)) |
        | TestFlight | \(d.isTestFlight) |
        | Report Time | \(iso.string(from: report.timestamp)) |
        """)

        // App state
        let r = report.sessionRecord
        sections.append("""
        ## App State

        | Field | Value |
        |-------|-------|
        | Session State | \(report.sessionState) |
        | Session Active | \(r.sessionActive) |
        | Cycle ID | \(r.currentCycleId?.uuidString ?? "none") |
        | Cycle Started | \(r.cycleStartedAt.map { iso.string(from: $0) } ?? "none") |
        | Look Away Started | \(r.lookAwayStartedAt.map { iso.string(from: $0) } ?? "none") |
        | Schedule Enabled | \(report.weeklySchedule.isEnabled) |
        """)

        // Pending notifications
        if !report.pendingNotifications.isEmpty {
            var table = """
            ## Pending Notifications

            | Identifier | Fire Date |
            |------------|-----------|
            """
            for n in report.pendingNotifications {
                let dateStr = n.fireDate.map { iso.string(from: $0) } ?? "unknown"
                table += "\n| \(n.identifier) | \(dateStr) |"
            }
            sections.append(table)
        }

        // Watch connectivity
        sections.append("""
        ## Watch Connectivity

        | Field | Value |
        |-------|-------|
        | Paired | \(report.watchIsPaired) |
        | Reachable | \(report.watchIsReachable) |
        | Last Synced | \(report.watchLastSyncedAt.map { iso.string(from: $0) } ?? "never") |
        """)

        // Log entries (collapsible)
        if !report.logEntries.isEmpty {
            var logLines = report.logEntries.map { entry in
                "[\(iso.string(from: entry.timestamp))] [\(entry.level.rawValue)] \(entry.message)"
            }
            sections.append("""
            <details>
            <summary>Log Buffer (\(report.logEntries.count) entries)</summary>

            ```
            \(logLines.joined(separator: "\n"))
            ```

            </details>
            """)
        }

        return sections.joined(separator: "\n\n")
    }
}

// MARK: - Error

public enum BugReportError: Error, LocalizedError {
    case submitFailed(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .submitFailed(let code):
            return "Bug report submission failed (HTTP \(code))"
        }
    }
}

// MARK: - No-op implementation

/// A `BugReporterProtocol` that does nothing. Used in tests and SwiftUI previews.
public final class NoopBugReporter: BugReporterProtocol, @unchecked Sendable {
    public init() {}
    public func submit(report: DiagnosticReport, userDescription: String) async throws {}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: All tests pass, including the 5 new BugReporter formatting tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/BugReporter.swift \
       Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/BugReporterTests.swift
git commit -m "feat: add BugReporterProtocol with GitHub issue reporter"
```

---

### Task 6: Shake detection + submission flow (iOS app target)

**Files:**
- Create: `BlinkBreak/BugReport/ShakeDetector.swift`
- Create: `BlinkBreak/BugReport/BugReportConfig.swift`
- Modify: `BlinkBreak/BlinkBreakApp.swift:44-54,60`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionState.swift` (add `CustomStringConvertible`)

- [ ] **Step 1: Create the PAT configuration file**

Create `BlinkBreak/BugReport/BugReportConfig.swift`:

```swift
//
//  BugReportConfig.swift
//  BlinkBreak
//
//  Configuration for the bug report feature. The PAT is a fine-grained GitHub token
//  scoped to issues:write on TytaniumDev/BlinkBreak only. This is acceptable for
//  TestFlight builds where all users are trusted testers.
//
//  To set up:
//  1. Go to https://github.com/settings/tokens?type=beta
//  2. Create a fine-grained PAT with:
//     - Repository access: TytaniumDev/BlinkBreak only
//     - Permissions: Issues → Read and write
//  3. Paste the token below.
//  4. Create the "bug-report" label on the repo if it doesn't exist.
//

enum BugReportConfig {
    /// Fine-grained GitHub PAT scoped to issues:write on TytaniumDev/BlinkBreak.
    /// Replace this placeholder with a real token before building for TestFlight.
    static let gitHubToken = "REPLACE_WITH_GITHUB_PAT"

    /// The target repository for bug report issues.
    static let gitHubRepo = "TytaniumDev/BlinkBreak"
}
```

- [ ] **Step 2: Create the shake detector**

Create `BlinkBreak/BugReport/ShakeDetector.swift`:

```swift
//
//  ShakeDetector.swift
//  BlinkBreak
//
//  Detects shake gestures and presents a bug report submission dialog.
//  TestFlight-only: production builds ignore shakes entirely.
//
//  Flutter analogue: like wrapping your root widget in a GestureDetector
//  that listens for device shake events.
//

import SwiftUI
import BlinkBreakCore

/// Invisible UIKit view controller that intercepts shake gestures. Layered into the
/// SwiftUI view hierarchy via `ShakeDetectorView`.
final class ShakeDetectingViewController: UIViewController {

    var onShake: (() -> Void)?

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            onShake?()
        }
    }

    // Must be first responder to receive motion events.
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
}

/// SwiftUI wrapper that layers an invisible shake-detecting UIKit controller behind
/// the content. Only active in TestFlight builds.
struct ShakeDetectorView<Content: View>: View {

    let content: Content
    let scheduler: NotificationSchedulerProtocol
    let persistence: PersistenceProtocol
    let sessionState: String
    let watchIsPaired: Bool
    let watchIsReachable: Bool

    @State private var showingSubmitAlert = false
    @State private var bugDescription = ""
    @State private var showingToast = false
    @State private var toastMessage = ""

    private var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    var body: some View {
        content
            .background(
                ShakeDetectorRepresentable {
                    guard isTestFlight else { return }
                    showingSubmitAlert = true
                    bugDescription = ""
                }
            )
            .alert("Report a Bug", isPresented: $showingSubmitAlert) {
                TextField("Describe the issue", text: $bugDescription)
                Button("Cancel", role: .cancel) {}
                Button("Send") {
                    submitReport()
                }
            } message: {
                Text("Your report will create a GitHub issue with diagnostic data (no personal info).")
            }
            .overlay(alignment: .bottom) {
                if showingToast {
                    Text(toastMessage)
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showingToast)
    }

    private func submitReport() {
        Task {
            do {
                let deviceInfo = DeviceInfo(
                    iosVersion: UIDevice.current.systemVersion,
                    deviceModel: Self.deviceModelIdentifier(),
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                    isTestFlight: isTestFlight
                )

                let collector = DiagnosticCollector(
                    scheduler: scheduler,
                    persistence: persistence,
                    logBuffer: LogBuffer.shared,
                    sessionState: sessionState,
                    watchIsPaired: watchIsPaired,
                    watchIsReachable: watchIsReachable
                )

                let report = await collector.collect(deviceInfo: deviceInfo)

                let reporter = GitHubIssueReporter(
                    token: BugReportConfig.gitHubToken,
                    repo: BugReportConfig.gitHubRepo
                )
                try await reporter.submit(
                    report: report,
                    userDescription: bugDescription
                )

                showToast("Report sent")
            } catch {
                showToast("Failed to send report")
            }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        showingToast = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            showingToast = false
        }
    }

    /// Returns the machine identifier (e.g. "iPhone15,2") instead of the marketing
    /// name. Avoids importing the user-facing device name which could be PII.
    private static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }
}

/// UIViewControllerRepresentable bridge for the shake-detecting UIKit controller.
private struct ShakeDetectorRepresentable: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeDetectingViewController {
        let vc = ShakeDetectingViewController()
        vc.onShake = onShake
        return vc
    }

    func updateUIViewController(_ uiViewController: ShakeDetectingViewController, context: Context) {
        uiViewController.onShake = onShake
    }
}
```

- [ ] **Step 3: Wrap RootView in ShakeDetectorView in BlinkBreakApp.swift**

RootView stays unchanged — the shake detector wraps it from BlinkBreakApp. This keeps previews working and avoids adding dependencies to RootView.

In `BlinkBreak/BlinkBreakApp.swift`, replace line 60:

```swift
            RootView(controller: controller)
```

with:

```swift
            ShakeDetectorView(
                content: RootView(controller: controller),
                scheduler: Self.sharedScheduler,
                persistence: Self.sharedPersistence,
                sessionState: controller.state.description,
                watchIsPaired: false,
                watchIsReachable: false
            )
```

Also, extract the scheduler into a shared static so we can pass it to ShakeDetectorView. Replace lines 44-54:

```swift
    private static let sharedScheduler = UNNotificationScheduler()

    @StateObject private var controller: SessionController = {
        sharedScheduler.registerCategories()
        return SessionController(
            scheduler: sharedScheduler,
            connectivity: WCSessionConnectivity(),
            persistence: sharedPersistence,
            alarm: NoopSessionAlarm(),
            scheduleEvaluator: sharedEvaluator
        )
    }()
```

Add a `description` computed property to `SessionState`. In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionState.swift`, add a `CustomStringConvertible` conformance:

```swift
extension SessionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: return "idle"
        case .running: return "running"
        case .breakActive: return "breakActive"
        case .lookAway: return "lookAway"
        }
    }
}
```

- [ ] **Step 4: Add the new files to project.yml**

Check if `project.yml` has explicit source listings for the iOS target. If it uses glob patterns or directory-based sources, the new `BugReport/` directory will be picked up automatically. If not, add the `BugReport` directory.

Run `grep -n "sources" project.yml` to check. If the iOS target uses `sources: BlinkBreak`, the new `BlinkBreak/BugReport/` directory is automatically included.

- [ ] **Step 5: Build and verify**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: All tests pass. The new iOS-only files don't affect the Swift package tests.

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/build.sh`
Expected: Build succeeds (if full Xcode is available).

- [ ] **Step 6: Commit**

```bash
git add BlinkBreak/BugReport/ShakeDetector.swift \
       BlinkBreak/BugReport/BugReportConfig.swift \
       BlinkBreak/BlinkBreakApp.swift \
       Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionState.swift
git commit -m "feat: add shake-to-report bug reporting for TestFlight builds"
```

---

### Task 7: Add `bug-report` label to the GitHub repo

**Files:** None (GitHub CLI command only)

- [ ] **Step 1: Create the label**

```bash
gh label create bug-report --repo TytaniumDev/BlinkBreak --description "Auto-generated bug report from TestFlight" --color "d73a4a"
```

- [ ] **Step 2: Commit** (no code change — label is repo metadata)

No commit needed.

---

### Task 8: Final verification

**Files:** None

- [ ] **Step 1: Run unit tests**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test.sh`
Expected: All tests pass (existing ~46 + ~15 new).

- [ ] **Step 2: Run lint**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/lint.sh`
Expected: Lint passes. `LogBuffer.swift`, `DiagnosticReport.swift`, `DiagnosticCollector.swift`, and `BugReporter.swift` are all in BlinkBreakCore and import only Foundation. No UI framework imports.

- [ ] **Step 3: Run integration tests**

Run: `cd /Users/tylerholland/Dev/BlinkBreak/.claude/worktrees/graceful-gliding-toast && ./scripts/test-integration.sh`
Expected: All 21 integration tests pass. The shake detector is layered in at the app level but doesn't affect the UI state machine tested by integration tests.
