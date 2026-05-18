//
//  PersistenceTests.swift
//  BlinkBreakCoreTests
//
//  Sanity tests for InMemoryPersistence and SessionRecord Codable round-tripping.
//

import Testing
@testable import BlinkBreakCore

@Suite("Persistence + SessionRecord")
struct PersistenceTests {

    @Test("InMemoryPersistence default is idle")
    func defaultIsIdle() {
        let store = InMemoryPersistence()
        #expect(store.load() == .idle)
    }

    @Test("InMemoryPersistence save/load round-trip")
    func roundTrip() {
        let store = InMemoryPersistence()
        let record = SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: Date(timeIntervalSince1970: 123_456),
            breakActiveStartedAt: Date(timeIntervalSince1970: 123_477)
        )

        store.save(record)

        #expect(store.load() == record)
    }

    @Test("InMemoryPersistence clear returns to idle")
    func clearReturnsToIdle() {
        let store = InMemoryPersistence(initial: SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: Date(),
            breakActiveStartedAt: nil
        ))

        store.clear()

        #expect(store.load() == .idle)
    }

    @Test("SessionRecord is Codable round-trippable")
    func codableRoundTrip() throws {
        let original = SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(uuidString: "11111111-2222-3333-4444-555555555555"),
            cycleStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            breakActiveStartedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)

        #expect(decoded == original)
    }

    @Test("SessionRecord round-trips lastUpdatedAt through JSON")
    func lastUpdatedAtRoundTrip() throws {
        let when = Date(timeIntervalSince1970: 1_700_001_234)
        let record = SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            breakActiveStartedAt: nil,
            lastUpdatedAt: when
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
        #expect(decoded.lastUpdatedAt == when)
    }

    @Test("SessionRecord decodes legacy JSON without lastUpdatedAt")
    func legacyRecordDecodes() throws {
        let legacyJSON = Data("""
        {
            "sessionActive": true,
            "currentCycleId": "11111111-2222-3333-4444-555555555555",
            "cycleStartedAt": 1700000000
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: legacyJSON)
        #expect(decoded.sessionActive == true)
        #expect(decoded.lastUpdatedAt == nil)
    }

    @Test("SessionRecord without manualStopDate decodes cleanly (backward compat)")
    func sessionRecordManualStopBackwardCompat() throws {
        let legacyJSON = """
        {"sessionActive":true,"currentCycleId":"550E8400-E29B-41D4-A716-446655440000","cycleStartedAt":1700000000}
        """
        let data = Data(legacyJSON.utf8)
        let record = try JSONDecoder().decode(SessionRecord.self, from: data)
        #expect(record.sessionActive == true)
        #expect(record.manualStopDate == nil)
    }

    @Test("SessionRecord with manualStopDate round-trips through JSON")
    func sessionRecordManualStopDateRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var record = SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: now
        )
        record.manualStopDate = now.addingTimeInterval(3600)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
        #expect(decoded.manualStopDate == record.manualStopDate)
    }

    @Test("SessionRecord.idle has nil manualStopDate")
    func sessionRecordIdleManualStopDate() {
        #expect(SessionRecord.idle.manualStopDate == nil)
    }

    @Test("InMemoryPersistence loadSchedule returns nil when nothing saved")
    func loadScheduleDefaultNil() {
        let persistence = InMemoryPersistence()
        #expect(persistence.loadSchedule() == nil)
    }

    @Test("InMemoryPersistence schedule round-trips through save/load")
    func scheduleRoundTrip() {
        let persistence = InMemoryPersistence()
        let schedule = WeeklySchedule.default
        persistence.saveSchedule(schedule)
        let loaded = persistence.loadSchedule()
        #expect(loaded == schedule)
    }

    @Test("InMemoryPersistence clear does not affect schedule")
    func clearDoesNotAffectSchedule() {
        let persistence = InMemoryPersistence()
        persistence.saveSchedule(.default)
        persistence.clear()
        #expect(persistence.loadSchedule() == .default)
    }

    // MARK: - Alarm sound mute

    @Test("InMemoryPersistence.loadAlarmSoundMuted() defaults to false")
    func inMemoryMutedDefaultsFalse() {
        let p = InMemoryPersistence()
        #expect(p.loadAlarmSoundMuted() == false)
    }

    @Test("InMemoryPersistence round-trips alarm sound muted flag")
    func inMemoryMutedRoundTrip() {
        let p = InMemoryPersistence()
        p.saveAlarmSoundMuted(true)
        #expect(p.loadAlarmSoundMuted() == true)
        p.saveAlarmSoundMuted(false)
        #expect(p.loadAlarmSoundMuted() == false)
    }

    // MARK: - Intent-execution log

    @Test("drainIntentExecutionLog returns empty when nothing was appended")
    func intentLogEmptyByDefault() {
        let p = InMemoryPersistence()
        #expect(p.drainIntentExecutionLog().isEmpty)
    }

    @Test("appendIntentExecutionLog preserves insertion order and drain clears")
    func intentLogAppendAndDrain() {
        let p = InMemoryPersistence()
        let entry1 = IntentExecutionLogEntry(timestamp: Date(timeIntervalSince1970: 1), intent: "A", message: "first")
        let entry2 = IntentExecutionLogEntry(timestamp: Date(timeIntervalSince1970: 2), intent: "B", message: "second")
        p.appendIntentExecutionLog(entry1)
        p.appendIntentExecutionLog(entry2)

        let drained = p.drainIntentExecutionLog()
        #expect(drained.count == 2)
        #expect(drained[0].message == "first")
        #expect(drained[1].message == "second")
        // Drain clears so subsequent calls yield empty.
        #expect(p.drainIntentExecutionLog().isEmpty)
    }

    @Test("appendIntentExecutionLog caps at intentExecutionLogCapacity, drops oldest")
    func intentLogBounded() {
        let p = InMemoryPersistence()
        let cap = BlinkBreakConstants.intentExecutionLogCapacity
        for i in 0..<(cap + 5) {
            p.appendIntentExecutionLog(
                IntentExecutionLogEntry(timestamp: Date(timeIntervalSince1970: TimeInterval(i)), intent: "I", message: "msg-\(i)")
            )
        }
        let drained = p.drainIntentExecutionLog()
        #expect(drained.count == cap)
        // Oldest entries (msg-0 through msg-4) should have been dropped.
        #expect(drained.first?.message == "msg-5")
        #expect(drained.last?.message == "msg-\(cap + 4)")
    }

    @Test("IntentExecutionLogEntry is Codable round-trippable")
    func intentLogEntryCodable() throws {
        let entry = IntentExecutionLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            intent: "SkipBreakIntent",
            message: "cancel alarm=12345678 (system Stop)"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(IntentExecutionLogEntry.self, from: data)
        #expect(decoded.timestamp == entry.timestamp)
        #expect(decoded.intent == entry.intent)
        #expect(decoded.message == entry.message)
    }
}
