//
//  SessionController.swift
//  BlinkBreakCore
//
//  The brain of BlinkBreak. Owns the state machine, coordinates the alarm
//  scheduler and persistence, and exposes observable state to SwiftUI.
//
//  How the cycle keeps going:
//  - The alarm buttons ("Start break", "End break", Stop) run App Intents. iOS
//    runs those even when the app isn't open, and they call `respond(to:alarmId:)`
//    here, which books the next alarm. So the cycle doesn't depend on the app
//    being alive.
//  - When the app IS alive it also watches the system alarm list. The look-away
//    alarm firing rolls the cycle on by itself, and an alarm that disappears
//    with no intent reporting a tap is treated as "skipped" after a short grace
//    period.
//  - `reconcile()` (on launch / foreground) catches up on anything missed.
//  - The weekly schedule pre-books the first break alarm of the next window, so
//    automatic starts need no background execution either.
//  - Manual sessions (and Resume after a Pause) hand control back to the
//    schedule at the end of the window open when they started, or the next one.
//
//  Every transition runs on one serial queue, so transitions never interleave
//  across `await`s.
//
//  Flutter analogue: the ChangeNotifier / Cubit / Bloc for the whole app. Views
//  read `state` and call `start()` / `stop()` etc. to request transitions.
//

import Foundation
import Observation

/// Which alarm button the user tapped. Reported by the app's App Intents.
public enum AlarmResponse: String, Sendable {
    /// The custom button: "Start break" on the break alarm, "End break" on the
    /// look-away alarm.
    case confirm
    /// The system Stop button. Skips the break (or ends the look-away) and
    /// continues on the normal cadence.
    case stop
}

@MainActor
@Observable
public final class SessionController: SessionControllerProtocol {

    // MARK: - Observable state

    public private(set) var state: SessionState = .idle
    public private(set) var weeklySchedule: WeeklySchedule
    public private(set) var muteAlarmSound: Bool
    public private(set) var authorizationDenied = false

    // MARK: - Dependencies

    @ObservationIgnored private let alarms: AlarmSchedulerProtocol
    @ObservationIgnored private let persistence: PersistenceProtocol
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private let log: AppLogger

    @ObservationIgnored private let queue = SerialTaskQueue()
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var wakeDate: Date?

    // MARK: - Init

    /// - Parameters:
    ///   - alarmScheduler: `AlarmKitScheduler()` in the app, `MockAlarmScheduler()` in tests.
    ///   - persistence: `UserDefaultsPersistence()` in the app, `InMemoryPersistence()` in tests.
    ///   - calendar: Used for schedule windows.
    ///   - clock: Returns "now". Tests pass a closure over a fake date to control time.
    ///   - sleep: Suspends for a duration. Tests pass an instant or gated version.
    public init(
        alarmScheduler: AlarmSchedulerProtocol,
        persistence: PersistenceProtocol,
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        logger: AppLogger = .shared
    ) {
        self.alarms = alarmScheduler
        self.persistence = persistence
        self.calendar = calendar
        self.clock = clock
        self.sleep = sleep
        self.log = logger
        self.weeklySchedule = persistence.loadSchedule()
        self.muteAlarmSound = persistence.loadAlarmSoundMuted()
        self.state = SessionState.derive(from: persistence.loadSession(), now: clock())

        let events = alarmScheduler.events
        eventTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    deinit {
        eventTask?.cancel()
        wakeTask?.cancel()
    }

    // MARK: - Public API

    public func scheduleStatus(at date: Date) -> String? {
        weeklySchedule.statusText(at: date, calendar: calendar)
    }

    public func start() async {
        await queue.run { await self.startSession(autoStarted: false) }
    }

    public func stop() async {
        await queue.run { await self.stopSession(reason: .user) }
    }

    public var canPause: Bool {
        state.isActive && weeklySchedule.isActive(at: clock(), calendar: calendar)
    }

    public func pause() async {
        await queue.run {
            guard self.canPause,
                  let windowEnd = self.weeklySchedule.currentOrNextWindowEnd(from: self.clock(), calendar: self.calendar)
            else {
                self.log.log(.debug, "pause: not available in state \(self.state), ignoring")
                return
            }
            self.log.log(.info, "pause: until \(windowEnd)")
            await self.stopSession(reason: .user, pausedUntil: windowEnd)
        }
    }

    public func startBreak() async {
        await queue.run { await self.beginBreak(expecting: nil) }
    }

    public func takeBreakNow() async {
        await queue.run {
            let record = self.persistence.loadSession()
            guard case .running = self.state, let firesAt = record.alarmFiresAt else { return }
            let soon = self.clock().addingTimeInterval(1)
            guard soon < firesAt else { return }
            self.log.log(.info, "takeBreakNow: moving break alarm to now")
            await self.rescheduleCurrentAlarm(record, at: soon)
        }
    }

    /// Called by the alarm App Intents with the button the user tapped.
    public func respond(to response: AlarmResponse, alarmId: UUID) async {
        await queue.run {
            let record = self.persistence.loadSession()
            guard record.alarmId == alarmId else {
                // The session already moved past this alarm (e.g. the look-away
                // rolled on when it started ringing), but it may still be ringing.
                // The custom button doesn't dismiss it by itself, so stop it here.
                self.log.log(.info, "respond(\(response.rawValue)): alarm \(alarmId.short) is not current, stopping it")
                await self.alarms.cancel(alarmId: alarmId)
                return
            }
            self.log.log(.info, "respond(\(response.rawValue)): alarm \(alarmId.short) phase=\(record.phase.rawValue)")
            switch (response, record.phase) {
            case (_, .idle):
                return
            case (.confirm, .scheduled), (.confirm, .running):
                await self.beginBreak(expecting: alarmId)
            case (.confirm, .lookingAway), (.stop, _):
                await self.completeCycle(expecting: alarmId)
            }
        }
    }

    public func reconcile() async {
        await queue.run { await self.reconcileWithSystem() }
    }

    public func updateSchedule(_ schedule: WeeklySchedule) {
        persistence.saveSchedule(schedule)
        weeklySchedule = schedule
        queue.enqueue { await self.applyScheduleChange() }
    }

    public func updateAlarmSound(muted: Bool) {
        persistence.saveAlarmSoundMuted(muted)
        muteAlarmSound = muted
        queue.enqueue {
            // Re-book the pending alarm so the new sound setting applies to it.
            let record = self.persistence.loadSession()
            guard record.phase != .idle, let firesAt = record.alarmFiresAt,
                  firesAt > self.clock().addingTimeInterval(1) else { return }
            await self.rescheduleCurrentAlarm(record, at: firesAt)
        }
    }

    /// Wait until every queued transition has finished. For tests.
    func waitUntilIdle() async {
        await queue.drain()
    }

    // MARK: - Alarm events

    func handle(_ event: AlarmEvent) {
        switch event {
        case .alerting(let id):
            log.log(.info, "event: alarm \(id.short) alerting")
            queue.enqueue { await self.evaluateTimedTransitions() }
        case .removed(let id):
            log.log(.info, "event: alarm \(id.short) removed")
            checkMissingAlarmAfterGrace(id)
        }
    }

    /// An alarm we own is gone. Usually a button intent is about to report what
    /// the user tapped — wait for it, then handle the alarm only if no intent did.
    private func checkMissingAlarmAfterGrace(_ id: UUID) {
        Task {
            await sleep(BlinkBreakConstants.missingAlarmGrace)
            await queue.run { await self.handleMissingAlarm(id) }
        }
    }

    private func handleMissingAlarm(_ id: UUID) async {
        let record = persistence.loadSession()
        guard record.alarmId == id, record.phase != .idle else { return }
        let stillScheduled: Bool
        do {
            stillScheduled = try await alarms.currentAlarms().contains { $0.alarmId == id }
        } catch {
            // Can't tell whether the alarm is really gone. Leave the session alone; the next reconcile checks again.
            log.log(.warning, "alarm \(id.short) check skipped: \(error)")
            return
        }
        guard !stillScheduled else { return }
        if let firesAt = record.alarmFiresAt, clock() < firesAt {
            log.log(.warning, "alarm \(id.short) vanished before firing; stopping")
            await stopSession(reason: .error)
        } else {
            log.log(.info, "alarm \(id.short) dismissed with no button response; continuing")
            await completeCycle(expecting: id)
        }
    }

    // MARK: - Transitions (always run on `queue`)

    private enum StopReason {
        /// The user tapped Stop (or Pause).
        case user
        /// The session's window is still open, but its next break would land
        /// after the window ends. Stays off for the rest of this window.
        case windowEnding
        /// The session's window has already closed. If another window is open
        /// by now (e.g. the app wasn't opened overnight), the schedule starts it.
        case windowClosed
        /// Something went wrong (scheduling failed, alarm vanished).
        case error
    }

    /// Cancel everything and book the first break. `cycleStart` in the future
    /// pre-books a schedule window instead of starting now.
    private func startSession(autoStarted: Bool, cycleStart: Date? = nil) async {
        let previous = persistence.loadSession()
        // A user's Start replaces everything; an automatic start leaves a
        // ringing alarm (e.g. the day's last look-away) to finish ringing.
        await cancelAlarms(keepingAlerting: autoStarted)
        let start = cycleStart ?? clock()
        let firesAt = start.addingTimeInterval(BlinkBreakConstants.breakInterval)
        guard let alarmId = await scheduleAlarm(.breakDue, at: firesAt) else {
            save(SessionRecord(manualStopDate: previous.manualStopDate, pausedUntil: previous.pausedUntil))
            return
        }
        if let cycleStart {
            // Pre-booked for a later window. Keep today's manual stop / pause so
            // a schedule edit before then can't restart the session early.
            save(SessionRecord(
                phase: .scheduled,
                alarmId: alarmId,
                alarmFiresAt: firesAt,
                wasAutoStarted: true,
                manualStopDate: previous.manualStopDate,
                pausedUntil: previous.pausedUntil
            ))
            log.log(.info, "start: pre-booked for \(cycleStart), alarm=\(alarmId.short)")
            return
        }
        // Schedule-started sessions follow the live schedule. Manual ones stop at
        // the end of the window open now, or the next one to open.
        let stopAt = autoStarted ? nil : weeklySchedule.currentOrNextWindowEnd(from: start, calendar: calendar)
        save(SessionRecord(
            phase: .running,
            alarmId: alarmId,
            alarmFiresAt: firesAt,
            wasAutoStarted: autoStarted,
            scheduledStopAt: stopAt
        ))
        log.log(.info, "start: running, auto=\(autoStarted), alarm=\(alarmId.short)")
    }

    /// - Parameter pausedUntil: Set by `pause()`: show `.paused` until then.
    private func stopSession(reason: StopReason, pausedUntil: Date? = nil) async {
        let now = clock()
        // A user Stop cancels the ringing alarm too. Automatic stops leave an
        // alerting alarm alone so its sound isn't cut off mid-ring.
        await cancelAlarms(keepingAlerting: reason != .user)
        var idle = SessionRecord(pausedUntil: pausedUntil)
        if reason == .user || reason == .windowEnding, weeklySchedule.isActive(at: now, calendar: calendar) {
            // Don't let the schedule restart the session in this same window.
            idle.manualStopDate = now
        }
        save(idle)
        log.log(.info, "stop: reason=\(reason)")
        await applySchedule()
    }

    /// breakDue → look-away. `expecting` guards against a stale intent.
    private func beginBreak(expecting alarmId: UUID?) async {
        let record = persistence.loadSession()
        guard record.phase == .running || record.phase == .scheduled else { return }
        if let alarmId, alarmId != record.alarmId { return }
        if sessionWindowHasEnded(record, at: clock()) {
            // The user answered the break after the session's window ended.
            await stopSession(reason: .windowClosed)
            return
        }
        if let current = record.alarmId {
            await alarms.cancel(alarmId: current)
        }
        let endsAt = clock().addingTimeInterval(BlinkBreakConstants.lookAwayDuration)
        guard let lookAwayId = await scheduleAlarm(.lookAwayDone, at: endsAt) else {
            await stopSession(reason: .error)
            return
        }
        save(SessionRecord(
            phase: .lookingAway,
            alarmId: lookAwayId,
            alarmFiresAt: endsAt,
            wasAutoStarted: record.wasAutoStarted,
            scheduledStopAt: record.scheduledStopAt
        ))
        log.log(.info, "break: look-away until \(endsAt), alarm=\(lookAwayId.short)")
    }

    /// Finish the current cycle (break skipped, or look-away over) and book the
    /// next break — or stop, if the next break would land past the session's window.
    /// - Parameter cancelCurrent: False when the look-away alarm is ringing and
    ///   should keep ringing until the user dismisses it.
    private func completeCycle(expecting alarmId: UUID?, cancelCurrent: Bool = true) async {
        let record = persistence.loadSession()
        guard record.phase != .idle else { return }
        if let alarmId, alarmId != record.alarmId { return }
        if cancelCurrent, let current = record.alarmId {
            await alarms.cancel(alarmId: current)
        }
        let now = clock()
        let nextFire = now.addingTimeInterval(BlinkBreakConstants.breakInterval)
        if sessionWindowHasEnded(record, at: nextFire) {
            await stopSession(reason: sessionWindowHasEnded(record, at: now) ? .windowClosed : .windowEnding)
            return
        }
        guard let nextId = await scheduleAlarm(.breakDue, at: nextFire) else {
            await stopSession(reason: .error)
            return
        }
        save(SessionRecord(
            phase: .running,
            alarmId: nextId,
            alarmFiresAt: nextFire,
            wasAutoStarted: record.wasAutoStarted,
            scheduledStopAt: record.scheduledStopAt
        ))
        log.log(.info, "cycle: next break at \(nextFire), alarm=\(nextId.short)")
    }

    /// Transitions that happen because time passed rather than because of a tap.
    private func evaluateTimedTransitions() async {
        defer { refreshState() }
        var record = persistence.loadSession()
        let now = clock()
        if let pausedUntil = record.pausedUntil, now >= pausedUntil || !weeklySchedule.isEnabled {
            // The paused window ended (or the schedule was turned off): the
            // pause lapses and the schedule takes over again.
            log.log(.info, "pause lapsed")
            record.pausedUntil = nil
            save(record)
        }
        guard let firesAt = record.alarmFiresAt else { return }
        switch record.phase {
        case .scheduled where now >= firesAt.addingTimeInterval(-BlinkBreakConstants.breakInterval):
            // The pre-booked window has opened.
            record.phase = .running
            save(record)
        case .lookingAway where now >= firesAt.addingTimeInterval(BlinkBreakConstants.lookAwayCompletionMargin):
            await completeCycle(expecting: record.alarmId, cancelCurrent: false)
        default:
            break
        }
    }

    private func reconcileWithSystem() async {
        defer { refreshState() }
        await refreshAuthorization()
        await evaluateTimedTransitions()

        let record = persistence.loadSession()
        let now = clock()
        let systemAlarms: [ScheduledAlarm]?
        do {
            systemAlarms = try await alarms.currentAlarms()
        } catch {
            // A failed read isn't "no alarms": skip the orphan and missing-alarm
            // checks this time rather than act on a wrong picture.
            log.log(.warning, "reconcile: alarm list unavailable: \(error)")
            systemAlarms = nil
        }

        // Alarms we don't own come from older builds or interrupted operations.
        for alarm in systemAlarms ?? [] where alarm.alarmId != record.alarmId && !alarm.isAlerting {
            log.log(.info, "reconcile: cancelling orphaned alarm \(alarm.alarmId.short)")
            await alarms.cancel(alarmId: alarm.alarmId)
        }

        if record.phase == .idle {
            await applySchedule()
            return
        }
        // A session still going after its window closed (for example a break
        // alarm nobody answered) ends here. A pre-booked start (still `.scheduled`
        // after the promotion above) is in the future, so it's exempt.
        if record.phase != .scheduled, sessionWindowHasEnded(record, at: now) {
            await stopSession(reason: .windowClosed)
            return
        }
        if let systemAlarms, let id = record.alarmId, !systemAlarms.contains(where: { $0.alarmId == id }) {
            checkMissingAlarmAfterGrace(id)
        }
    }

    /// When idle, start or pre-book according to the weekly schedule.
    private func applySchedule() async {
        let record = persistence.loadSession()
        guard record.phase == .idle, weeklySchedule.isEnabled else { return }
        let now = clock()
        if weeklySchedule.isActive(at: now, manualStopDate: record.manualStopDate, calendar: calendar) {
            await startSession(autoStarted: true)
        } else if let next = weeklySchedule.nextWindowStart(after: now, calendar: calendar) {
            await startSession(autoStarted: true, cycleStart: next)
        }
    }

    private func applyScheduleChange() async {
        await evaluateTimedTransitions()
        let record = persistence.loadSession()
        switch record.phase {
        case .idle:
            await applySchedule()
        case .scheduled:
            // Re-book (or drop) the pre-booked start for the new schedule, keeping
            // any manual stop / pause for the current window.
            await cancelAlarms(keepingAlerting: false)
            save(SessionRecord(manualStopDate: record.manualStopDate, pausedUntil: record.pausedUntil))
            await applySchedule()
        case .running, .lookingAway:
            // A running session picks up the new schedule at its next cycle.
            break
        }
    }

    /// Persist, then refresh the derived UI state and the next timed wake-up.
    private func save(_ record: SessionRecord) {
        persistence.saveSession(record)
        refreshState()
    }

    private func refreshState() {
        let record = persistence.loadSession()
        let now = clock()
        let newState = SessionState.derive(from: record, now: now)
        if newState != state {
            state = newState
        }
        scheduleWake(for: record, now: now)
    }

    /// While the app is alive, wake up when the UI state would change on its own
    /// (a pre-booked window opens, a break comes due, a look-away ends).
    private func scheduleWake(for record: SessionRecord, now: Date) {
        let alarmTarget: Date? = {
            guard let firesAt = record.alarmFiresAt else { return nil }
            switch record.phase {
            case .idle:
                return nil
            case .scheduled:
                let cycleStart = firesAt.addingTimeInterval(-BlinkBreakConstants.breakInterval)
                return now < cycleStart ? cycleStart : firesAt
            case .running:
                return firesAt
            case .lookingAway:
                return firesAt.addingTimeInterval(BlinkBreakConstants.lookAwayCompletionMargin)
            }
        }()
        // The earliest upcoming change: the pause lapsing, or an alarm-driven one.
        let target = [record.pausedUntil, alarmTarget].compactMap { $0 }.filter { $0 > now }.min()
        guard let target, target > now else {
            wakeTask?.cancel()
            wakeTask = nil
            wakeDate = nil
            return
        }
        guard target != wakeDate else { return }
        wakeTask?.cancel()
        wakeDate = target
        wakeTask = Task { [weak self, sleep, clock] in
            // Loop in case the sleep returns before the wall clock reaches the target.
            while !Task.isCancelled {
                let remaining = target.timeIntervalSince(clock())
                guard remaining > 0 else { break }
                await sleep(.milliseconds(Int64((remaining * 1000).rounded(.up))))
            }
            guard !Task.isCancelled, let self else { return }
            self.queue.enqueue { await self.evaluateTimedTransitions() }
        }
    }
}

// MARK: - Helpers

extension SessionController {

    /// Whether `date` is past the schedule window this session belongs to.
    /// Schedule-started sessions follow the live schedule; manual ones stop at the
    /// `scheduledStopAt` captured when they started. Nothing ends while the
    /// schedule is off.
    private func sessionWindowHasEnded(_ record: SessionRecord, at date: Date) -> Bool {
        guard weeklySchedule.isEnabled else { return false }
        if record.wasAutoStarted {
            return !weeklySchedule.isActive(at: date, calendar: calendar)
        }
        guard let stopAt = record.scheduledStopAt else { return false }
        return date >= stopAt
    }

    private func refreshAuthorization() async {
        let status = await alarms.authorizationStatus()
        authorizationDenied = status == .denied
    }

    private func scheduleAlarm(_ kind: AlarmKind, at date: Date) async -> UUID? {
        do {
            let id = try await alarms.schedule(kind, at: date, muteSound: muteAlarmSound)
            authorizationDenied = false
            return id
        } catch AlarmSchedulerError.authorizationDenied {
            log.log(.warning, "schedule \(kind.rawValue): permission denied")
            authorizationDenied = true
            return nil
        } catch {
            log.log(.error, "schedule \(kind.rawValue) failed: \(error)")
            return nil
        }
    }

    /// Replace the current alarm with an identical one at `date`.
    private func rescheduleCurrentAlarm(_ record: SessionRecord, at date: Date) async {
        guard let kind = record.alarmKind else { return }
        if let current = record.alarmId {
            await alarms.cancel(alarmId: current)
        }
        guard let newId = await scheduleAlarm(kind, at: date) else {
            await stopSession(reason: .error)
            return
        }
        var updated = record
        updated.alarmId = newId
        updated.alarmFiresAt = date
        save(updated)
    }

    private func cancelAlarms(keepingAlerting: Bool) async {
        let systemAlarms: [ScheduledAlarm]
        do {
            systemAlarms = try await alarms.currentAlarms()
        } catch {
            // Fall back to the one alarm the session knows it owns. Its ringing
            // state is unknown; cutting a ring short beats leaving a duplicate
            // alarm booked. Reconcile cancels any other leftovers later.
            log.log(.warning, "cancel: alarm list unavailable, cancelling the session's alarm: \(error)")
            if let id = persistence.loadSession().alarmId {
                await alarms.cancel(alarmId: id)
            }
            return
        }
        for alarm in systemAlarms where !(keepingAlerting && alarm.isAlerting) {
            await alarms.cancel(alarmId: alarm.alarmId)
        }
    }
}

extension UUID {
    /// First 8 characters, for log lines.
    var short: String { String(uuidString.prefix(8)) }
}
