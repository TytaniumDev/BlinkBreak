//
//  Persistence.swift
//  BlinkBreakCore
//
//  Protocol abstraction over SessionRecord storage, plus a real UserDefaults-backed
//  implementation and an in-memory one for tests.
//
//  Flutter analogue: think of this as an abstract Repository with a
//  SharedPreferencesRepository and an InMemoryRepository for testing.
//

import Foundation

// MARK: - Protocol

/// Read/write a single `SessionRecord`. Synchronous, small payload.
///
/// Tests depend on this protocol; real app code uses `UserDefaultsPersistence`.
public protocol PersistenceProtocol: Sendable {
    /// Load the current record. Returns `SessionRecord.idle` if nothing is stored.
    func load() -> SessionRecord

    /// Persist the given record. Errors are swallowed — UserDefaults writes essentially
    /// never fail on disk, and there's no meaningful recovery path if they do.
    func save(_ record: SessionRecord)

    /// Erase any stored record. Equivalent to `save(.idle)`.
    func clear()

    /// Load the persisted weekly schedule, or `nil` if none has been saved yet.
    /// Callers should fall back to `WeeklySchedule.default` on `nil`.
    func loadSchedule() -> WeeklySchedule?

    /// Persist the given weekly schedule. Independent of the session record so
    /// existing users upgrade cleanly without a migration.
    func saveSchedule(_ schedule: WeeklySchedule)
}

// MARK: - Real implementation

/// The production implementation of `PersistenceProtocol`, backed by `UserDefaults.standard`.
///
/// Session data is JSON-encoded and stored under a single key. We encode as JSON (via
/// `JSONEncoder`) instead of using `NSKeyedArchiver` because JSON is human-readable in the
/// UserDefaults plist dump and easier to debug from the command line.
///
/// Marked `@unchecked Sendable` because `UserDefaults` is thread-safe for reads and writes
/// even though it hasn't yet adopted the `Sendable` protocol in the SDK.
public final class UserDefaultsPersistence: PersistenceProtocol, @unchecked Sendable {

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        key: String = BlinkBreakConstants.sessionRecordKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> SessionRecord {
        // If no data has ever been written, return the idle record. Same for malformed data —
        // we prefer a silent recovery-to-idle over crashing the app on a decoding error.
        guard let data = defaults.data(forKey: key) else { return .idle }
        return (try? decoder.decode(SessionRecord.self, from: data)) ?? .idle
    }

    public func save(_ record: SessionRecord) {
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }

    public func loadSchedule() -> WeeklySchedule? {
        guard let data = defaults.data(forKey: BlinkBreakConstants.weeklyScheduleKey) else { return nil }
        return try? decoder.decode(WeeklySchedule.self, from: data)
    }

    public func saveSchedule(_ schedule: WeeklySchedule) {
        guard let data = try? encoder.encode(schedule) else { return }
        defaults.set(data, forKey: BlinkBreakConstants.weeklyScheduleKey)
    }
}

// MARK: - In-memory implementation (for tests)

/// A test-only `PersistenceProtocol` that stores the record in memory instead of
/// touching real UserDefaults. Used by unit tests to avoid polluting the dev machine's
/// UserDefaults domain.
public final class InMemoryPersistence: PersistenceProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var record: SessionRecord
    private var schedule: WeeklySchedule?

    public init(initial: SessionRecord = .idle) {
        self.record = initial
    }

    public func load() -> SessionRecord {
        lock.lock()
        defer { lock.unlock() }
        return record
    }

    public func save(_ record: SessionRecord) {
        lock.lock()
        defer { lock.unlock() }
        self.record = record
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        self.record = .idle
    }

    public func loadSchedule() -> WeeklySchedule? {
        lock.lock()
        defer { lock.unlock() }
        return schedule
    }

    public func saveSchedule(_ schedule: WeeklySchedule) {
        lock.lock()
        defer { lock.unlock() }
        self.schedule = schedule
    }
}
