//
//  BugReporter.swift
//  BlinkBreakCore
//
//  Protocol for submitting bug reports, plus a no-op implementation for tests
//  and previews. The concrete production implementation lives in the iOS app
//  target (SentryFeedbackReporter) so BlinkBreakCore stays free of third-party
//  SDK imports.
//
//  Flutter analogue: an abstract BugReportService with a NoopBugReportService
//  for tests/previews; the real implementation is wired up in the platform
//  layer.
//

import Foundation

/// Submits a bug report with diagnostic data. Tests and previews use `NoopBugReporter`.
public protocol BugReporterProtocol: Sendable {
    func submit(report: DiagnosticReport, userDescription: String) async throws
}

/// A `BugReporterProtocol` that does nothing. Used in tests and SwiftUI previews.
public final class NoopBugReporter: BugReporterProtocol, @unchecked Sendable {
    public init() {}
    public func submit(report: DiagnosticReport, userDescription: String) async throws {}
}
