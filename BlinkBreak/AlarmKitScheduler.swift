//
//  AlarmKitScheduler.swift
//  BlinkBreak
//
//  Concrete `AlarmSchedulerProtocol` implementation backed by AlarmKit's
//  `AlarmManager.shared`. iOS 26+ only.
//
//  This is the only file in the codebase that imports AlarmKit. The
//  `BlinkBreakCore` package is platform-agnostic by design.
//

import Foundation
import AlarmKit
import SwiftUI
import BlinkBreakCore

/// Marker metadata for our alarms. AlarmKit requires a Metadata generic on the
/// configuration value even when we don't carry any extra data.
public struct BlinkBreakAlarmMetadata: AlarmMetadata {
    public init() {}
}

@available(iOS 26.0, *)
public final class AlarmKitScheduler: AlarmSchedulerProtocol, @unchecked Sendable {

    private let lock = NSLock()
    /// Maps the alarm UUIDs we've scheduled to their semantic kind so we can
    /// translate AlarmKit `[Alarm]` snapshots back into our `AlarmEvent` vocabulary.
    private var idToKind: [UUID: AlarmKind] = [:]

    public let events: AsyncStream<AlarmEvent>
    private let eventContinuation: AsyncStream<AlarmEvent>.Continuation
    private var observerTask: Task<Void, Never>?

    public init() {
        var cont: AsyncStream<AlarmEvent>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.eventContinuation = cont

        // Subscribe to AlarmKit's update stream and translate each delta into our
        // `.fired` / `.dismissed` event vocabulary.
        observerTask = Task { [weak self] in
            var lastAlerting: Set<UUID> = []
            var lastKnown: Set<UUID> = []
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                let nowAlerting = Set(alarms.filter { $0.state == .alerting }.map { $0.id })
                let nowKnown = Set(alarms.map(\.id))
                let known = self.snapshotMapping()

                // Newly alerting → `.fired`
                for id in nowAlerting.subtracting(lastAlerting) {
                    if let kind = known[id] {
                        self.eventContinuation.yield(.fired(alarmId: id, kind: kind))
                    }
                }

                // Disappeared from the system entirely → `.dismissed`. Either the user
                // tapped Stop or we cancelled it programmatically.
                for id in lastKnown.subtracting(nowKnown) {
                    if let kind = known[id] {
                        self.eventContinuation.yield(.dismissed(alarmId: id, kind: kind))
                        self.forgetMapping(id: id)
                    }
                }

                lastAlerting = nowAlerting
                lastKnown = nowKnown
            }
        }
    }

    deinit {
        observerTask?.cancel()
        eventContinuation.finish()
    }

    private func snapshotMapping() -> [UUID: AlarmKind] {
        lock.lock(); defer { lock.unlock() }
        return idToKind
    }

    private func rememberMapping(id: UUID, kind: AlarmKind) {
        lock.lock(); defer { lock.unlock() }
        idToKind[id] = kind
    }

    private func forgetMapping(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        idToKind.removeValue(forKey: id)
    }

    // MARK: - AlarmSchedulerProtocol

    public func requestAuthorizationIfNeeded() async throws -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let state = try await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        @unknown default:
            return false
        }
    }

    public func scheduleCountdown(duration: TimeInterval, kind: AlarmKind) async throws -> UUID {
        // Authorization gate.
        let authorized = (try? await requestAuthorizationIfNeeded()) ?? false
        guard authorized else {
            throw AlarmSchedulerError.authorizationDenied
        }

        let id = UUID()
        let title: LocalizedStringResource
        let buttonText: LocalizedStringResource
        let buttonImage: String
        switch kind {
        case .breakDue:
            title = "Time to look away"
            buttonText = "Start break"
            buttonImage = "eye"
        case .lookAwayDone:
            title = "Look-away complete"
            buttonText = "Done"
            buttonImage = "checkmark"
        }

        let stopButton = AlarmButton(
            text: buttonText,
            textColor: .white,
            systemImageName: buttonImage
        )
        let alert = AlarmPresentation.Alert(title: title, stopButton: stopButton)
        let attributes = AlarmAttributes<BlinkBreakAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .blue
        )
        let configuration = AlarmManager.AlarmConfiguration<BlinkBreakAlarmMetadata>.timer(
            duration: duration,
            attributes: attributes
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        } catch {
            throw AlarmSchedulerError.schedulingFailed(reason: String(describing: error))
        }

        rememberMapping(id: id, kind: kind)
        return id
    }

    public func cancel(alarmId: UUID) async {
        do {
            try AlarmManager.shared.cancel(id: alarmId)
        } catch {
            // Cancelling a non-existent alarm is fine — the user may have already dismissed it.
        }
        forgetMapping(id: alarmId)
    }

    public func cancelAll() async {
        let mapping = snapshotMapping()
        for id in mapping.keys {
            await cancel(alarmId: id)
        }
    }

    public func currentAlarms() async -> [ScheduledAlarmInfo] {
        let mapping = snapshotMapping()
        return mapping.map { ScheduledAlarmInfo(alarmId: $0.key, kind: $0.value) }
    }
}
