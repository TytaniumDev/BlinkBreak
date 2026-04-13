//
//  MockSessionAlarm.swift
//  BlinkBreakCoreTests
//
//  A test-only SessionAlarmProtocol that records every arm/disarm call for assertion.
//  Same shape and style as MockNotificationScheduler.
//

import Foundation
@testable import BlinkBreakCore

/// Records calls for assertion. Used by SessionController tests to verify that the
/// state machine interacts correctly with the alarm surface.
final class MockSessionAlarm: SessionAlarmProtocol, @unchecked Sendable {

    // MARK: - Recorded calls

    private let lock = NSLock()
    private(set) var armedCalls: [(cycleId: UUID, fireDate: Date)] = []
    private(set) var disarmedCycleIds: [UUID] = []

    // MARK: - SessionAlarmProtocol

    func arm(cycleId: UUID, fireDate: Date) {
        lock.withLock {
            armedCalls.append((cycleId, fireDate))
        }
    }

    func disarm(cycleId: UUID) {
        lock.withLock {
            disarmedCycleIds.append(cycleId)
        }
    }

    // MARK: - Test helpers

    /// The most recent arm call, or nil if never armed.
    var lastArmed: (cycleId: UUID, fireDate: Date)? {
        lock.withLock {
            return armedCalls.last
        }
    }

    /// The most recent disarm target, or nil if never disarmed.
    var lastDisarmedCycleId: UUID? {
        lock.withLock {
            return disarmedCycleIds.last
        }
    }

    /// Reset all recorded state. Useful between test phases within one test.
    func reset() {
        lock.withLock {
            armedCalls.removeAll()
            disarmedCycleIds.removeAll()
        }
    }
}
