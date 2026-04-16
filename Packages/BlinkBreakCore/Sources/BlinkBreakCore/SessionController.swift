//
//  SessionController.swift
//  BlinkBreakCore
//
//  The brain of BlinkBreak. Owns the state machine, coordinates the scheduler,
//  persistence, and Watch connectivity services, and publishes state changes to
//  any observing SwiftUI view.
//
//  Flutter analogue: this is the ChangeNotifier / Cubit / Bloc for the whole app.
//  Views consume `state` as a @Published value; they call `start()` / `stop()` etc.
//  to request transitions. Views never mutate state directly.
//
//  Dependency injection: takes every collaborator as a protocol, plus a `now` closure
//  so tests can advance virtual time without sleeping.
//

import Foundation
import Combine

/// The concrete `SessionControllerProtocol` used by both the iOS and watchOS app targets.
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

    // MARK: - Dependencies

    private let scheduler: NotificationSchedulerProtocol
    private let persistence: PersistenceProtocol
    private let clock: @Sendable () -> Date
    private let scheduleEvaluator: ScheduleEvaluatorProtocol
    private let calendar: Calendar

    // MARK: - Init

    /// - Parameters:
    ///   - scheduler: Notification scheduler. Use `UNNotificationScheduler()` in production,
    ///     `MockNotificationScheduler()` in tests.
    ///   - persistence: Session record storage. Use `UserDefaultsPersistence()` in production,
    ///     `InMemoryPersistence()` in tests.
    ///   - clock: Closure returning "now". Defaults to `{ Date() }`. Tests pass a closure
    ///     backed by a mutable fake date so they can advance virtual time.
    public init(
        scheduler: NotificationSchedulerProtocol,
        persistence: PersistenceProtocol,
        scheduleEvaluator: ScheduleEvaluatorProtocol = NoopScheduleEvaluator(),
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scheduler = scheduler
        self.persistence = persistence
        self.scheduleEvaluator = scheduleEvaluator
        self.calendar = calendar
        self.clock = clock
        self.weeklySchedule = persistence.loadSchedule() ?? .empty
    }

    // MARK: - Public API (SessionControllerProtocol)

    /// Starts a new session. Transitions idle → running. Schedules the first break cascade.
    public func start() {
        startSession(wasAutoStarted: false)
    }

    /// Core start logic. Used by both `start()` (manual) and `evaluateSchedule()` (auto).
    /// - Parameter wasAutoStarted: Pass `true` when the session is started by the weekly
    ///   schedule so it can be auto-stopped later. Manual starts pass `false`.
    private func startSession(wasAutoStarted: Bool = false) {
        // Clean up any stale state from a previous (possibly crashed) session.
        scheduler.cancelAll()

        let cycleId = UUID()
        let cycleStartedAt = clock()

        let record = SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: cycleStartedAt,
            breakActiveStartedAt: nil,
            lastUpdatedAt: cycleStartedAt,
            wasAutoStarted: wasAutoStarted ? true : nil
        )
        persistence.save(record)

        // Schedule the single break notification for this cycle.
        scheduler.schedule(CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: cycleStartedAt))

        state = .running(cycleStartedAt: cycleStartedAt)
    }

    /// Stops the current session. Transitions any-state → idle. Cancels all pending notifications.
    public func stop() {
        let now = clock()
        scheduler.cancelAll()
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

    /// Handles the user tapping "Start break" on a notification action.
    ///
    /// This method is idempotent and defends against stale acks: if the supplied cycleId
    /// doesn't match the currently-persisted cycleId (because the user is tapping an old
    /// notification that somehow survived, or the cycle has already rolled), it no-ops.
    public func handleStartBreakAction(cycleId: UUID) {
        let record = persistence.load()
        guard record.sessionActive,
              let currentCycleId = record.currentCycleId,
              currentCycleId == cycleId else {
            // Stale or no-op case. Don't mutate anything.
            return
        }

        // 1. Cancel all notifications for this cycle (pending and delivered).
        scheduler.cancel(identifiers: CascadeBuilder.identifiers(for: cycleId))

        // 2. The user is starting the break. Generate a new cycleId for the NEXT cycle.
        let breakActiveStartedAt = clock()
        let nextCycleId = UUID()
        let nextCycleStartedAt = breakActiveStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)

        // 3. Schedule the "done, back to work" notification. Uses the OLD cycleId so it shares
        //    the thread-identifier with the cascade it completes — groups cleanly in Notification
        //    Center.
        scheduler.schedule(
            CascadeBuilder.buildDoneNotification(cycleId: cycleId, breakActiveStartedAt: breakActiveStartedAt)
        )

        // 4. Schedule the next cycle's single break notification.
        scheduler.schedule(
            CascadeBuilder.buildBreakNotification(cycleId: nextCycleId, cycleStartedAt: nextCycleStartedAt)
        )

        // 5. Persist the new state. currentCycleId is the NEW one; cycleStartedAt is the NEW one.
        //    breakActiveStartedAt records the start of the current 20s window. Forward
        //    wasAutoStarted so schedule-started sessions remain eligible for auto-stop
        //    across break cycles.
        let newRecord = SessionRecord(
            sessionActive: true,
            currentCycleId: nextCycleId,
            cycleStartedAt: nextCycleStartedAt,
            breakActiveStartedAt: breakActiveStartedAt,
            lastUpdatedAt: clock(),
            wasAutoStarted: record.wasAutoStarted
        )
        persistence.save(newRecord)

        // 6. Update UI state.
        state = .breakActive(startedAt: breakActiveStartedAt)
    }

    /// Acknowledges the current break cycle from inside the app (e.g. the user tapped
    /// "Start break" on the foregrounded `BreakPendingView` instead of on a notification).
    /// Resolves the current cycleId from persistence and forwards to `handleStartBreakAction`.
    public func acknowledgeCurrentBreak() {
        guard let cycleId = persistence.load().currentCycleId else { return }
        handleStartBreakAction(cycleId: cycleId)
    }

    /// Rebuilds the in-memory `state` from the persisted record + pending notifications +
    /// the current clock. Never trusts in-memory state. Called on launch, on foreground,
    /// and on notification delivery. After reconciling persisted state, evaluates the weekly
    /// schedule to auto-start or auto-stop as appropriate.
    public func reconcile() async {
        reconcileState()
        evaluateSchedule()
    }

    /// Core reconciliation logic: rebuilds the in-memory `state` from the persisted record +
    /// the current clock. Extracted from `reconcile` so `evaluateSchedule` can run
    /// after reconciliation completes.
    private func reconcileState() {
        let record = persistence.load()
        let now = clock()

        // Case 1: no active session.
        guard record.sessionActive else {
            state = .idle
            return
        }

        // Case 2: corrupt record (sessionActive but missing fields) — recover to idle.
        guard let currentCycleId = record.currentCycleId,
              let cycleStartedAt = record.cycleStartedAt else {
            persistence.save(.idle)
            state = .idle
            return
        }

        // Case 3: if we're still inside the breakActive window, show breakActive.
        if let breakActiveStartedAt = record.breakActiveStartedAt {
            let breakActiveEnd = breakActiveStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)
            if now < breakActiveEnd {
                state = .breakActive(startedAt: breakActiveStartedAt)
                return
            }
            // breakActive has already elapsed. Clear the stale field in persistence and fall
            // through to the running/breakPending check below. The persisted cycleStartedAt
            // already points to the next cycle (set when handleStartBreakAction ran).
            var cleared = record
            cleared.breakActiveStartedAt = nil
            persistence.save(cleared)
        }

        // Case 4: break time hasn't arrived yet → running.
        let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        if now < breakFireTime {
            state = .running(cycleStartedAt: cycleStartedAt)
            return
        }

        // Case 5: break time has arrived (or passed) without a break acknowledgment.
        // State is breakPending — the user needs to acknowledge the break. This is
        // unconditional: with the single-notification design, the notification
        // either transitions from pending to delivered at break time (no overlap
        // window), so we can't distinguish "just fired" from "fired a while ago"
        // by inspecting the scheduler. Instead we rely on the persisted session
        // record: if the user never acknowledged, they're still owed a break.
        //
        // The user can always Stop the session from the breakPending screen path
        // (ack, then stop from breakActive) or by swiping away the notification and
        // reopening the app. There's no timeout-to-idle fallback.
        state = .breakPending(cycleStartedAt: cycleStartedAt)
    }

    /// Consult the schedule evaluator to auto-start or auto-stop the session.
    /// Runs after `reconcileState()` so the in-memory state reflects persistence.
    /// Only takes action when the weekly schedule is enabled — without a schedule,
    /// the evaluator has no effect (preserving existing behavior for all tests that
    /// don't inject a scheduleEvaluator).
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

}
