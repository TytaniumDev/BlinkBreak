//
//  SessionControllerTests.swift
//  BlinkBreakCoreTests
//
//  State-machine tests for SessionController, using the AlarmKit mock and
//  virtual time. Public API calls are awaited directly — the controller runs
//  every transition on a serial queue, so no sleeps are needed. Alarm events
//  (which arrive on a stream) use `settle()`.
//
//  Written in Swift Testing (`import Testing`), not legacy XCTest.
//

import Testing
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — state machine")
struct SessionControllerTests {

    typealias Fixture = SessionControllerFixture
    let interval = BlinkBreakConstants.breakInterval
    let lookAway = BlinkBreakConstants.lookAwayDuration

    // MARK: - start()

    @Test("start() goes idle → running with the break due one interval from now")
    func startRuns() async {
        let f = Fixture()
        #expect(f.controller.state == .idle)

        await f.controller.start()

        #expect(f.controller.state == .running(breakAt: f.now.value.addingTimeInterval(interval)))
    }

    @Test("start() books exactly one break alarm and persists it")
    func startBooksAlarm() async {
        let f = Fixture()
        await f.controller.start()

        #expect(f.alarms.scheduled.count == 1)
        let call = f.alarms.scheduled[0]
        #expect(call.kind == .breakDue)
        #expect(call.fireDate == f.now.value.addingTimeInterval(interval))
        #expect(f.record == SessionRecord(phase: .running, alarmId: call.alarmId, alarmFiresAt: call.fireDate))
    }

    @Test("start() cancels alarms left over from earlier sessions")
    func startCancelsLeftovers() async {
        let f = Fixture()
        let orphan = UUID()
        f.alarms.addSystemAlarm(orphan)

        await f.controller.start()

        #expect(f.alarms.cancelled.contains(orphan))
        #expect(f.alarms.systemAlarmIds == [f.record.alarmId!])
    }

    @Test("start() passes the mute preference to the scheduler")
    func startPassesMute() async {
        let f = Fixture()
        f.controller.updateAlarmSound(muted: true)
        await f.controller.start()
        #expect(f.alarms.lastScheduled?.muteSound == true)
    }

    @Test("start() with permission denied stays idle and flags authorizationDenied")
    func startDenied() async {
        let f = Fixture()
        f.alarms.stubAuthorization(.denied)

        await f.controller.start()

        #expect(f.controller.state == .idle)
        #expect(f.controller.authorizationDenied)
        #expect(f.record.phase == .idle)
    }

    @Test("start() that fails to schedule stays idle")
    func startFails() async {
        let f = Fixture()
        f.alarms.failNextSchedule(with: .schedulingFailed(reason: "boom"))

        await f.controller.start()

        #expect(f.controller.state == .idle)
        #expect(f.controller.authorizationDenied == false)
    }

    // MARK: - stop()

    @Test("stop() goes to idle, cancels every alarm, persists idle")
    func stopStops() async {
        let f = Fixture()
        let alarm = await f.startRunning()

        await f.controller.stop()

        #expect(f.controller.state == .idle)
        #expect(f.alarms.cancelled.contains(alarm))
        #expect(f.alarms.systemAlarmIds.isEmpty)
        #expect(f.record.phase == .idle)
    }

    @Test("stop() also cancels an alarm that's ringing")
    func stopCancelsAlerting() async {
        let f = Fixture()
        let alarm = await f.startRunning()
        f.advance(by: interval)
        f.alarms.simulateAlerting(alarm)
        await f.settle()

        await f.controller.stop()

        #expect(f.alarms.systemAlarmIds.isEmpty)
    }

    @Test("Stop tapped while start is still scheduling wins: no session is revived")
    func stopDuringStart() async {
        let f = Fixture()
        let gate = ManualSleeper()
        f.alarms.setBeforeSchedule { await gate.sleep(.zero) }

        let starting = Task { await f.controller.start() }
        while gate.pendingCount == 0 { await Task.yield() }
        let stopping = Task { await f.controller.stop() }
        await Task.yield()
        f.alarms.setBeforeSchedule(nil)
        gate.releaseAll()
        await starting.value
        await stopping.value

        #expect(f.controller.state == .idle)
        #expect(f.record.phase == .idle)
        #expect(f.alarms.systemAlarmIds.isEmpty)
    }

    // MARK: - Break flow

    @Test("the break coming due shows breakPending")
    func breakComesDue() async {
        let f = Fixture()
        let alarm = await f.startRunning()

        f.advance(by: interval)
        f.alarms.simulateAlerting(alarm)
        await f.settle()

        #expect(f.controller.state == .breakPending)
    }

    @Test("the UI reaches breakPending on time even without an alerting event")
    func breakComesDueWithoutEvent() async {
        let f = Fixture()
        await f.startRunning()

        f.advance(by: interval)
        await f.releaseSleepsAndSettle()

        #expect(f.controller.state == .breakPending)
    }

    @Test("in-app startBreak() books the look-away and shows breakActive")
    func inAppStartBreak() async {
        let f = Fixture()
        let breakAlarm = await f.startRunning()
        f.advance(by: interval)

        await f.controller.startBreak()

        let endsAt = f.now.value.addingTimeInterval(lookAway)
        #expect(f.controller.state == .breakActive(endsAt: endsAt))
        #expect(f.alarms.cancelled.contains(breakAlarm))
        #expect(f.alarms.lastScheduled?.kind == .lookAwayDone)
        #expect(f.alarms.lastScheduled?.fireDate == endsAt)
        #expect(f.record.phase == .lookingAway)
    }

    @Test("startBreak() while idle does nothing")
    func startBreakIdle() async {
        let f = Fixture()
        await f.controller.startBreak()
        #expect(f.alarms.scheduled.isEmpty)
        #expect(f.controller.state == .idle)
    }

    // MARK: - Alarm buttons (App Intents)

    @Test("\"Start break\" on the break alarm books the look-away")
    func confirmBreakAlarm() async {
        let f = Fixture()
        let alarm = await f.startRunning()
        f.advance(by: interval)

        await f.controller.respond(to: .confirm, alarmId: alarm)

        #expect(f.record.phase == .lookingAway)
        #expect(f.alarms.lastScheduled?.kind == .lookAwayDone)
    }

    @Test("Stop on the break alarm skips the look-away and books the next break")
    func stopBreakAlarm() async {
        let f = Fixture()
        let alarm = await f.startRunning()
        f.advance(by: interval)

        await f.controller.respond(to: .stop, alarmId: alarm)

        let nextFire = f.now.value.addingTimeInterval(interval)
        #expect(f.controller.state == .running(breakAt: nextFire))
        #expect(f.alarms.lastScheduled?.kind == .breakDue)
        #expect(f.alarms.scheduled.allSatisfy { $0.kind == .breakDue })
    }

    @Test("\"End break\" on the look-away alarm books the next break")
    func confirmLookAwayAlarm() async {
        let f = Fixture()
        let lookAwayAlarm = await f.startLookingAway()
        f.advance(by: lookAway)

        await f.controller.respond(to: .confirm, alarmId: lookAwayAlarm)

        #expect(f.controller.state == .running(breakAt: f.now.value.addingTimeInterval(interval)))
        #expect(f.record.phase == .running)
    }

    @Test("Stop on the look-away alarm also books the next break")
    func stopLookAwayAlarm() async {
        let f = Fixture()
        let lookAwayAlarm = await f.startLookingAway()
        f.advance(by: lookAway)

        await f.controller.respond(to: .stop, alarmId: lookAwayAlarm)

        #expect(f.record.phase == .running)
    }

    @Test("a button response for an alarm the session no longer owns is ignored")
    func staleResponse() async {
        let f = Fixture()
        let first = await f.startRunning()
        await f.controller.stop()
        await f.startRunning()
        let before = f.record

        await f.controller.respond(to: .confirm, alarmId: first)

        #expect(f.record == before)
    }

    @Test("a button response while idle is ignored")
    func responseWhileIdle() async {
        let f = Fixture()
        await f.controller.respond(to: .stop, alarmId: UUID())
        #expect(f.alarms.scheduled.isEmpty)
    }

    @Test("when the app is alive, the look-away alarm ringing rolls to the next cycle but keeps ringing")
    func lookAwayAlertRolls() async {
        let f = Fixture()
        let lookAwayAlarm = await f.startLookingAway()
        f.advance(by: lookAway + BlinkBreakConstants.lookAwayCompletionMargin)

        f.alarms.simulateAlerting(lookAwayAlarm)
        await f.settle()

        #expect(f.record.phase == .running)
        #expect(f.alarms.systemAlarmIds.contains(lookAwayAlarm))
        #expect(f.alarms.cancelled.contains(lookAwayAlarm) == false)
    }

    @Test("\"End break\" arriving after the app already rolled on doesn't roll twice")
    func noDoubleRoll() async {
        let f = Fixture()
        let lookAwayAlarm = await f.startLookingAway()
        f.advance(by: lookAway + BlinkBreakConstants.lookAwayCompletionMargin)
        f.alarms.simulateAlerting(lookAwayAlarm)
        await f.settle()
        let afterRoll = f.record

        await f.controller.respond(to: .confirm, alarmId: lookAwayAlarm)

        #expect(f.record == afterRoll)
    }

    @Test("the look-away ending on time rolls on even without an alerting event")
    func lookAwayEndsWithoutEvent() async {
        let f = Fixture()
        await f.startLookingAway()

        f.advance(by: lookAway + BlinkBreakConstants.lookAwayCompletionMargin)
        await f.releaseSleepsAndSettle()

        #expect(f.record.phase == .running)
    }

    // MARK: - Alarm removed with no button response

    @Test("an alarm dismissed with no intent response is treated as skipped after the grace period")
    func removalFallback() async {
        let f = Fixture()
        let alarm = await f.startRunning()
        f.advance(by: interval)

        f.alarms.simulateRemoval(alarm)
        await f.settle()
        #expect(f.record.alarmId == alarm, "nothing happens during the grace period")

        await f.releaseSleepsAndSettle()
        #expect(f.record.phase == .running)
        #expect(f.record.alarmId != alarm)
    }

    @Test("an intent arriving within the grace period wins over the fallback")
    func intentBeatsFallback() async {
        let f = Fixture()
        let alarm = await f.startRunning()
        f.advance(by: interval)

        f.alarms.simulateRemoval(alarm)
        await f.settle()
        await f.controller.respond(to: .confirm, alarmId: alarm)
        await f.releaseSleepsAndSettle()

        #expect(f.record.phase == .lookingAway)
        #expect(f.alarms.scheduled.filter { $0.kind == .lookAwayDone }.count == 1)
    }

    @Test("an alarm that vanishes before it fires stops the session")
    func vanishedEarly() async {
        let f = Fixture()
        let alarm = await f.startRunning()

        f.alarms.simulateRemoval(alarm)
        await f.releaseSleepsAndSettle()

        #expect(f.controller.state == .idle)
    }

    @Test("removal of an alarm the controller replaced itself is ignored")
    func removalOfReplacedAlarm() async {
        let f = Fixture()
        let original = await f.startRunning()
        await f.controller.takeBreakNow()
        let replaced = f.record

        f.alarms.simulateRemoval(original)
        await f.releaseSleepsAndSettle()

        #expect(f.record == replaced)
    }

    // MARK: - takeBreakNow()

    @Test("takeBreakNow() moves the break alarm to one second from now")
    func takeBreakNow() async {
        let f = Fixture()
        let original = await f.startRunning()

        await f.controller.takeBreakNow()

        let soon = f.now.value.addingTimeInterval(1)
        #expect(f.alarms.cancelled.contains(original))
        #expect(f.alarms.lastScheduled?.fireDate == soon)
        #expect(f.record.alarmId == f.alarms.lastScheduled?.alarmId)
        #expect(f.record.alarmFiresAt == soon)
    }

    @Test("takeBreakNow() while idle does nothing")
    func takeBreakNowIdle() async {
        let f = Fixture()
        await f.controller.takeBreakNow()
        #expect(f.alarms.scheduled.isEmpty)
    }

    // MARK: - Alarm sound

    @Test("muteAlarmSound defaults to false and updateAlarmSound persists it immediately")
    func muteDefaults() async {
        let f = Fixture()
        #expect(f.controller.muteAlarmSound == false)

        f.controller.updateAlarmSound(muted: true)

        #expect(f.controller.muteAlarmSound)
        #expect(f.persistence.loadAlarmSoundMuted())
    }

    @Test("changing the sound while idle schedules nothing")
    func muteWhileIdle() async {
        let f = Fixture()
        f.controller.updateAlarmSound(muted: true)
        await f.settle()
        #expect(f.alarms.scheduled.isEmpty)
    }

    @Test("changing the sound while running re-books the same fire time with the new sound")
    func muteWhileRunning() async {
        let f = Fixture()
        let original = await f.startRunning()
        let firesAt = f.record.alarmFiresAt

        f.controller.updateAlarmSound(muted: true)
        await f.settle()

        #expect(f.alarms.cancelled.contains(original))
        #expect(f.alarms.lastScheduled?.muteSound == true)
        #expect(f.alarms.lastScheduled?.fireDate == firesAt)
        #expect(f.record.alarmId == f.alarms.lastScheduled?.alarmId)
    }

    // MARK: - Full loop

    @Test("full loop: start → break due → Start break → End break → running")
    func fullLoop() async {
        let f = Fixture()
        let breakAlarm = await f.startRunning()

        f.advance(by: interval)
        f.alarms.simulateAlerting(breakAlarm)
        await f.settle()
        #expect(f.controller.state == .breakPending)

        await f.controller.respond(to: .confirm, alarmId: breakAlarm)
        guard case .breakActive = f.controller.state else {
            Issue.record("expected breakActive, got \(f.controller.state)")
            return
        }

        let lookAwayAlarm = f.record.alarmId!
        f.advance(by: lookAway)
        await f.controller.respond(to: .confirm, alarmId: lookAwayAlarm)

        #expect(f.controller.state == .running(breakAt: f.now.value.addingTimeInterval(interval)))
        #expect(f.alarms.systemAlarmIds == [f.record.alarmId!])
    }
}
