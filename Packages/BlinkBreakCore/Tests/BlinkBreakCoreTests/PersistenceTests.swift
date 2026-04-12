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
            lookAwayStartedAt: Date(timeIntervalSince1970: 123_477)
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
            lookAwayStartedAt: nil
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
            lookAwayStartedAt: Date(timeIntervalSince1970: 1_700_000_100)
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
            lookAwayStartedAt: nil,
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

    @Test("SessionRecord.init(from: SessionSnapshot) copies updatedAt into lastUpdatedAt")
    func initFromSnapshot() {
        let cycleId = UUID()
        let cycleStart = Date(timeIntervalSince1970: 1_700_000_000)
        let lookAwayStart = Date(timeIntervalSince1970: 1_700_000_100)
        let snap = SessionSnapshot(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: cycleStart,
            lookAwayStartedAt: lookAwayStart,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let record = SessionRecord(from: snap)
        #expect(record.sessionActive == true)
        #expect(record.currentCycleId == cycleId)
        #expect(record.cycleStartedAt == cycleStart)
        #expect(record.lookAwayStartedAt == lookAwayStart)
        #expect(record.lastUpdatedAt == Date(timeIntervalSince1970: 1_700_000_200))
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
}
