//
//  MockAlarmScheduler.swift
//  BlinkBreakCoreTests
//
//  Test double for AlarmSchedulerProtocol. Keeps an in-memory list of "system"
//  alarms so tests can:
//  - Inspect `scheduled` / `cancelled` to assert what the controller asked for.
//  - Mark an alarm alerting (`simulateAlerting`) or make it vanish the way the
//    system does after a button tap (`simulateRemoval`).
//  - Stub authorization and scheduling failures.
//

import Foundation
import Synchronization
@testable import BlinkBreakCore

final class MockAlarmScheduler: AlarmSchedulerProtocol {

    struct ScheduleCall: Equatable {
        let alarmId: UUID
        let kind: AlarmKind
        let fireDate: Date
        let muteSound: Bool
    }

    private struct Storage {
        var scheduled: [ScheduleCall] = []
        var cancelled: [UUID] = []
        var system: [ScheduledAlarm] = []
        var authorization: AlarmAuthorizationStatus = .authorized
        var nextError: AlarmSchedulerError?
    }

    private let storage = Mutex(Storage())
    private let beforeScheduleHook = Mutex<(@Sendable () async -> Void)?>(nil)
    private let continuation: AsyncStream<AlarmEvent>.Continuation
    let events: AsyncStream<AlarmEvent>

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    // MARK: - Inspection

    var scheduled: [ScheduleCall] { storage.withLock { $0.scheduled } }
    var cancelled: [UUID] { storage.withLock { $0.cancelled } }
    var systemAlarmIds: [UUID] { storage.withLock { $0.system.map(\.alarmId) } }
    var lastScheduled: ScheduleCall? { scheduled.last }

    // MARK: - Stubbing

    func stubAuthorization(_ status: AlarmAuthorizationStatus) {
        storage.withLock { $0.authorization = status }
    }

    /// Make the next `schedule` call throw.
    func failNextSchedule(with error: AlarmSchedulerError) {
        storage.withLock { $0.nextError = error }
    }

    /// Run `hook` inside every `schedule` call before it returns, to simulate a
    /// slow AlarmKit round trip that other calls can race against.
    func setBeforeSchedule(_ hook: (@Sendable () async -> Void)?) {
        beforeScheduleHook.withLock { $0 = hook }
    }

    /// Put an alarm into the system list as if an earlier launch had scheduled it.
    func addSystemAlarm(_ id: UUID, isAlerting: Bool = false) {
        storage.withLock { $0.system.append(ScheduledAlarm(alarmId: id, isAlerting: isAlerting)) }
    }

    // MARK: - Event simulation

    func simulateAlerting(_ id: UUID) {
        storage.withLock { storage in
            storage.system = storage.system.map {
                $0.alarmId == id ? ScheduledAlarm(alarmId: id, isAlerting: true) : $0
            }
        }
        continuation.yield(.alerting(alarmId: id))
    }

    /// The alarm disappears from the system (user tapped a button, or it timed out).
    func simulateRemoval(_ id: UUID) {
        storage.withLock { $0.system.removeAll { $0.alarmId == id } }
        continuation.yield(.removed(alarmId: id))
    }

    // MARK: - AlarmSchedulerProtocol

    func authorizationStatus() async -> AlarmAuthorizationStatus {
        storage.withLock { $0.authorization }
    }

    func schedule(_ kind: AlarmKind, at fireDate: Date, muteSound: Bool) async throws -> UUID {
        if let hook = beforeScheduleHook.withLock({ $0 }) {
            await hook()
        }
        return try storage.withLock { storage in
            if let error = storage.nextError {
                storage.nextError = nil
                throw error
            }
            if storage.authorization == .denied {
                throw AlarmSchedulerError.authorizationDenied
            }
            let id = UUID()
            storage.scheduled.append(ScheduleCall(alarmId: id, kind: kind, fireDate: fireDate, muteSound: muteSound))
            storage.system.append(ScheduledAlarm(alarmId: id))
            return id
        }
    }

    func cancel(alarmId: UUID) async {
        storage.withLock { storage in
            storage.cancelled.append(alarmId)
            storage.system.removeAll { $0.alarmId == alarmId }
        }
    }

    func currentAlarms() async -> [ScheduledAlarm] {
        storage.withLock { $0.system }
    }
}
