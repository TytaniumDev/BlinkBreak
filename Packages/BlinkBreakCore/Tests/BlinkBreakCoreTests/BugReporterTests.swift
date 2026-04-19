//
//  BugReporterTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the GitHub issue Markdown formatting logic. The actual POST is not tested
//  (it's a single URLSession call verified by construction); we test the formatting
//  because that's where bugs hide.
//

@testable import BlinkBreakCore
import Foundation
import Testing

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

    @Test("body sanitizes markdown/HTML in user description")
    func bodySanitizesHTML() {
        let report = makeReport(logCount: 0)
        let body = GitHubIssueReporter.formatBody(
            userDescription: "Look at this <script>alert(1)</script> and <details>something</details>",
            report: report
        )
        #expect(body.contains("Look at this &lt;script&gt;alert(1)&lt;/script&gt; and &lt;details&gt;something&lt;/details&gt;"))
        #expect(!body.contains("<script>"))
        #expect(!body.contains("<details>something</details>"))
    }

    @Test("body sanitizes triple backticks in log messages")
    func bodySanitizesMarkdownBlocks() {
        let report = DiagnosticReport(
            timestamp: Date(),
            deviceInfo: DeviceInfo(iosVersion: "1", deviceModel: "2", appVersion: "3", buildNumber: "4", isTestFlight: true),
            sessionState: "idle",
            sessionRecord: .idle,
            weeklySchedule: .empty,
            logEntries: [LogEntry(timestamp: Date(), level: .info, message: "Sneaky ``` injected ``` code")]
        )
        let body = GitHubIssueReporter.formatBody(
            userDescription: "test",
            report: report
        )
        #expect(body.contains("Sneaky ` ` ` injected ` ` ` code"))
        #expect(!body.contains("``` injected ```"))
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
