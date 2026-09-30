//
//  Persistence.swift
//  BlinkBreakCore
//
//  Protocol over the three small values BlinkBreak stores — the session record,
//  the weekly schedule, and the alarm-sound preference — plus the
//  UserDefaults-backed implementation. Tests use an in-memory implementation
//  that lives in the test target.
//
//  Flutter analogue: an abstract Repository with a SharedPreferences implementation.
//

import Foundation

/// Synchronous storage for BlinkBreak's persisted values.
public protocol PersistenceProtocol: Sendable {
    /// The stored session, or an idle record if nothing (or something unreadable) is stored.
    func loadSession() -> SessionRecord
    func saveSession(_ record: SessionRecord)

    /// The stored schedule, or `WeeklySchedule.default` if none is stored.
    func loadSchedule() -> WeeklySchedule
    func saveSchedule(_ schedule: WeeklySchedule)

    /// Whether alarms play silently. Defaults to `false`.
    func loadAlarmSoundMuted() -> Bool
    func saveAlarmSoundMuted(_ muted: Bool)
}

/// The production `PersistenceProtocol`, backed by `UserDefaults`. Values are
/// JSON-encoded so they're readable in a plist dump.
public struct UserDefaultsPersistence: PersistenceProtocol {

    private enum Key {
        static let session = "BlinkBreak.Session.v2"
        static let schedule = "BlinkBreak.WeeklySchedule"
        static let alarmSoundMuted = "BlinkBreak.MuteAlarmSound"
    }

    /// Keys written by builds before the intent-driven redesign. Nothing reads
    /// them; `removeLegacyData()` deletes them.
    private static let legacyKeys = [
        "BlinkBreak.SessionRecord",
        "BlinkBreak.AcknowledgeRequestedAlarmId",
        "BlinkBreak.IntentExecutionLog",
        "blinkbreak.alarmkit.idToKind.v1"
    ]

    // UserDefaults is documented as thread-safe but isn't marked Sendable in the SDK.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSession() -> SessionRecord {
        decode(SessionRecord.self, forKey: Key.session) ?? SessionRecord()
    }

    public func saveSession(_ record: SessionRecord) {
        encode(record, forKey: Key.session)
    }

    public func loadSchedule() -> WeeklySchedule {
        decode(WeeklySchedule.self, forKey: Key.schedule) ?? .default
    }

    public func saveSchedule(_ schedule: WeeklySchedule) {
        encode(schedule, forKey: Key.schedule)
    }

    public func loadAlarmSoundMuted() -> Bool {
        defaults.bool(forKey: Key.alarmSoundMuted)
    }

    public func saveAlarmSoundMuted(_ muted: Bool) {
        defaults.set(muted, forKey: Key.alarmSoundMuted)
    }

    /// Deletes values left behind by older builds.
    public func removeLegacyData() {
        Self.legacyKeys.forEach(defaults.removeObject(forKey:))
    }

    /// Deletes everything BlinkBreak stores. Used by UI tests for a clean start.
    public func removeAll() {
        removeLegacyData()
        [Key.session, Key.schedule, Key.alarmSoundMuted].forEach(defaults.removeObject(forKey:))
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
