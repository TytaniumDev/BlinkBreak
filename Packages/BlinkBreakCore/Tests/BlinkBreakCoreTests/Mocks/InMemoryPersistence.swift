//
//  InMemoryPersistence.swift
//  BlinkBreakCoreTests
//
//  PersistenceProtocol backed by memory, so tests never touch real UserDefaults.
//

import Foundation
import Synchronization
@testable import BlinkBreakCore

final class InMemoryPersistence: PersistenceProtocol {

    private struct Storage {
        var session = SessionRecord()
        var schedule = WeeklySchedule.default
        var alarmSoundMuted = false
        var meetingSettings = MeetingSettings.default
    }

    private let storage: Mutex<Storage>

    init(
        session: SessionRecord = SessionRecord(),
        schedule: WeeklySchedule = .default,
        meetingSettings: MeetingSettings = .default
    ) {
        storage = Mutex(Storage(session: session, schedule: schedule, meetingSettings: meetingSettings))
    }

    func loadSession() -> SessionRecord { storage.withLock { $0.session } }
    func saveSession(_ record: SessionRecord) { storage.withLock { $0.session = record } }
    func loadSchedule() -> WeeklySchedule { storage.withLock { $0.schedule } }
    func saveSchedule(_ schedule: WeeklySchedule) { storage.withLock { $0.schedule = schedule } }
    func loadAlarmSoundMuted() -> Bool { storage.withLock { $0.alarmSoundMuted } }
    func saveAlarmSoundMuted(_ muted: Bool) { storage.withLock { $0.alarmSoundMuted = muted } }
    func loadMeetingSettings() -> MeetingSettings { storage.withLock { $0.meetingSettings } }
    func saveMeetingSettings(_ settings: MeetingSettings) { storage.withLock { $0.meetingSettings = settings } }
}
