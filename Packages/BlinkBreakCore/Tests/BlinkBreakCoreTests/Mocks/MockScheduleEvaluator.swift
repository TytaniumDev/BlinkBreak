//
//  MockScheduleEvaluator.swift
//  BlinkBreakCoreTests
//
//  Test mock for ScheduleEvaluating. Returns configurable stubbed values.
//

@testable import BlinkBreakCore
import Foundation

final class MockScheduleEvaluator: ScheduleEvaluatorProtocol, @unchecked Sendable {

    var stubbedShouldBeActive: Bool = false
    var stubbedNextTransitionDate: Date?
    var stubbedStatusText: String?
    var shouldBeActiveCalls: [(date: Date, manualStopDate: Date?)] = []

    func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool {
        shouldBeActiveCalls.append((date: date, manualStopDate: manualStopDate))
        return stubbedShouldBeActive
    }

    func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? {
        stubbedNextTransitionDate
    }

    func statusText(at date: Date, calendar: Calendar) -> String? {
        stubbedStatusText
    }
}
