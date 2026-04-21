//
//  SessionController.swift
//  BlinkBreakCore
//
//  The brain of BlinkBreak. Owns the state machine, coordinates the alarm
//  scheduler and persistence, and publishes state changes to observing SwiftUI views.
//
//  Cycle chaining is event-driven: AlarmSchedulerProtocol emits .fired and
//  .dismissed events as the system delivers alarms and the user acknowledges them.
//  We subscribe in init and react.
//
//  Flutter analogue: this is the ChangeNotifier / Cubit / Bloc for the whole app.
//  Views consume `state` as a @Published value; they call `start()` / `stop()` etc.
//  to request transitions. Views never mutate state directly.
//

import Foundation
import Combine

/// The concrete `SessionControllerProtocol` used by the iOS app target.
///
/// Marked `@MainActor` so SwiftUI observation of `state` is thread-safe without manual
/// dispatch. All state mutations happen on the main actor.
@MainActor
public final class SessionController: ObservableObject, SessionControllerProtocol {

    // MARK: - Published state

    /// The current session state. Views observe this via @ObservedObject / @StateObject.
    @Published public private(set) var state: SessionState = .idle

    /// The current weekly schedule. Views observe this to display schedule settings.
    @Published public private(set) var weeklySchedule: WeeklySchedule = .empty

    /// Whether the alarm sound is muted. Loaded from persistence on init.
    @Published public private(set) var muteAlarmSound: Bool = false

    /// True when the AlarmKit authorization prompt has been denied. Views check this
    /// to swap the idle UI for a "go to Settings" prompt.
    @Published public private(set) var authorizationDenied: Bool = false

    // MARK: - Dependencies

    private let alarmScheduler: AlarmSchedulerProtocol
    private let persistence: PersistenceProtocol
    private let clock: @Sendable () -> Date
    private let scheduleEvaluator: ScheduleEvaluatorProtocol
    private let calendar: Calendar
    private let logBuffer: LogBuffer

    private var eventTask: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - alarmScheduler: AlarmKit wrapper. Use `AlarmKitScheduler()` in production,
    ///     `MockAlarmScheduler()` in tests.
    ///   - persistence: Session record storage. Use `UserDefaultsPersistence()` in production,
    ///     `InMemoryPersistence()` in tests.
    ///   - clock: Closure returning "now". Defaults to `{ Date() }`. Tests pass a closure
    ///     backed by a mutable fake date so they can advance virtual time.
    public init(
        alarmScheduler: AlarmSchedulerProtocol,
        persistence: PersistenceProtocol,
        scheduleEvaluator: ScheduleEvaluatorProtocol = NoopScheduleEvaluator(),
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { Date() },
        logBuffer: LogBuffer = .shared
    ) {
        self.alarmScheduler = alarmScheduler
        self.persistence = persistence
        self.scheduleEvaluator = scheduleEvaluator
        self.calendar = calendar
        self.clock = clock
        self.logBuffer = logBuffer
        self.weeklySchedule = persistence.loadSchedule() ?? .empty
        self.muteAlarmSound = persistence.loadAlarmSoundMuted()

        // Subscribe to alarm events. The Task hops to the main actor for each event so
        // state mutations are isolated correctly.
        let stream = alarmScheduler.events
        self.eventTask = Task { @MainActor [weak self] in
            for await event in stream {
                self?.handleAlarmEvent(event)
            }
        }
    }

    deinit {
        eventTask?.cancel()
    }

    // MARK: - Public API (SessionControllerProtocol)

    /// Starts a new session. Transitions idle → running. Schedules the first break alarm.
    public func start() {
        startSession(wasAutoStarted: false)
    }

    /// Core start logic. Used by both `start()` (manual) and `evaluateSchedule()` (auto).
    private func startSession(wasAutoStarted: Bool = false) {
        logBuffer.log(.info, "start: beginning session (auto=\(wasAutoStarted))")
        Task { [weak self] in
            guard let self else { return }
            await self.alarmScheduler.cancelAll()

            let cycleId = UUID()
            let cycleStartedAt = self.clock()

            let alarmId: UUID
            do {
                alarmId = try await self.alarmScheduler.scheduleCountdown(
                    duration: BlinkBreakConstants.breakInterval,
                    kind: .breakDue,
                    muteSound: self.muteAlarmSound
                )
            } catch AlarmSchedulerError.authorizationDenied {
                self.logBuffer.log(.warning, "start: authorization denied")
                self.authorizationDenied = true
                return
            } catch {
                self.logBuffer.log(.error, "start: scheduling failed: \(error)")
                return
            }

            let record = SessionRecord(
                sessionActive: true,
                currentCycleId: cycleId,
                cycleStartedAt: cycleStartedAt,
                breakActiveStartedAt: nil,
                lastUpdatedAt: cycleStartedAt,
                wasAutoStarted: wasAutoStarted ? true : nil,
                currentAlarmId: alarmId
            )
            self.persistence.save(record)
            self.state = .running(cycleStartedAt: cycleStartedAt)
            self.authorizationDenied = false
            self.logBuffer.log(.info, "start: running, alarm=\(alarmId.uuidString.prefix(8))")
        }
    }

    /// Stops the current session. Transitions any-state → idle. Cancels all alarms.
    public func stop() {
        let now = clock()
        logBuffer.log(.info, "stop: from state \(state.description)")
        Task { [weak self] in
            await self?.alarmScheduler.cancelAll()
        }
        var idleRecord = SessionRecord.idle
        idleRecord.lastUpdatedAt = now
        if scheduleEvaluator.shouldBeActive(at: now, manualStopDate: nil, calendar: calendar) {
            idleRecord.manualStopDate = now
        }
        persistence.save(idleRecord)
        state = .idle
    }

    /// Replace the weekly schedule, persist it, and update the published property.
    public func updateSchedule(_ schedule: WeeklySchedule) {
        persistence.saveSchedule(schedule)
        weeklySchedule = schedule
    }

    /// Update the alarm-sound mute preference. Reschedules the current alarm if running.
    public func updateAlarmSound(muted: Bool) {
        persistence.saveAlarmSoundMuted(muted)
        muteAlarmSound = muted
        // Only reschedule during .running. In .breakActive the look-away alarm is
        // already firing and lasts at most 20 s; the next cycle's alarm will pick up
        // the new value from self.muteAlarmSound. In .breakPending the break alarm
        // is already alerting on-screen, so there is nothing useful to reschedule.
        guard case .running(let cycleStartedAt) = state,
              let currentAlarmId = persistence.load().currentAlarmId else { return }
        let remaining = max(1, cycleStartedAt
            .addingTimeInterval(BlinkBreakConstants.breakInterval)
            .timeIntervalSince(clock()))
        logBuffer.log(.info, "updateAlarmSound: muted=\(muted), rescheduling \(Int(remaining))s")
        replaceRunningAlarm(previousAlarmId: currentAlarmId, duration: remaining, muteSound: muted)
    }

    /// Cancel the current alarm and reschedule it to fire in 1 second. Wired to the
    /// "Take break now" button; no-op outside the `.running` state.
    public func triggerBreakNow() {
        guard case .running = state,
              let currentAlarmId = persistence.load().currentAlarmId else { return }
        logBuffer.log(.info, "triggerBreakNow: rescheduling break-due alarm to 1s")
        replaceRunningAlarm(previousAlarmId: currentAlarmId, duration: 1, muteSound: muteAlarmSound)
    }

    /// Cancel the break-due alarm currently attached to the running session and schedule
    /// a replacement with new timing. Used by both `updateAlarmSound(muted:)` and
    /// `triggerBreakNow()`. If `stop()` or a concurrent call changes `currentAlarmId`
    /// while we're awaiting the scheduler, the replacement is cancelled and the record
    /// left untouched.
    private func replaceRunningAlarm(previousAlarmId: UUID, duration: TimeInterval, muteSound: Bool) {
        Task { [weak self] in
            guard let self else { return }
            await self.alarmScheduler.cancel(alarmId: previousAlarmId)
            let newId: UUID
            do {
                newId = try await self.alarmScheduler.scheduleCountdown(
                    duration: duration,
                    kind: .breakDue,
                    muteSound: muteSound
                )
            } catch AlarmSchedulerError.authorizationDenied {
                self.logBuffer.log(.error, "replaceRunningAlarm: authorization denied — stopping session")
                self.authorizationDenied = true
                self.stop()
                return
            } catch {
                // Cancel already succeeded but reschedule failed — the session is now
                // in a zombie state where no break alarm will ever fire. Stop cleanly
                // rather than leaving the UI claiming we're running.
                self.logBuffer.log(.error, "replaceRunningAlarm: reschedule failed, stopping session: \(error)")
                self.stop()
                return
            }
            var record = self.persistence.load()
            guard record.sessionActive, record.currentAlarmId == previousAlarmId else {
                await self.alarmScheduler.cancel(alarmId: newId)
                return
            }
            record.currentAlarmId = newId
            self.persistence.save(record)
        }
    }

    /// Acknowledges the current break cycle from inside the app (e.g. the user tapped
    /// "Start break" on the foregrounded `BreakPendingView` instead of on the alarm UI).
    /// Synthesizes a dismissed event for the current break alarm.
    public func acknowledgeCurrentBreak() {
        guard let alarmId = persistence.load().currentAlarmId else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.alarmScheduler.cancel(alarmId: alarmId)
            await MainActor.run {
                self.handleAlarmEvent(.dismissed(alarmId: alarmId, kind: .breakDue))
            }
        }
    }

    /// Rebuilds the in-memory `state` from the persisted record + the alarm scheduler's
    /// current set of scheduled alarms + the current clock. Never trusts in-memory state.
    /// Called on launch, on foreground, and on periodic ticks.
    public func reconcile() async {
        await refreshAuthorization()
        await reconcileState()
        evaluateSchedule()
        logBuffer.log(.info, "reconcile: state=\(state.description), authDenied=\(authorizationDenied)")
    }

    /// Query the scheduler's authorization state and publish whether it's denied.
    /// On `.notDetermined`, this will trigger the system prompt the first time; on
    /// subsequent calls it's a read.
    public func refreshAuthorization() async {
        do {
            let granted = try await alarmScheduler.requestAuthorizationIfNeeded()
            authorizationDenied = !granted
        } catch AlarmSchedulerError.authorizationDenied {
            authorizationDenied = true
        } catch {
            // Transient scheduler error — don't flip the UI to permission-denied on a
            // one-off failure. Leave `authorizationDenied` unchanged; a later reconcile
            // will re-query.
            logBuffer.log(.warning, "refreshAuthorization: transient error, leaving state unchanged: \(error)")
        }
    }

    // MARK: - Reconciliation

    private func reconcileState() async {
        let record = persistence.load()
        let now = clock()

        // Case 1: no active session.
        guard record.sessionActive else {
            state = .idle
            return
        }

        // Case 2: corrupt record (sessionActive but missing fields) → recover to idle.
        guard let _ = record.currentCycleId,
              let cycleStartedAt = record.cycleStartedAt else {
            persistence.save(.idle)
            state = .idle
            return
        }

        // What's actually scheduled in the system right now?
        let scheduled = await alarmScheduler.currentAlarms()
        let activeAlarm = record.currentAlarmId.flatMap { id in
            scheduled.first(where: { $0.alarmId == id })
        }

        if let alarm = activeAlarm {
            // If the alarm is currently alerting (system alert UI is up), we're
            // mid-transition between scheduled-for-later and user-dismissed. Surface
            // the appropriate "alerting now" state so the in-app UI matches.
            if alarm.isAlerting {
                switch alarm.kind {
                case .breakDue:
                    state = .breakPending(cycleStartedAt: cycleStartedAt)
                case .lookAwayDone:
                    // Look-away alarm is alerting — the cycle is about to roll. Stay
                    // in breakActive until the dismissed event drives the transition.
                    if let breakActiveStartedAt = record.breakActiveStartedAt {
                        state = .breakActive(startedAt: breakActiveStartedAt)
                    } else {
                        state = .running(cycleStartedAt: cycleStartedAt)
                    }
                }
                return
            }
            switch alarm.kind {
            case .breakDue:
                state = .running(cycleStartedAt: cycleStartedAt)
            case .lookAwayDone:
                if let breakActiveStartedAt = record.breakActiveStartedAt {
                    state = .breakActive(startedAt: breakActiveStartedAt)
                } else {
                    state = .running(cycleStartedAt: cycleStartedAt)
                }
            }
            return
        }

        // No alarm scheduled. If we're inside the breakActive window per persistence,
        // the alarm fired while we were killed — show breakPending so the user can ack
        // (or continue the look-away if they already did, depending on the data).
        if let breakActiveStartedAt = record.breakActiveStartedAt {
            let breakActiveEnd = breakActiveStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)
            if now < breakActiveEnd {
                state = .breakActive(startedAt: breakActiveStartedAt)
                return
            }
            // breakActive elapsed without us hearing the dismiss. Clear and fall through.
            var cleared = record
            cleared.breakActiveStartedAt = nil
            persistence.save(cleared)
        }

        // breakPending fallback: the break alarm fired while killed and the user never
        // acknowledged. The persisted cycleStartedAt is past its 20-minute window.
        let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        if now >= breakFireTime {
            state = .breakPending(cycleStartedAt: cycleStartedAt)
            return
        }

        // Otherwise we're between events with no scheduled alarm — the system lost the
        // alarm somehow. Stop the session so the user can restart cleanly.
        var idleRecord = SessionRecord.idle
        idleRecord.lastUpdatedAt = now
        persistence.save(idleRecord)
        state = .idle
    }

    /// Consult the schedule evaluator to auto-start or auto-stop the session.
    /// Runs after `reconcileState()` so the in-memory state reflects persistence.
    private func evaluateSchedule() {
        guard weeklySchedule.isEnabled else { return }
        let record = persistence.load()
        let now = clock()
        let shouldBeActive = scheduleEvaluator.shouldBeActive(
            at: now,
            manualStopDate: record.manualStopDate,
            calendar: calendar
        )
        if shouldBeActive && state == .idle {
            startSession(wasAutoStarted: true)
        } else if !shouldBeActive && state.isActive && (record.wasAutoStarted ?? false) {
            stop()
        }
    }

    // MARK: - Alarm event handling

    private func handleAlarmEvent(_ event: AlarmEvent) {
        switch event {
        case let .fired(_, kind):
            handleFired(kind: kind)
        case let .dismissed(alarmId, kind):
            handleDismissed(alarmId: alarmId, kind: kind)
        }
    }

    private func handleFired(kind: AlarmKind) {
        logBuffer.log(.info, "fired: kind=\(kind.rawValue)")
        let record = persistence.load()
        guard record.sessionActive,
              let cycleStartedAt = record.cycleStartedAt else { return }
        switch kind {
        case .breakDue:
            // Break alarm is showing the alert UI. State is breakPending until the user
            // dismisses (which we treat as "Start break").
            state = .breakPending(cycleStartedAt: cycleStartedAt)
        case .lookAwayDone:
            // Look-away alarm is showing the alert UI. We don't change state here;
            // SwiftUI continues to show the lookAway countdown UI until dismissal
            // (which rolls to the next cycle). The state stays at breakActive — the
            // alarm UI is the system's responsibility.
            break
        }
    }

    private func handleDismissed(alarmId: UUID, kind: AlarmKind) {
        let record = persistence.load()
        guard record.sessionActive,
              record.currentAlarmId == alarmId,
              record.currentCycleId != nil,
              record.cycleStartedAt != nil else {
            logBuffer.log(.debug, "dismissed: ignored stale alarm \(alarmId.uuidString.prefix(8))")
            return
        }

        switch kind {
        case .breakDue:
            // User acknowledged the break. Schedule the look-away countdown.
            logBuffer.log(.info, "dismissed breakDue: scheduling look-away")
            Task { [weak self] in
                guard let self else { return }
                let breakActiveStartedAt = self.clock()
                let lookAwayAlarmId: UUID
                do {
                    lookAwayAlarmId = try await self.alarmScheduler.scheduleCountdown(
                        duration: BlinkBreakConstants.lookAwayDuration,
                        kind: .lookAwayDone,
                        muteSound: self.muteAlarmSound
                    )
                } catch {
                    self.logBuffer.log(.error, "dismissed breakDue: look-away schedule failed, stopping: \(error)")
                    self.stop()
                    return
                }
                var newRecord = self.persistence.load()
                newRecord.breakActiveStartedAt = breakActiveStartedAt
                newRecord.lastUpdatedAt = self.clock()
                newRecord.currentAlarmId = lookAwayAlarmId
                self.persistence.save(newRecord)
                self.state = .breakActive(startedAt: breakActiveStartedAt)
            }
        case .lookAwayDone:
            // Look-away period over. Roll to a new cycle.
            logBuffer.log(.info, "dismissed lookAwayDone: rolling to next cycle")
            Task { [weak self] in
                guard let self else { return }
                let nextCycleId = UUID()
                let nextCycleStartedAt = self.clock()
                let nextAlarmId: UUID
                do {
                    nextAlarmId = try await self.alarmScheduler.scheduleCountdown(
                        duration: BlinkBreakConstants.breakInterval,
                        kind: .breakDue,
                        muteSound: self.muteAlarmSound
                    )
                } catch {
                    self.logBuffer.log(.error, "dismissed lookAwayDone: next-cycle schedule failed, stopping: \(error)")
                    self.stop()
                    return
                }
                let newRecord = SessionRecord(
                    sessionActive: true,
                    currentCycleId: nextCycleId,
                    cycleStartedAt: nextCycleStartedAt,
                    breakActiveStartedAt: nil,
                    lastUpdatedAt: nextCycleStartedAt,
                    wasAutoStarted: record.wasAutoStarted,
                    currentAlarmId: nextAlarmId
                )
                self.persistence.save(newRecord)
                self.state = .running(cycleStartedAt: nextCycleStartedAt)
            }
        }
    }
}
