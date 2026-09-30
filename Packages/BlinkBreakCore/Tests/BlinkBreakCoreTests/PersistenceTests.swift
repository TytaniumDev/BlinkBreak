//
//  PersistenceTests.swift
//  BlinkBreakCoreTests
//
//  UserDefaultsPersistence round-trips against an isolated UserDefaults suite,
//  plus SessionRecord / SessionState derivation.
//

import Testing
@testable import BlinkBreakCore

@Suite("Persistence")
struct PersistenceTests {

    /// A fresh, empty UserDefaults suite per test.
    func makeDefaults() -> UserDefaults {
        let name = "BlinkBreakTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("defaults when nothing is stored")
    func emptyDefaults() {
        let store = UserDefaultsPersistence(defaults: makeDefaults())
        #expect(store.loadSession() == SessionRecord())
        #expect(store.loadSchedule() == .default)
        #expect(store.loadAlarmSoundMuted() == false)
    }

    @Test("session, schedule and sound round-trip")
    func roundTrip() {
        let store = UserDefaultsPersistence(defaults: makeDefaults())
        let record = SessionRecord(
            phase: .lookingAway,
            alarmId: UUID(),
            alarmFiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            wasAutoStarted: true,
            manualStopDate: Date(timeIntervalSince1970: 1_700_000_000),
            pausedUntil: Date(timeIntervalSince1970: 1_700_003_600),
            scheduledStopAt: Date(timeIntervalSince1970: 1_700_007_200)
        )
        store.saveSession(record)
        store.saveSchedule(.workweekOn)
        store.saveAlarmSoundMuted(true)

        #expect(store.loadSession() == record)
        #expect(store.loadSchedule() == .workweekOn)
        #expect(store.loadAlarmSoundMuted())
    }

    @Test("unreadable session data falls back to idle instead of crashing")
    func garbage() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "BlinkBreak.Session.v2")
        #expect(UserDefaultsPersistence(defaults: defaults).loadSession() == SessionRecord())
    }

    @Test("removeLegacyData deletes old keys and keeps current ones")
    func legacyCleanup() {
        let defaults = makeDefaults()
        let store = UserDefaultsPersistence(defaults: defaults)
        defaults.set(Data(), forKey: "BlinkBreak.SessionRecord")
        defaults.set("x", forKey: "BlinkBreak.AcknowledgeRequestedAlarmId")
        store.saveAlarmSoundMuted(true)

        store.removeLegacyData()

        #expect(defaults.object(forKey: "BlinkBreak.SessionRecord") == nil)
        #expect(defaults.object(forKey: "BlinkBreak.AcknowledgeRequestedAlarmId") == nil)
        #expect(store.loadAlarmSoundMuted())
    }

    @Test("removeAll resets everything")
    func removeAll() {
        let store = UserDefaultsPersistence(defaults: makeDefaults())
        store.saveSession(SessionRecord(phase: .running, alarmId: UUID(), alarmFiresAt: Date()))
        store.saveSchedule(.workweekOn)
        store.saveAlarmSoundMuted(true)

        store.removeAll()

        #expect(store.loadSession() == SessionRecord())
        #expect(store.loadSchedule() == .default)
        #expect(store.loadAlarmSoundMuted() == false)
    }
}

@Suite("SessionState — derivation")
struct SessionStateDerivationTests {

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let interval = BlinkBreakConstants.breakInterval

    func record(_ phase: SessionRecord.Phase, firesIn seconds: TimeInterval) -> SessionRecord {
        SessionRecord(phase: phase, alarmId: UUID(), alarmFiresAt: now.addingTimeInterval(seconds))
    }

    @Test("idle and incomplete records are idle")
    func idle() {
        #expect(SessionState.derive(from: SessionRecord(), now: now) == .idle)
        #expect(SessionState.derive(from: SessionRecord(phase: .running), now: now) == .idle)
    }

    @Test("running before and after the break time")
    func running() {
        #expect(SessionState.derive(from: record(.running, firesIn: 60), now: now)
                == .running(breakAt: now.addingTimeInterval(60)))
        #expect(SessionState.derive(from: record(.running, firesIn: 0), now: now) == .breakPending)
    }

    @Test("a pre-booked start is idle until its window opens")
    func scheduled() {
        #expect(SessionState.derive(from: record(.scheduled, firesIn: interval + 60), now: now) == .idle)
        #expect(SessionState.derive(from: record(.scheduled, firesIn: interval), now: now)
                == .running(breakAt: now.addingTimeInterval(interval)))
    }

    @Test("a pause shows paused until it lapses, on idle and pre-booked records")
    func paused() {
        let until = now.addingTimeInterval(600)
        #expect(SessionState.derive(from: SessionRecord(pausedUntil: until), now: now) == .paused(until: until))
        var preBooked = record(.scheduled, firesIn: 86_400)
        preBooked.pausedUntil = until
        #expect(SessionState.derive(from: preBooked, now: now) == .paused(until: until))
        #expect(SessionState.derive(from: SessionRecord(pausedUntil: now), now: now) == .idle)
        #expect(SessionState.paused(until: until).isActive == false)
    }

    @Test("looking away is breakActive")
    func lookingAway() {
        #expect(SessionState.derive(from: record(.lookingAway, firesIn: 10), now: now)
                == .breakActive(endsAt: now.addingTimeInterval(10)))
    }

    @Test("alarmKind follows the phase")
    func alarmKind() {
        #expect(SessionRecord().alarmKind == nil)
        #expect(record(.scheduled, firesIn: 0).alarmKind == .breakDue)
        #expect(record(.running, firesIn: 0).alarmKind == .breakDue)
        #expect(record(.lookingAway, firesIn: 0).alarmKind == .lookAwayDone)
    }
}
