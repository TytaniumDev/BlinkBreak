//
//  SessionControllerTests.swift
//  BlinkBreakCoreTests
//
//  State-machine tests for SessionController. Uses an AlarmKit mock + virtual time.
//
//  AlarmKit is event-driven, so most state transitions are driven by simulating
//  alarm events (`fire`, `dismiss`) rather than by advancing the clock and calling
//  reconcile. Where the production code spawns a Task to schedule an alarm, tests
//  await `Task.yield()` (or a small `Task.sleep`) to let the spawned task complete.
//
//  Written in Swift Testing (the `import Testing` framework), not legacy XCTest.
//

@testable import BlinkBreakCore
import Foundation
import Testing

@MainActor
@Suite("SessionController — state machine")
struct SessionControllerTests {

    typealias Fixture = TestFixture

    // MARK: - start()

    @Test("start() transitions idle → running with clock time as cycleStartedAt")
    func startTransitionsToRunning() async {
        let f = Fixture()
        #expect(f.controller.state == .idle)

        await f.controller.start()

        guard case .running(let startedAt) = f.controller.state else {
            Issue.record("expected running, got \(f.controller.state)")
            return
        }
        #expect(startedAt == f.nowBox.value)
    }

    @Test("start() schedules a single break-due alarm")
    func startSchedulesBreakAlarm() async {
        let f = Fixture()
        await f.controller.start()

        #expect(f.alarmScheduler.scheduled.count == 1)
        let call = f.alarmScheduler.scheduled[0]
        #expect(call.kind == .breakDue)
        #expect(call.duration == BlinkBreakConstants.breakInterval)
    }

    @Test("start() persists an active record with currentAlarmId set")
    func startPersistsRecord() async {
        let f = Fixture()
        await f.controller.start()

        let record = f.persistence.load()
        #expect(record.sessionActive)
        #expect(record.currentCycleId != nil)
        #expect(record.cycleStartedAt == f.nowBox.value)
        #expect(record.breakActiveStartedAt == nil)
        #expect(record.currentAlarmId != nil)
        #expect(record.currentAlarmId == f.alarmScheduler.scheduled.last?.alarmId)
    }

    @Test("start() cancels any previously-scheduled alarms first")
    func startCancelsExistingAlarms() async {
        let f = Fixture()

        await f.controller.start()
        let firstCancelAllCount = f.alarmScheduler.cancelAllCount

        await f.controller.start()

        #expect(f.alarmScheduler.cancelAllCount == firstCancelAllCount + 1)
    }

    // MARK: - stop()

    @Test("stop() transitions any state → idle")
    func stopTransitionsToIdle() async {
        let f = Fixture()
        await f.controller.start()

        await f.controller.stop()

        #expect(f.controller.state == .idle)
    }

    @Test("stop() cancels all alarms")
    func stopCancelsEverything() async {
        let f = Fixture()
        await f.controller.start()
        let initial = f.alarmScheduler.cancelAllCount

        await f.controller.stop()

        #expect(f.alarmScheduler.cancelAllCount == initial + 1)
    }

    @Test("stop() persists idle record")
    func stopPersistsIdle() async {
        let f = Fixture()
        await f.controller.start()

        await f.controller.stop()

        let record = f.persistence.load()
        #expect(record.sessionActive == false)
        #expect(record.currentCycleId == nil)
    }

    // MARK: - Event-driven transitions

    @Test("break-due alarm firing transitions running → breakPending")
    func breakAlarmFireGoesToBreakPending() async {
        let f = Fixture()
        await f.controller.start()
        let alarmId = f.alarmScheduler.scheduled.last!.alarmId

        f.alarmScheduler.simulateFire(alarmId: alarmId, kind: .breakDue)
        await settle()

        guard case .breakPending = f.controller.state else {
            Issue.record("expected breakPending, got \(f.controller.state)")
            return
        }
    }

    @Test("break-due alarm dismissal transitions to breakActive + schedules look-away")
    func breakDismissSchedulesLookAway() async {
        let f = Fixture()
        await f.controller.start()
        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId

        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        f.advance(by: 5)
        f.alarmScheduler.simulateDismiss(alarmId: breakAlarmId, kind: .breakDue)
        await settle()

        // Should have scheduled a look-away alarm
        let lookAwayCalls = f.alarmScheduler.scheduled.filter { $0.kind == .lookAwayDone }
        #expect(lookAwayCalls.count == 1)
        #expect(lookAwayCalls[0].duration == BlinkBreakConstants.lookAwayDuration)

        // State should be breakActive
        guard case .breakActive(let startedAt) = f.controller.state else {
            Issue.record("expected breakActive, got \(f.controller.state)")
            return
        }
        #expect(startedAt == f.nowBox.value)

        // Persistence should have advanced the alarm ID + breakActiveStartedAt
        let record = f.persistence.load()
        #expect(record.breakActiveStartedAt == f.nowBox.value)
        #expect(record.currentAlarmId == lookAwayCalls[0].alarmId)
    }

    @Test("look-away alarm dismissal rolls to next cycle")
    func lookAwayDismissRollsCycle() async {
        let f = Fixture()
        await f.controller.start()
        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        f.alarmScheduler.simulateDismiss(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        let lookAwayAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        let firstCycleId = f.persistence.load().currentCycleId!

        f.advance(by: BlinkBreakConstants.lookAwayDuration)
        f.alarmScheduler.simulateFire(alarmId: lookAwayAlarmId, kind: .lookAwayDone)
        f.alarmScheduler.simulateDismiss(alarmId: lookAwayAlarmId, kind: .lookAwayDone)
        await settle()

        // State should be running with new cycle
        guard case .running = f.controller.state else {
            Issue.record("expected running, got \(f.controller.state)")
            return
        }
        let record = f.persistence.load()
        #expect(record.currentCycleId != firstCycleId)
        #expect(record.breakActiveStartedAt == nil)

        // A new break alarm should be scheduled
        let breakCalls = f.alarmScheduler.scheduled.filter { $0.kind == .breakDue }
        #expect(breakCalls.count == 2)  // initial + next-cycle
    }

    @Test("dismissed event for stale alarmId is ignored")
    func staleDismissIgnored() async {
        let f = Fixture()
        await f.controller.start()
        let stateBefore = f.controller.state

        f.alarmScheduler.simulateDismiss(alarmId: UUID(), kind: .breakDue)
        await settle()

        #expect(f.controller.state == stateBefore)
    }

    // MARK: - acknowledgeCurrentBreak()

    @Test("acknowledgeCurrentBreak triggers the same flow as alarm dismissal")
    func acknowledgeFromInsideAppFlow() async {
        let f = Fixture()
        await f.controller.start()
        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()

        await f.controller.acknowledgeCurrentBreak()

        // Should have cancelled the break alarm + scheduled look-away
        #expect(f.alarmScheduler.cancelledIds.contains(breakAlarmId))
        let lookAwayCalls = f.alarmScheduler.scheduled.filter { $0.kind == .lookAwayDone }
        #expect(lookAwayCalls.count == 1)
        guard case .breakActive = f.controller.state else {
            Issue.record("expected breakActive, got \(f.controller.state)")
            return
        }
    }

    @Test("acknowledgeCurrentBreak with no current alarm is a no-op")
    func acknowledgeWhileIdleIgnored() async {
        let f = Fixture()
        await f.controller.acknowledgeCurrentBreak()

        #expect(f.controller.state == .idle)
        #expect(f.alarmScheduler.scheduled.isEmpty)
    }

    // MARK: - Full loop

    @Test("full loop: start → break fires → ack → look-away → roll cycle")
    func fullLoop() async {
        let f = Fixture()

        await f.controller.start()
        #expect(f.controller.state.description == "running")
        let firstCycleId = f.persistence.load().currentCycleId!

        let breakAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.alarmScheduler.simulateFire(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        #expect(f.controller.state.description == "breakPending")

        f.alarmScheduler.simulateDismiss(alarmId: breakAlarmId, kind: .breakDue)
        await settle()
        #expect(f.controller.state.description == "breakActive")

        let lookAwayAlarmId = f.alarmScheduler.scheduled.last!.alarmId
        f.advance(by: BlinkBreakConstants.lookAwayDuration)
        f.alarmScheduler.simulateFire(alarmId: lookAwayAlarmId, kind: .lookAwayDone)
        f.alarmScheduler.simulateDismiss(alarmId: lookAwayAlarmId, kind: .lookAwayDone)
        await settle()

        #expect(f.controller.state.description == "running")
        #expect(f.persistence.load().currentCycleId != firstCycleId)

        await f.controller.stop()
        #expect(f.controller.state == .idle)
        #expect(f.persistence.load().sessionActive == false)
    }

    // MARK: - triggerBreakNow()

    @Test("triggerBreakNow() while running cancels current alarm and schedules 1-second breakDue alarm")
    func triggerBreakNowWhileRunning() async {
        let f = Fixture()
        await f.controller.start()

        let originalId = f.alarmScheduler.scheduled.last!.alarmId
        await f.controller.triggerBreakNow()

        #expect(f.alarmScheduler.cancelledIds.contains(originalId))

        let newCall = f.alarmScheduler.scheduled.last!
        #expect(newCall.duration == 1)
        #expect(newCall.kind == .breakDue)
    }

    @Test("triggerBreakNow() while running updates SessionRecord.currentAlarmId")
    func triggerBreakNowUpdatesRecord() async {
        let f = Fixture()
        await f.controller.start()

        let idBefore = f.persistence.load().currentAlarmId!
        await f.controller.triggerBreakNow()

        let idAfter = f.persistence.load().currentAlarmId!
        #expect(idAfter != idBefore)
    }

    @Test("triggerBreakNow() while idle is a no-op")
    func triggerBreakNowWhileIdleIsNoOp() async {
        let f = Fixture()
        await f.controller.triggerBreakNow()
        #expect(f.alarmScheduler.scheduled.isEmpty)
        #expect(f.alarmScheduler.cancelledIds.isEmpty)
        #expect(f.controller.state == .idle)
    }

    // MARK: - muteAlarmSound / updateAlarmSound(muted:)

    @Test("muteAlarmSound defaults to false")
    func muteAlarmSoundDefaultsFalse() {
        let f = Fixture()
        #expect(f.controller.muteAlarmSound == false)
    }

    @Test("updateAlarmSound(muted:) updates the published property and persists")
    func updateAlarmSoundPersists() async {
        let f = Fixture()
        await f.controller.updateAlarmSound(muted: true)
        #expect(f.controller.muteAlarmSound == true)
        #expect(f.persistence.loadAlarmSoundMuted() == true)

        await f.controller.updateAlarmSound(muted: false)
        #expect(f.controller.muteAlarmSound == false)
        #expect(f.persistence.loadAlarmSoundMuted() == false)
    }

    @Test("updateAlarmSound(muted:) while idle does not schedule or cancel any alarms")
    func updateAlarmSoundWhileIdleIsNoOp() async {
        let f = Fixture()
        await f.controller.updateAlarmSound(muted: true)
        #expect(f.alarmScheduler.scheduled.isEmpty)
        #expect(f.alarmScheduler.cancelledIds.isEmpty)
    }

    @Test("updateAlarmSound(muted:) while running cancels current alarm and reschedules with new muteSound")
    func updateAlarmSoundWhileRunningReschedules() async {
        let f = Fixture()
        await f.controller.start()

        let originalId = f.alarmScheduler.scheduled.last!.alarmId
        f.advance(by: 5 * 60)  // 5 minutes into the 20-minute cycle

        await f.controller.updateAlarmSound(muted: true)

        // Original alarm cancelled
        #expect(f.alarmScheduler.cancelledIds.contains(originalId))

        // New alarm scheduled with muteSound: true and remaining duration ≈ 15 minutes
        let newCall = f.alarmScheduler.scheduled.last!
        #expect(newCall.muteSound == true)
        #expect(newCall.kind == .breakDue)
        #expect(abs(newCall.duration - 15 * 60) < 2)
    }

    @Test("start() passes muteAlarmSound preference through to scheduleCountdown")
    func startPassesMuteSoundPreference() async {
        let f = Fixture()
        await f.controller.updateAlarmSound(muted: true)
        await f.controller.start()

        let call = f.alarmScheduler.scheduled.last!
        #expect(call.muteSound == true)
    }
}
