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
        // already gone, which is harmless, but AlarmKit's errors don't say which
        // failure it was, so every failure is logged rather than swallowed.
        let shortId = alarmId.uuidString.prefix(8)
        let state: Alarm.State?
        do {
            guard let alarm = try AlarmManager.shared.alarms.first(where: { $0.id == alarmId }) else {
                // Already stopped (e.g. by `stopRinging`) or never booked.
                AppLogger.shared.log(.debug, "alarm \(shortId): already gone, nothing to cancel")
                return
            }
            state = alarm.state
        } catch {
            // Can't tell whether it's ringing; fall through to `cancel(id:)`.
            AppLogger.shared.log(.warning, "alarm \(shortId): listing alarms before cancel failed: \(error)")
            state = nil
        }
        let isAlerting = state == .alerting
        do {
            if isAlerting {
                try AlarmManager.shared.stop(id: alarmId)
            } else {
                try AlarmManager.shared.cancel(id: alarmId)
            }
        } catch {
            let action = isAlerting ? "stop" : "cancel"
            let stateText = state.map { String(describing: $0) } ?? "unknown"
            AppLogger.shared.log(.warning, "alarm \(shortId): \(action) failed (state=\(stateText)): \(error)")
        }
    }

    /// Silences an alarm the user just answered from its alert. Called first
    /// thing by `BreakButtonIntent`: the custom button doesn't dismiss the alarm
    /// by itself, and stopping it straight away (rather than after the session
    /// controller's queue gets to it) lets the system clear the alert on every
    /// device showing it, including a paired Apple Watch.
    static func stopRinging(alarmId: UUID) {
        do {
            try AlarmManager.shared.stop(id: alarmId)
            AppLogger.shared.log(.info, "alarm \(alarmId.uuidString.prefix(8)): stopped from its button")
        } catch {
            // Already dismissed, e.g. the user answered on the other device first.
            AppLogger.shared.log(.info, "alarm \(alarmId.uuidString.prefix(8)): stop from its button failed: \(error)")
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
        // UI tests use the system default. Observed on the iOS 26.4 simulator
        // runtime: SpringBoard crashes (`-[AVAudioSession reporterID]:
        // unrecognized selector`) whenever an alarm plays a bundled sound file,
        // even the silent one. That runtime can't load the default tone at all,
        // so the default is both safe and quiet there. Revisit when the simulator
        // runtime changes — a runtime that can load the default tone would make
        // UI-test alarms audible and may reintroduce the crash.
        if UITestSupport.isActive { return .default }
        return muted ? .named("break-alarm-silent.caf") : .named("break-alarm.caf")
    }
}
