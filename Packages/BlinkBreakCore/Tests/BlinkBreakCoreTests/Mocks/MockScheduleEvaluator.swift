//
//  MockScheduleEvaluator.swift
//  BlinkBreakCoreTests
//
//  Test mock for ScheduleEvaluating. Returns configurable stubbed values.
//

import Foundation
@testable import BlinkBreakCore

final class MockScheduleEvaluator: ScheduleEvaluatorProtocol, @unchecked Sendable {

    var stubbedShouldBeActive: Bool = false
    /// When set, takes priority over `stubbedShouldBeActive`. Lets tests answer
    /// differently for "now" vs. "next alarm fire-time" in the same evaluator call sequence.
    var stubbedShouldBeActiveBlock: (@Sendable (Date) -> Bool)?
    var stubbedNextTransitionDate: Date?
    var stubbedStatusText: String?
    var shouldBeActiveCalls: [(date: Date, manualStopDate: Date?)] = []

    func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool {
        shouldBeActiveCalls.append((date: date, manualStopDate: manualStopDate))
        if let block = stubbedShouldBeActiveBlock {
            return block(date)
        }
        return stubbedShouldBeActive
    }

    func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? {
        stubbedNextTransitionDate
    }

    func statusText(at date: Date, calendar: Calendar) -> String? {
        stubbedStatusText
    }
}
