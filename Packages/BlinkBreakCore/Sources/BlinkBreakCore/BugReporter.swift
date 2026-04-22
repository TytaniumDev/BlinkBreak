//
//  BugReporter.swift
//  BlinkBreakCore
//
//  Protocol for submitting bug reports, plus a GitHub Issues implementation and a
//  no-op mock. The protocol follows the same dependency-injection pattern as
//  AlarmSchedulerProtocol and PersistenceProtocol.
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
        // Enforce input length limit to prevent large payload DoS
        let truncatedDescription = String(userDescription.prefix(3000))

        let url = URL(string: "https://api.github.com/repos/\(repo)/issues")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0 // Prevent hanging connections
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let title = Self.formatTitle(userDescription: truncatedDescription)
        let body = Self.formatBody(userDescription: truncatedDescription, report: report)

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

    /// Shared formatter for ISO 8601 date strings. Thread-safe.
    private static let iso = ISO8601DateFormatter()

    /// Format the issue title, truncating the user description to ~60 characters.
    /// The full title stays within 75 chars: "[Bug Report] " (13) + 59 chars + "..." (3) = 75.
    static func formatTitle(userDescription: String) -> String {
        let maxLength = 59
        if userDescription.count <= maxLength {
            return "[Bug Report] \(userDescription)"
        }
        let truncated = String(userDescription.prefix(maxLength)) + "..."
        return "[Bug Report] \(truncated)"
    }

    /// Format the issue body as Markdown with all diagnostic sections.
    static func formatBody(userDescription: String, report: DiagnosticReport) -> String {
        var sections: [String] = []

        // Sanitize user description to prevent Markdown/HTML injection
        let sanitizedDescription = userDescription
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // User description
        sections.append("""
        ## Description

        \(sanitizedDescription)
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
        | Break Active Started | \(r.breakActiveStartedAt.map { iso.string(from: $0) } ?? "none") |
        | Schedule Enabled | \(report.weeklySchedule.isEnabled) |
        """)

        // Log entries (collapsible)
        if !report.logEntries.isEmpty {
            let logLines = report.logEntries.lazy.map { entry in
                let safeMessage = entry.message.replacingOccurrences(of: "```", with: "` ` `")
                return "[\(iso.string(from: entry.timestamp))] [\(entry.level.rawValue)] \(safeMessage)"
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
