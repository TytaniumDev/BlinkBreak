//
//  MockAlarmScheduler.swift
//  BlinkBreakCoreTests
//
//  Test double for AlarmSchedulerProtocol. Lets tests:
//  - Drive virtual time by calling `simulateFire` and `simulateDismiss`.
//  - Inspect `scheduled` to assert which alarms were created.
//  - Override `nextAssignedId` to make assertions deterministic.
//

import Foundation
@testable import BlinkBreakCore

final class MockAlarmScheduler: AlarmSchedulerProtocol, @unchecked Sendable {

    struct ScheduleCall: Equatable {
        let alarmId: UUID
        let duration: TimeInterval
        let kind: AlarmKind
    }

    private let lock = NSLock()
    private var _scheduled: [ScheduleCall] = []
    private var _cancelled: [UUID] = []
    private var _cancelAllCount: Int = 0
    private var _currentAlarms: [ScheduledAlarmInfo] = []
    private var _stubbedAuthorization: Bool = true
    private var _nextAssignedId: UUID?

    private let continuation: AsyncStream<AlarmEvent>.Continuation
    let events: AsyncStream<AlarmEvent>

    init() {
        var cont: AsyncStream<AlarmEvent>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    // MARK: - Inspection

    var scheduled: [ScheduleCall] {
        lock.lock(); defer { lock.unlock() }
        return _scheduled
    }

    var cancelledIds: [UUID] {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    var cancelAllCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _cancelAllCount
    }

    // MARK: - Stubbing helpers

    /// Override the next ID returned from `scheduleCountdown`. Useful when a test
    /// needs a specific UUID it can later assert on.
    func setNextAssignedId(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        _nextAssignedId = id
    }

    func stubAuthorization(_ granted: Bool) {
        lock.lock(); defer { lock.unlock() }
        _stubbedAuthorization = granted
    }

    func setCurrentAlarms(_ alarms: [ScheduledAlarmInfo]) {
        lock.lock(); defer { lock.unlock() }
        _currentAlarms = alarms
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        _scheduled.removeAll()
        _cancelled.removeAll()
        _cancelAllCount = 0
        _currentAlarms.removeAll()
        _nextAssignedId = nil
    }

    // MARK: - Event simulation

    /// Push a `.fired` event onto the stream. Called by tests to simulate the
    /// system firing an alarm.
    func simulateFire(alarmId: UUID, kind: AlarmKind) {
        continuation.yield(.fired(alarmId: alarmId, kind: kind))
    }

    /// Push a `.dismissed` event onto the stream. Simulates the user tapping Stop.
    func simulateDismiss(alarmId: UUID, kind: AlarmKind) {
        continuation.yield(.dismissed(alarmId: alarmId, kind: kind))
    }

    // MARK: - AlarmSchedulerProtocol

    func requestAuthorizationIfNeeded() async throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _stubbedAuthorization
    }

    func scheduleCountdown(duration: TimeInterval, kind: AlarmKind) async throws -> UUID {
        lock.lock()
        let id = _nextAssignedId ?? UUID()
        _nextAssignedId = nil
        _scheduled.append(ScheduleCall(alarmId: id, duration: duration, kind: kind))
        // Mirror real AlarmKit behavior: scheduling adds the alarm to the system's
        // active set. `currentAlarms()` should report it until cancellation or fire.
        _currentAlarms.append(ScheduledAlarmInfo(alarmId: id, kind: kind))
        lock.unlock()
        return id
    }

    func cancel(alarmId: UUID) async {
        lock.lock(); defer { lock.unlock() }
        _cancelled.append(alarmId)
        _currentAlarms.removeAll(where: { $0.alarmId == alarmId })
    }

    func cancelAll() async {
        lock.lock(); defer { lock.unlock() }
        _cancelAllCount += 1
        _currentAlarms.removeAll()
    }

    func currentAlarms() async -> [ScheduledAlarmInfo] {
        lock.lock(); defer { lock.unlock() }
        return _currentAlarms
    }
}
