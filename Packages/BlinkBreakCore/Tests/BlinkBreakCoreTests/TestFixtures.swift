//
//  TestFixtures.swift
//  BlinkBreakCoreTests
//
//  Shared helpers used across the SessionController test suites: a mutable date
//  box for virtual-time control, a task-flushing helper, and a configurable
//  fixture that wires up mocks + a SessionController with an injected clock.
//

import Foundation
@testable import BlinkBreakCore

/// Thread-safe mutable box around a `Date` so fixtures can share a reference with
/// the controller's injected clock closure and advance virtual time without
/// re-creating the controller.
final class NowBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Date
    init(value: Date) { self.storage = value }
    var value: Date {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); defer { lock.unlock() }; storage = newValue }
    }
}

/// SessionController spawns Tasks for alarm-scheduling work. Tests need to let
/// those tasks complete before asserting. Yielding a few times with a tiny sleep
/// is enough for any awaited sequence in the controller to flush given everything
/// runs on the main actor.
func settle() async {
    for _ in 0..<3 {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
}

/// Wires up a `SessionController` with in-memory mocks and a clock backed by a
/// `NowBox` so tests can control virtual time. Pass an evaluator for suites that
/// exercise the schedule integration; omit for the default `NoopScheduleEvaluator`.
@MainActor
final class SessionControllerFixture {
    let alarmScheduler = MockAlarmScheduler()
    let persistence = InMemoryPersistence()
    let evaluator: MockScheduleEvaluator?
    let nowBox = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
    let controller: SessionController

    init(evaluator: MockScheduleEvaluator? = nil) {
        let box = nowBox
        self.evaluator = evaluator
        self.controller = SessionController(
            alarmScheduler: alarmScheduler,
            persistence: persistence,
            scheduleEvaluator: evaluator ?? NoopScheduleEvaluator(),
            clock: { box.value }
        )
    }

    func advance(by seconds: TimeInterval) {
        nowBox.value = nowBox.value.addingTimeInterval(seconds)
    }
}
