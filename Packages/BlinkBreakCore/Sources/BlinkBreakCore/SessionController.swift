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

    // MARK: - Dependencies

    private let alarmScheduler: AlarmSchedulerProtocol
    private let persistence: PersistenceProtocol
    private let clock: @Sendable () -> Date
    private let scheduleEvaluator: ScheduleEvaluatorProtocol
    private let calendar: Calendar

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
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.alarmScheduler = alarmScheduler
        self.persistence = persistence
        self.scheduleEvaluator = scheduleEvaluator
        self.calendar = calendar
        self.clock = clock
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
            } catch {
                // Authorization not granted, scheduling failed — stay idle.
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
        }
    }

    /// Stops the current session. Transitions any-state → idle. Cancels all alarms.
    public func stop() {
        let now = clock()
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
        let now = clock()
        let remaining = max(1, cycleStartedAt
            .addingTimeInterval(BlinkBreakConstants.breakInterval)
            .timeIntervalSince(now))
        Task { [weak self] in
            guard let self else { return }
            await self.alarmScheduler.cancel(alarmId: currentAlarmId)
            let newId: UUID
            do {
                newId = try await self.alarmScheduler.scheduleCountdown(
                    duration: remaining,
                    kind: .breakDue,
                    muteSound: muted
                )
            } catch { return }
            // Re-check session is still active before persisting; stop() may have
            // fired while the async cancel/schedule was in flight.
            var record = self.persistence.load()
            guard record.sessionActive else {
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
        await reconcileState()
        evaluateSchedule()
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
            return
        }

        switch kind {
        case .breakDue:
            // User acknowledged the break. Schedule the look-away countdown.
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
