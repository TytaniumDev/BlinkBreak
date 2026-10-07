//
//  AlarmKitScheduler.swift
//  BlinkBreak
//
//  Concrete `AlarmSchedulerProtocol` backed by AlarmKit's `AlarmManager.shared`.
//  This and AlarmIntents.swift are the only files that import AlarmKit; the
//  `BlinkBreakCore` package stays platform-agnostic.
//
//  The system is the source of truth: `currentAlarms()` reads
//  `AlarmManager.shared.alarms` directly, and `events` is a diff of the
//  `alarmUpdates` stream. Nothing is cached in UserDefaults.
//
//  Why `.alarm(schedule:)` and not `.timer(duration:)`: a timer-backed alarm
//  implies a countdown Live Activity that the system surfaces as a running
//  countdown before the alarm fires. A fixed-date schedule with an alert-only
//  presentation avoids that surface entirely.
//

import ActivityKit  // AlertConfiguration (alarm sounds)
import AlarmKit
import AppIntents
import BlinkBreakCore
import SwiftUI

/// AlarmKit requires a metadata type even when we don't carry any extra data.
struct BlinkBreakAlarmMetadata: AlarmMetadata {}

final class AlarmKitScheduler: AlarmSchedulerProtocol {

    let events: AsyncStream<AlarmEvent>
    private let observer: Task<Void, Never>

    init() {
        let (events, continuation) = AsyncStream.makeStream(of: AlarmEvent.self)
        self.events = events
        observer = Task {
            // The first snapshot is a baseline: alarms that vanished while the app
            // wasn't running are caught up by `SessionController.reconcile()`.
            var previous: [UUID: Bool]?
            for await alarms in AlarmManager.shared.alarmUpdates {
                let current = Dictionary(alarms.map { ($0.id, $0.state == .alerting) }) { first, _ in first }
                for (id, isAlerting) in current where isAlerting && previous?[id] != true {
                    continuation.yield(.alerting(alarmId: id))
                }
                if let previous {
                    for id in previous.keys where current[id] == nil {
                        continuation.yield(.removed(alarmId: id))
                    }
                }
                previous = current
            }
            continuation.finish()
        }
    }

    deinit {
        observer.cancel()
    }

    // MARK: - AlarmSchedulerProtocol

    func authorizationStatus() async -> AlarmAuthorizationStatus {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func schedule(_ kind: AlarmKind, at fireDate: Date, muteSound: Bool) async throws -> UUID {
        try await requestAuthorizationIfNeeded()

        let id = UUID()
        let attributes = AlarmAttributes<BlinkBreakAlarmMetadata>(
            presentation: AlarmPresentation(alert: Self.alert(for: kind)),
            tintColor: .accentColor
        )
        // The system Stop button runs `StopButtonIntent` (skip / end the break);
        // the custom secondary button runs `BreakButtonIntent` (start / end the break).
        let configuration = AlarmManager.AlarmConfiguration<BlinkBreakAlarmMetadata>.alarm(
            schedule: .fixed(fireDate),
            attributes: attributes,
            stopIntent: StopButtonIntent(alarmID: id.uuidString),
            secondaryIntent: BreakButtonIntent(alarmID: id.uuidString),
            sound: Self.sound(muted: muteSound)
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        } catch {
            throw AlarmSchedulerError.schedulingFailed(reason: String(describing: error))
        }
        return id
    }

    func cancel(alarmId: UUID) async {
        // Apple's call for silencing a ringing alarm is `stop(id:)`; `cancel(id:)`
        // removes one that hasn't fired yet. Both throw for an alarm that's
        // already gone, which is fine.
        let isAlerting = (try? AlarmManager.shared.alarms)?
            .contains { $0.id == alarmId && $0.state == .alerting } ?? false
        if isAlerting {
            try? AlarmManager.shared.stop(id: alarmId)
        } else {
            try? AlarmManager.shared.cancel(id: alarmId)
        }
    }

    func currentAlarms() async throws -> [ScheduledAlarm] {
        do {
            return try AlarmManager.shared.alarms.map {
                ScheduledAlarm(alarmId: $0.id, isAlerting: $0.state == .alerting)
            }
        } catch {
            throw AlarmSchedulerError.listingFailed(reason: String(describing: error))
        }
    }

    // MARK: - Helpers

    private func requestAuthorizationIfNeeded() async throws {
        switch await authorizationStatus() {
        case .authorized:
            return
        case .denied:
            throw AlarmSchedulerError.authorizationDenied
        case .notDetermined:
            let state: AlarmManager.AuthorizationState
            do {
                state = try await AlarmManager.shared.requestAuthorization()
            } catch {
                // The request itself failed; that isn't the user saying no.
                throw AlarmSchedulerError.schedulingFailed(reason: "authorization request failed: \(error)")
            }
            guard state == .authorized else { throw AlarmSchedulerError.authorizationDenied }
        }
    }

    private static func alert(for kind: AlarmKind) -> AlarmPresentation.Alert {
        switch kind {
        case .breakDue:
            return alert(title: "Time to look away", button: "Start break", systemImage: "eye")
        case .lookAwayDone:
            return alert(title: "Look-away complete", button: "End break", systemImage: "checkmark")
        }
    }

    private static func alert(
        title: LocalizedStringResource,
        button: LocalizedStringResource,
        systemImage: String
    ) -> AlarmPresentation.Alert {
        AlarmPresentation.Alert(
            title: title,
            secondaryButton: AlarmButton(text: button, textColor: .white, systemImageName: systemImage),
            secondaryButtonBehavior: .custom
        )
    }

    private static func sound(muted: Bool) -> AlertConfiguration.AlertSound {
        // UI tests use the system default. The iOS 26.4 simulator's SpringBoard
        // crashes (`-[AVAudioSession reporterID]: unrecognized selector`) whenever
        // an alarm plays a custom sound file, even the silent one. It can't load
        // the default tone at all, so the default is both safe and quiet there.
        if UITestSupport.isActive { return .default }
        return muted ? .named("break-alarm-silent.caf") : .named("break-alarm.caf")
    }
}
