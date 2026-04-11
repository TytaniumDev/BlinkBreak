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
}
