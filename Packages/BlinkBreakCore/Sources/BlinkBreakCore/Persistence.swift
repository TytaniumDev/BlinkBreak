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

    /// Load the persisted alarm-sound mute preference. Returns `false` (sound on) if
    /// never saved.
    func loadAlarmSoundMuted() -> Bool

    /// Persist the alarm-sound mute preference.
    func saveAlarmSoundMuted(_ muted: Bool)

    /// Read the "acknowledge this alarm" marker written by `DismissAlarmIntent`
    /// when the user taps the secondary "Start break" / "End break" button.
    /// Returns the alarm UUID the user wanted to acknowledge, or `nil` if no
    /// ack is pending. Scoped to one alarm so a stale entry from a previous
    /// alarm can't be mistakenly consumed for a different one.
    ///
    /// `SessionController.handleDismissed` consumes the marker (load + clear)
    /// and treats absence-of-marker as the default skip path — that makes the
    /// AlarmKit race where the dismissed event arrives before the intent
    /// finishes running harmless instead of scheduling a surprise look-away.
    func loadAcknowledgeRequestedAlarmId() -> UUID?

    /// Set or clear the acknowledge marker. Pass `nil` to clear. Callers in
    /// `SessionController.handleDismissed` always clear after reading so the
    /// marker is consumed exactly once.
    func saveAcknowledgeRequestedAlarmId(_ id: UUID?)

    /// Append an intent-execution log entry. AlarmKit's `LiveActivityIntent`s
    /// can run in a separate intent-host process where `LogBuffer.shared` is
    /// its own per-process singleton (invisible to the main app's breadcrumb
    /// stream and to Sentry bug reports). The intents append here instead so
    /// the main app can drain the queue and emit each entry into its own
    /// `LogBuffer` as soon as it next runs `handleDismissed`. Implementations
    /// must bound the queue at `BlinkBreakConstants.intentExecutionLogCapacity`
    /// to keep UserDefaults small.
    func appendIntentExecutionLog(_ entry: IntentExecutionLogEntry)

    /// Atomically read and clear all intent-execution log entries. Returns
    /// entries in insertion order (oldest first). Callers (typically
    /// `SessionController.handleDismissed`) re-emit each into `LogBuffer`.
    func drainIntentExecutionLog() -> [IntentExecutionLogEntry]
}

/// A single intent-execution event captured by `SkipBreakIntent` or
/// `DismissAlarmIntent`, persisted to UserDefaults so it survives the
/// intent-host process boundary and shows up in the main app's Sentry
/// breadcrumbs when `SessionController.handleDismissed` drains the queue.
public struct IntentExecutionLogEntry: Codable, Sendable {
    public let timestamp: Date
    /// Short, stable identifier of the intent type (e.g. "SkipBreakIntent").
    public let intent: String
    /// Free-text description of what the intent did. Kept short — this lands
    /// in Sentry breadcrumbs which have a tight per-line budget.
    public let message: String

    public init(timestamp: Date, intent: String, message: String) {
        self.timestamp = timestamp
        self.intent = intent
        self.message = message
    }
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

    public func loadAlarmSoundMuted() -> Bool {
        defaults.bool(forKey: BlinkBreakConstants.alarmSoundMutedKey)
    }

    public func saveAlarmSoundMuted(_ muted: Bool) {
        defaults.set(muted, forKey: BlinkBreakConstants.alarmSoundMutedKey)
    }

    public func loadAcknowledgeRequestedAlarmId() -> UUID? {
        guard let string = defaults.string(forKey: BlinkBreakConstants.acknowledgeRequestedAlarmIdKey) else {
            return nil
        }
        return UUID(uuidString: string)
    }

    public func saveAcknowledgeRequestedAlarmId(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: BlinkBreakConstants.acknowledgeRequestedAlarmIdKey)
        } else {
            defaults.removeObject(forKey: BlinkBreakConstants.acknowledgeRequestedAlarmIdKey)
        }
    }

    // The intent-execution log isn't cross-process atomic — UserDefaults
    // doesn't expose a compare-and-swap primitive. In practice the intents
    // only run in response to a single user tap on the alarm UI, so we'd
    // need two intents to fire concurrently for a clash to be possible.
    // Even if it happened, losing a single diagnostic entry is acceptable;
    // the entries are advisory, not load-bearing for any state machine.
    public func appendIntentExecutionLog(_ entry: IntentExecutionLogEntry) {
        var existing = decodedIntentExecutionLog()
        existing.append(entry)
        if existing.count > BlinkBreakConstants.intentExecutionLogCapacity {
            existing.removeFirst(existing.count - BlinkBreakConstants.intentExecutionLogCapacity)
        }
        guard let data = try? encoder.encode(existing) else { return }
        defaults.set(data, forKey: BlinkBreakConstants.intentExecutionLogKey)
    }

    public func drainIntentExecutionLog() -> [IntentExecutionLogEntry] {
        let entries = decodedIntentExecutionLog()
        if !entries.isEmpty {
            defaults.removeObject(forKey: BlinkBreakConstants.intentExecutionLogKey)
        }
        return entries
    }

    private func decodedIntentExecutionLog() -> [IntentExecutionLogEntry] {
        guard let data = defaults.data(forKey: BlinkBreakConstants.intentExecutionLogKey) else { return [] }
        return (try? decoder.decode([IntentExecutionLogEntry].self, from: data)) ?? []
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
    private var alarmSoundMuted: Bool = false
    private var acknowledgeRequestedAlarmId: UUID?
    private var intentExecutionLog: [IntentExecutionLogEntry] = []

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

    public func loadAlarmSoundMuted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return alarmSoundMuted
    }

    public func saveAlarmSoundMuted(_ muted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        alarmSoundMuted = muted
    }

    public func loadAcknowledgeRequestedAlarmId() -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        return acknowledgeRequestedAlarmId
    }

    public func saveAcknowledgeRequestedAlarmId(_ id: UUID?) {
        lock.lock()
        defer { lock.unlock() }
        acknowledgeRequestedAlarmId = id
    }

    public func appendIntentExecutionLog(_ entry: IntentExecutionLogEntry) {
        lock.lock()
        defer { lock.unlock() }
        intentExecutionLog.append(entry)
        if intentExecutionLog.count > BlinkBreakConstants.intentExecutionLogCapacity {
            intentExecutionLog.removeFirst(intentExecutionLog.count - BlinkBreakConstants.intentExecutionLogCapacity)
        }
    }

    public func drainIntentExecutionLog() -> [IntentExecutionLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        let entries = intentExecutionLog
        intentExecutionLog.removeAll()
        return entries
    }
}
