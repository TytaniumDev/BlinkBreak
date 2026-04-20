//
//  TestFixture.swift
//  BlinkBreakCoreTests
//
//  Shared test fixtures: a SessionController wired up with all-mock collaborators
//  and a virtual clock that tests can advance synchronously.
//
//  Used by SessionControllerTests, ReconciliationTests, and ScheduleIntegrationTests
//  so each suite doesn't redefine the same boilerplate.
//

@testable import BlinkBreakCore
import Foundation

/// Thread-safe mutable box around a `Date` so the fixture's `clock` closure can
/// capture it by reference and read the latest value on each call.
final class NowBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Date
    init(value: Date) { self.storage = value }
    var value: Date {
        get {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock(); defer { lock.unlock() }
            storage = newValue
        }
    }
}

/// All-mock collaborator wiring for SessionController tests. Pass a `MockScheduleEvaluator`
/// when testing schedule-driven behavior; omit it for plain state-machine tests.
@MainActor
final class TestFixture {
    let alarmScheduler = MockAlarmScheduler()
    let persistence = InMemoryPersistence()
    let evaluator: MockScheduleEvaluator
    let nowBox = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
    let controller: SessionController

    init(evaluator: MockScheduleEvaluator? = nil) {
        let resolvedEvaluator = evaluator ?? MockScheduleEvaluator()
        self.evaluator = resolvedEvaluator
        let box = nowBox
        self.controller = SessionController(
            alarmScheduler: alarmScheduler,
            persistence: persistence,
            scheduleEvaluator: resolvedEvaluator,
            clock: { box.value }
        )
    }

    func advance(by seconds: TimeInterval) {
        nowBox.value = nowBox.value.addingTimeInterval(seconds)
    }
}

/// SessionController spawns Tasks for alarm-scheduling work. Yield + sleep briefly
/// to let those flush before assertions.
func settle() async {
    for _ in 0..<3 {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
}
