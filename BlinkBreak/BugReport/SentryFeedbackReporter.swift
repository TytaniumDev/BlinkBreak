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
        // Capture a companion event with the session-specific tags scoped to
        // *this* event via the block overload — the scope changes apply only
        // inside the block. Using `SentrySDK.configureScope` here would mutate
        // the global scope, leaking these tags onto every subsequent crash /
        // event for the rest of the process lifetime. `SentrySDK.capture(feedback:)`
        // doesn't expose a scope-block overload, so we tag the companion event
        // and link the feedback to it via `associatedEventId`.
        let eventId = SentrySDK.capture(message: "User bug report") { scope in
            scope.setTag(value: report.sessionState, key: "session_state")
            scope.setTag(value: String(report.sessionRecord.sessionActive), key: "session_active")
            scope.setTag(value: String(report.weeklySchedule.isEnabled), key: "schedule_enabled")
            scope.setTag(value: String(report.deviceInfo.isTestFlight), key: "testflight")
        }

        let feedback = SentryFeedback(
            message: userDescription.isEmpty ? "(no description)" : userDescription,
            name: nil,
            email: nil,
            source: .custom,
            associatedEventId: eventId
        )
        SentrySDK.capture(feedback: feedback)
    }
}
