//
//  ScheduleIntegrationTests.swift
//  BlinkBreakCoreTests
//
//  Tests for SessionController's schedule-driven auto-start/stop behavior.
//

import Testing
import Foundation
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — schedule integration")
struct ScheduleIntegrationTests {

    @MainActor
    final class Fixture {
        let scheduler = MockNotificationScheduler()
        let connectivity = MockWatchConnectivity()
        let persistence = InMemoryPersistence()
        let alarm = MockSessionAlarm()
        let evaluator = MockScheduleEvaluator()
        let nowBox: NowBox
        let controller: SessionController

        init() {
            let box = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
            self.nowBox = box
            self.controller = SessionController(
                scheduler: scheduler,
                connectivity: connectivity,
                persistence: persistence,
                alarm: alarm,
                scheduleEvaluator: evaluator,
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

    @Test("reconcileOnLaunch auto-starts when evaluator says active and state is idle")
    func autoStart() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)  // Enable schedule so evaluateSchedule() runs
        f.evaluator.stubbedShouldBeActive = true
        #expect(f.controller.state == .idle)
        await f.controller.reconcileOnLaunch()
        #expect(f.controller.state != .idle)
        #expect(f.persistence.load().sessionActive == true)
    }

    @Test("reconcileOnLaunch auto-stops when evaluator says inactive and state is running")
    func autoStop() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)  // Enable schedule so evaluateSchedule() runs
        f.controller.start()
        #expect(f.controller.state != .idle)
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcileOnLaunch()
        #expect(f.controller.state == .idle)
    }

    @Test("reconcileOnLaunch does not auto-start when evaluator returns false")
    func noAutoStartWhenInactive() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)  // Enable schedule so evaluateSchedule() runs
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcileOnLaunch()
        #expect(f.controller.state == .idle)
    }

    @Test("stop() sets manualStopDate when evaluator says within window")
    func stopSetsManualStopDate() {
        let f = Fixture()
        f.evaluator.stubbedShouldBeActive = true
        f.controller.start()
        f.controller.stop()
        #expect(f.persistence.load().manualStopDate != nil)
    }

    @Test("stop() does not set manualStopDate when evaluator says outside window")
    func stopNoManualStopDateOutsideWindow() {
        let f = Fixture()
        f.evaluator.stubbedShouldBeActive = false
        f.controller.start()
        f.controller.stop()
        #expect(f.persistence.load().manualStopDate == nil)
    }

    @Test("reconcileOnLaunch passes manualStopDate to evaluator")
    func passesManualStopDate() async {
        let f = Fixture()
        f.controller.updateSchedule(.default)  // Enable schedule so evaluateSchedule() runs
        let stopDate = Date(timeIntervalSince1970: 1_699_999_000)
        var record = SessionRecord.idle
        record.manualStopDate = stopDate
        f.persistence.save(record)
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcileOnLaunch()
        #expect(f.evaluator.shouldBeActiveCalls.last?.manualStopDate == stopDate)
    }

    @Test("updateSchedule saves to persistence and updates published property")
    func updateSchedule() {
        let f = Fixture()
        let schedule = WeeklySchedule.default
        f.controller.updateSchedule(schedule)
        #expect(f.controller.weeklySchedule == schedule)
        #expect(f.persistence.loadSchedule() == schedule)
    }
}
