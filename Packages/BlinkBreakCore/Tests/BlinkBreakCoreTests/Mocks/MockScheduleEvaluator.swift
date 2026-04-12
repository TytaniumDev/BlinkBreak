//
//  MockScheduleEvaluator.swift
//  BlinkBreakCoreTests
//
//  Test mock for ScheduleEvaluating. Returns configurable stubbed values.
//

import Foundation
@testable import BlinkBreakCore

final class MockScheduleEvaluator: ScheduleEvaluating, @unchecked Sendable {

    var stubbedShouldBeActive: Bool = false
    var stubbedNextTransitionDate: Date?
    var shouldBeActiveCalls: [(date: Date, manualStopDate: Date?)] = []

    func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool {
        shouldBeActiveCalls.append((date: date, manualStopDate: manualStopDate))
        return stubbedShouldBeActive
    }

    func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? {
        stubbedNextTransitionDate
    }
}
