//
//  FeedbackReporting.swift
//  BlinkBreak
//
//  The feedback-submission interface views use, injected through the SwiftUI
//  environment. Production uses `SentryFeedbackReporter`; previews and tests
//  get the no-op default.
//
//  Flutter analogue: an abstract service provided with `Provider<FeedbackService>`.
//

import SwiftUI

enum FeedbackCategory: String, CaseIterable, Identifiable, Sendable {
    case suggestion = "Suggestion"
    case bugReport = "Bug Report"
    case question = "Question"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .suggestion: return "lightbulb.fill"
        case .bugReport: return "ladybug.fill"
        case .question: return "questionmark.circle.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

protocol FeedbackReporting: Sendable {
    /// - Parameter email: Optional reply-to address the user typed in.
    func submit(category: FeedbackCategory, message: String, email: String?) async throws
}

struct NoopFeedbackReporter: FeedbackReporting {
    func submit(category: FeedbackCategory, message: String, email: String?) async throws {}
}

extension EnvironmentValues {
    @Entry var feedbackReporter: any FeedbackReporting = NoopFeedbackReporter()
}
