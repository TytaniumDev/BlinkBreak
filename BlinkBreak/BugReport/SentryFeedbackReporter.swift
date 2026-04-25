//
//  SentryFeedbackReporter.swift
//  BlinkBreak
//
//  Submits user-initiated bug reports as Sentry user feedback. Lives in the iOS
//  app target because BlinkBreakCore stays free of third-party SDK imports.
//
//  Sentry already captures release, environment, device info, and the breadcrumb
//  stream (mirrored from LogBuffer in SentryBootstrap). We attach session state
//  and weekly-schedule context as tags so the feedback event is filterable in
//  the Sentry UI alongside the standard metadata.
//
//  In DEBUG builds Sentry is not initialized, so capture(feedback:) is a no-op
//  and the call returns successfully — that's fine for local shake testing.
//

import Foundation
import BlinkBreakCore
import Sentry

final class SentryFeedbackReporter: BugReporterProtocol, @unchecked Sendable {

    func submit(report: DiagnosticReport, userDescription: String) async throws {
        SentrySDK.configureScope { scope in
            scope.setTag(value: report.sessionState, key: "session_state")
            scope.setTag(value: String(report.sessionRecord.sessionActive), key: "session_active")
            scope.setTag(value: String(report.weeklySchedule.isEnabled), key: "schedule_enabled")
            scope.setTag(value: String(report.deviceInfo.isTestFlight), key: "testflight")
        }

        let feedback = SentryFeedback(
            message: userDescription.isEmpty ? "(no description)" : userDescription,
            name: nil,
            email: nil,
            source: .custom
        )
        SentrySDK.capture(feedback: feedback)
    }
}
