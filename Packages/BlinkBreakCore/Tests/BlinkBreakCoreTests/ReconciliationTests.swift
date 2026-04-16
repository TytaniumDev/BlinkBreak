//
//  ReconciliationTests.swift
//  BlinkBreakCoreTests
//
//  Targeted tests for `SessionController.reconcile()` — the method that rebuilds UI
//  state from persisted record + the alarm scheduler's currently-scheduled alarms +
//  the current clock.
//

import Testing
import Foundation
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — reconciliation")
struct ReconciliationTests {

    @MainActor
    final class Fixture {
        let alarmScheduler = MockAlarmScheduler()
        let persistence = InMemoryPersistence()
        let nowBox = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
        let controller: SessionController

        init() {
            let box = nowBox
            self.controller = SessionController(
                alarmScheduler: alarmScheduler,
                persistence: persistence,
                clock: { box.value }
            )
        }

        func advance(by seconds: TimeInterval) {
            nowBox.value = nowBox.value.addingTimeInterval(seconds)
        }
    }

    final class NowBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Date
        init(value: Date) { self.storage = value }
        var value: Date {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); defer { lock.unlock() }; storage = newValue }
        }
    }

    @Test("reconcile with no persisted session → idle")
    func noSession() async {
        let f = Fixture()
        f.persistence.save(.idle)

        await f.controller.reconcile()

        #expect(f.controller.state == .idle)
    }

    @Test("reconcile within running window with active break-due alarm → running")
    func withinRunning() async {
        let f = Fixture()
        let cycleId = UUID()
        let alarmId = UUID()
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: f.nowBox.value,
            breakActiveStartedAt: nil,
            currentAlarmId: alarmId
        ))
        f.alarmScheduler.setCurrentAlarms([
            ScheduledAlarmInfo(alarmId: alarmId, kind: .breakDue)
        ])

        await f.controller.reconcile()

        guard case .running(let startedAt) = f.controller.state else {
            Issue.record("expected running, got \(f.controller.state)")
            return
        }
        #expect(startedAt == f.nowBox.value)
    }

    @Test("reconcile past break time with no scheduled alarm → breakPending")
    func pastBreakNoAlarm() async {
        let f = Fixture()
        let cycleId = UUID()
        let started = f.nowBox.value
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: started,
            breakActiveStartedAt: nil,
            currentAlarmId: UUID()
        ))
        f.alarmScheduler.setCurrentAlarms([])
        f.advance(by: BlinkBreakConstants.breakInterval + 60)

        await f.controller.reconcile()

        guard case .breakPending(let startedAt) = f.controller.state else {
            Issue.record("expected breakPending, got \(f.controller.state)")
            return
        }
        #expect(startedAt == started)
    }

    @Test("reconcile within breakActive window with active look-away alarm → breakActive")
    func withinBreakActiveWindow() async {
        let f = Fixture()
        let breakActiveStart = f.nowBox.value
        let alarmId = UUID()
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: breakActiveStart,
            breakActiveStartedAt: breakActiveStart,
            currentAlarmId: alarmId
        ))
        f.alarmScheduler.setCurrentAlarms([
            ScheduledAlarmInfo(alarmId: alarmId, kind: .lookAwayDone)
        ])
        f.advance(by: BlinkBreakConstants.lookAwayDuration / 2)

        await f.controller.reconcile()

        guard case .breakActive(let startedAt) = f.controller.state else {
            Issue.record("expected breakActive, got \(f.controller.state)")
            return
        }
        #expect(startedAt == breakActiveStart)
    }

    @Test("reconcile in breakActive window with no alarm scheduled → breakActive (alarm fired while killed)")
    func breakActiveNoAlarm() async {
        let f = Fixture()
        let breakActiveStart = f.nowBox.value
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: breakActiveStart,
            breakActiveStartedAt: breakActiveStart,
            currentAlarmId: UUID()
        ))
        f.alarmScheduler.setCurrentAlarms([])
        f.advance(by: BlinkBreakConstants.lookAwayDuration / 2)

        await f.controller.reconcile()

        guard case .breakActive(let startedAt) = f.controller.state else {
            Issue.record("expected breakActive, got \(f.controller.state)")
            return
        }
        #expect(startedAt == breakActiveStart)
    }

    @Test("reconcile with break-due alarm currently alerting → breakPending")
    func reconcileWithAlertingBreakAlarm() async {
        let f = Fixture()
        let cycleId = UUID()
        let alarmId = UUID()
        let started = f.nowBox.value
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: started,
            breakActiveStartedAt: nil,
            currentAlarmId: alarmId
        ))
        f.alarmScheduler.setCurrentAlarms([
            ScheduledAlarmInfo(alarmId: alarmId, kind: .breakDue, isAlerting: true)
        ])
        f.advance(by: BlinkBreakConstants.breakInterval + 1)

        await f.controller.reconcile()

        guard case .breakPending(let startedAt) = f.controller.state else {
            Issue.record("expected breakPending, got \(f.controller.state)")
            return
        }
        #expect(startedAt == started)
    }

    @Test("reconcile with corrupt record (active but missing fields) → idle")
    func corruptRecord() async {
        let f = Fixture()
        f.persistence.save(SessionRecord(
            sessionActive: true,
            currentCycleId: nil,
            cycleStartedAt: nil,
            breakActiveStartedAt: nil
        ))

        await f.controller.reconcile()

        #expect(f.controller.state == .idle)
        #expect(f.persistence.load() == .idle)
    }
}
