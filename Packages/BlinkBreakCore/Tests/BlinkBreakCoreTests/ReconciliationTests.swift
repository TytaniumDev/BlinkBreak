//
//  ReconciliationTests.swift
//  BlinkBreakCoreTests
//
//  `reconcile()` after the app was killed or backgrounded: the persisted record
//  plus the system's alarm list must rebuild the right state and catch up on
//  anything that happened while the app wasn't running.
//

import Testing
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — reconciliation")
struct ReconciliationTests {

    typealias Fixture = SessionControllerFixture
    let interval = BlinkBreakConstants.breakInterval
    let lookAway = BlinkBreakConstants.lookAwayDuration

    /// A fixture whose persisted record says `phase`, owning an alarm that
    /// fires `firesIn` seconds from "now". The alarm is in the system list
    /// unless `alarmInSystem` is false.
    func fixture(
        phase: SessionRecord.Phase,
        firesIn: TimeInterval,
        alarmInSystem: Bool = true,
        alerting: Bool = false
    ) -> (Fixture, UUID) {
        let now = TestCalendar.date(weekday: 2, hour: 10)
        let alarmId = UUID()
        let f = Fixture(now: now, session: SessionRecord(
            phase: phase,
            alarmId: alarmId,
            alarmFiresAt: now.addingTimeInterval(firesIn)
        ))
        if alarmInSystem {
            f.alarms.addSystemAlarm(alarmId, isAlerting: alerting)
        }
        return (f, alarmId)
    }

    @Test("no session → idle")
    func noSession() async {
        let f = Fixture()
        await f.controller.reconcile()
        #expect(f.controller.state == .idle)
    }

    @Test("state is derived from the persisted record at init, before any reconcile")
    func initialState() async {
        let (f, _) = fixture(phase: .running, firesIn: 600)
        #expect(f.controller.state == .running(breakAt: f.now.value.addingTimeInterval(600)))
    }

    @Test("running with its alarm still scheduled → running")
    func runningIntact() async {
        let (f, alarmId) = fixture(phase: .running, firesIn: 600)

        await f.controller.reconcile()

        #expect(f.controller.state == .running(breakAt: f.now.value.addingTimeInterval(600)))
        #expect(f.record.alarmId == alarmId)
    }

    @Test("break alarm ringing → breakPending")
    func breakRinging() async {
        let (f, _) = fixture(phase: .running, firesIn: -30, alerting: true)
        await f.controller.reconcile()
        #expect(f.controller.state == .breakPending)
    }

    @Test("look-away in progress with its alarm scheduled → breakActive")
    func lookingAwayIntact() async {
        let (f, _) = fixture(phase: .lookingAway, firesIn: 10)
        await f.controller.reconcile()
        #expect(f.controller.state == .breakActive(endsAt: f.now.value.addingTimeInterval(10)))
    }

    @Test("look-away that ended while the app was dead rolls straight to the next cycle")
    func lookAwayEndedWhileDead() async {
        let (f, _) = fixture(phase: .lookingAway, firesIn: -60, alarmInSystem: false)

        await f.controller.reconcile()

        #expect(f.controller.state == .running(breakAt: f.now.value.addingTimeInterval(interval)))
    }

    @Test("break alarm dismissed while the app was dead → skipped after the grace period, not a stale breakPending")
    func breakDismissedWhileDead() async {
        let (f, alarmId) = fixture(phase: .running, firesIn: -300, alarmInSystem: false)

        await f.controller.reconcile()
        #expect(f.record.alarmId == alarmId, "waits for a possible intent first")

        await f.releaseSleepsAndSettle()
        #expect(f.controller.state == .running(breakAt: f.now.value.addingTimeInterval(interval)))
    }

    @Test("an intent launching the app at the same time as reconcile still wins")
    func intentAtLaunch() async {
        let (f, alarmId) = fixture(phase: .running, firesIn: -5, alarmInSystem: false)

        await f.controller.reconcile()
        await f.controller.respond(to: .confirm, alarmId: alarmId)
        await f.releaseSleepsAndSettle()

        #expect(f.record.phase == .lookingAway)
    }

    @Test("break alarm missing before its fire time → session stops")
    func alarmLostEarly() async {
        let (f, _) = fixture(phase: .running, firesIn: 600, alarmInSystem: false)

        await f.controller.reconcile()
        await f.releaseSleepsAndSettle()

        #expect(f.controller.state == .idle)
        #expect(f.record.phase == .idle)
    }

    @Test("alarms the session doesn't own are cancelled; a ringing one is left alone")
    func orphans() async {
        let (f, alarmId) = fixture(phase: .running, firesIn: 600)
        let orphan = UUID()
        let ringingOrphan = UUID()
        f.alarms.addSystemAlarm(orphan)
        f.alarms.addSystemAlarm(ringingOrphan, isAlerting: true)

        await f.controller.reconcile()

        #expect(f.alarms.cancelled == [orphan])
        #expect(Set(f.alarms.systemAlarmIds) == [alarmId, ringingOrphan])
    }

    @Test("idle with leftover alarms from an old build → they're cancelled")
    func idleOrphans() async {
        let f = Fixture()
        let leftover = UUID()
        f.alarms.addSystemAlarm(leftover)

        await f.controller.reconcile()

        #expect(f.alarms.systemAlarmIds.isEmpty)
    }

    @Test("reconcile publishes authorizationDenied from the scheduler without prompting")
    func permission() async {
        let f = Fixture()
        f.alarms.stubAuthorization(.denied)
        await f.controller.reconcile()
        #expect(f.controller.authorizationDenied)

        f.alarms.stubAuthorization(.notDetermined)
        await f.controller.reconcile()
        #expect(f.controller.authorizationDenied == false)
    }

    @Test("overlapping reconciles on launch book exactly one alarm")
    func overlappingReconciles() async {
        let f = Fixture(schedule: .workweekOn)

        async let first: Void = f.controller.reconcile()
        async let second: Void = f.controller.reconcile()
        _ = await (first, second)

        #expect(f.alarms.scheduled.count == 1)
        #expect(f.alarms.systemAlarmIds.count == 1)
    }
}
