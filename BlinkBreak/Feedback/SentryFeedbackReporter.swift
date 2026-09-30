//
//  SentryFeedbackReporter.swift
//  BlinkBreak
//
//  Sends user feedback to Sentry. Sentry already captures release, device info,
//  and the breadcrumb stream (mirrored from AppLogger in SentryBootstrap); this
//  adds a few app-state tags so feedback is filterable in the Sentry UI.
//
//  In DEBUG builds Sentry is not initialized, so these calls are no-ops.
//

import Foundation
import Sentry

struct SentryFeedbackReporter: FeedbackReporting {

    /// App-state tags attached to each submission.
    let context: @MainActor @Sendable () -> [String: String]

    func submit(category: FeedbackCategory, message: String, email: String?) async throws {
        var tags = await context()
        tags["category"] = category.rawValue
        tags["testflight"] = String(await DistributionChannel.isTestFlight())

        // Tag a companion event via the scope-block overload so the tags apply
        // to this event only, then link the feedback to it.
        let eventId = SentrySDK.capture(message: "User feedback") { scope in
            for (key, value) in tags {
                scope.setTag(value: value, key: key)
            }
            // One issue per submission instead of all collapsing into one group.
            scope.setFingerprint(["user-feedback", UUID().uuidString])
        }

        SentrySDK.capture(feedback: SentryFeedback(
            message: "[\(category.rawValue.uppercased())] \(message)",
            name: nil,
            email: email,
            source: .custom,
            associatedEventId: eventId
        ))
    }
}
