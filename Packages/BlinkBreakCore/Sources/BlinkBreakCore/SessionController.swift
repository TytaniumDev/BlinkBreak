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
    private let connectivity: WatchConnectivityProtocol
    private let persistence: PersistenceProtocol
    private let alarm: SessionAlarmProtocol
    private let clock: @Sendable () -> Date
    private let scheduleEvaluator: ScheduleEvaluatorProtocol
    private let calendar: Calendar

    // MARK: - Init

    /// - Parameters:
    ///   - scheduler: Notification scheduler. Use `UNNotificationScheduler()` in production,
    ///     `MockNotificationScheduler()` in tests.
    ///   - connectivity: WatchConnectivity wrapper. Use `WCSessionConnectivity()` in production,
    ///     `NoopConnectivity()` in tests / on macOS.
    ///   - persistence: Session record storage. Use `UserDefaultsPersistence()` in production,
    ///     `InMemoryPersistence()` in tests.
    ///   - alarm: Extended runtime session alarm. Use `WKExtendedRuntimeSessionAlarm()` on
    ///     Watch, `NoopSessionAlarm()` on iPhone and in tests.
    ///   - clock: Closure returning "now". Defaults to `{ Date() }`. Tests pass a closure
    ///     backed by a mutable fake date so they can advance virtual time.
    public init(
        scheduler: NotificationSchedulerProtocol,
        connectivity: WatchConnectivityProtocol,
        persistence: PersistenceProtocol,
        alarm: SessionAlarmProtocol,
        scheduleEvaluator: ScheduleEvaluatorProtocol = NoopScheduleEvaluator(),
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scheduler = scheduler
        self.connectivity = connectivity
        self.persistence = persistence
        self.alarm = alarm
        self.scheduleEvaluator = scheduleEvaluator
        self.calendar = calendar
        self.clock = clock
        self.weeklySchedule = persistence.loadSchedule() ?? .empty
    }

    // MARK: - Public API (SessionControllerProtocol)

    /// Starts a new session. Transitions idle → running. Schedules the first break cascade.
    public func start() {
        // Clean up any stale state from a previous (possibly crashed) session.
        scheduler.cancelAll()

        let cycleId = UUID()
        let cycleStartedAt = clock()

        let record = SessionRecord(
            sessionActive: true,
            currentCycleId: cycleId,
            cycleStartedAt: cycleStartedAt,
            breakActiveStartedAt: nil,
            lastUpdatedAt: cycleStartedAt
        )
        persistence.save(record)

        // Schedule the single break notification for this cycle.
        scheduler.schedule(CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: cycleStartedAt))

        // Arm the Watch-side extended runtime session alarm. No-op on iPhone.
        alarm.arm(
            cycleId: cycleId,
            fireDate: cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        )

        state = .running(cycleStartedAt: cycleStartedAt)
        broadcastSnapshot(for: record)
    }

    /// Stops the current session. Transitions any-state → idle. Cancels all pending notifications
    /// and disarms the alarm.
    public func stop() {
        let now = clock()
        if let currentCycleId = persistence.load().currentCycleId {
            alarm.disarm(cycleId: currentCycleId)
        }
        scheduler.cancelAll()
        var idleRecord = SessionRecord.idle
        idleRecord.lastUpdatedAt = now
        if scheduleEvaluator.shouldBeActive(at: now, manualStopDate: nil, calendar: calendar) {
            idleRecord.manualStopDate = now
        }
        persistence.save(idleRecord)
        state = .idle
        broadcastSnapshot(for: idleRecord)
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

        // 1. Disarm the current cycle's alarm (stops any in-progress haptic loop on Watch).
        alarm.disarm(cycleId: cycleId)

        // 2. Cancel all notifications for this cycle (pending and delivered).
        scheduler.cancel(identifiers: CascadeBuilder.identifiers(for: cycleId))

        // 3. The user is starting the break. Generate a new cycleId for the NEXT cycle.
        let breakActiveStartedAt = clock()
        let nextCycleId = UUID()
        let nextCycleStartedAt = breakActiveStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)

        // 4. Schedule the "done, back to work" notification. Uses the OLD cycleId so it shares
        //    the thread-identifier with the cascade it completes — groups cleanly in Notification
        //    Center.
        scheduler.schedule(
            CascadeBuilder.buildDoneNotification(cycleId: cycleId, breakActiveStartedAt: breakActiveStartedAt)
        )

        // 5. Schedule the next cycle's single break notification.
        scheduler.schedule(
            CascadeBuilder.buildBreakNotification(cycleId: nextCycleId, cycleStartedAt: nextCycleStartedAt)
        )

        // 6. Arm the alarm for the next cycle.
        alarm.arm(
            cycleId: nextCycleId,
            fireDate: nextCycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        )

        // 7. Persist the new state. currentCycleId is the NEW one; cycleStartedAt is the NEW one.
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

        // 8. Update UI state and broadcast to the Watch.
        state = .breakActive(startedAt: breakActiveStartedAt)
        broadcastSnapshot(for: newRecord)
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
    /// and periodically by views to detect automatic state transitions (running → breakPending,
    /// breakActive → running). After reconciling persisted state, evaluates the weekly schedule
    /// to auto-start or auto-stop as appropriate.
    public func reconcileOnLaunch() async {
        reconcileState()
        evaluateSchedule()
    }

    /// Core reconciliation logic: rebuilds the in-memory `state` from the persisted record +
    /// the current clock. Extracted from `reconcileOnLaunch` so `evaluateSchedule` can run
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
            broadcastSnapshot(for: cleared)
        }

        // Case 4: break time hasn't arrived yet → running.
        let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        if now < breakFireTime {
            state = .running(cycleStartedAt: cycleStartedAt)
            // Re-arm the alarm for the remaining time in the cycle. On iPhone this is
            // a no-op (NoopSessionAlarm); on Watch it restores the extended runtime
            // session after an app kill / launch.
            alarm.arm(cycleId: currentCycleId, fireDate: breakFireTime)
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
        // Re-arm the alarm so the Watch can restart the haptic loop after an app
        // kill/relaunch during an active break. Uses breakFireTime (which is in the
        // past) — the alarm implementation's DispatchSourceTimer fires immediately
        // when the deadline is already passed, which starts the haptic loop right away.
        alarm.arm(cycleId: currentCycleId, fireDate: breakFireTime)
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
            start()
            // Mark the session as schedule-initiated so we can auto-stop it later.
            // Manual starts leave wasAutoStarted as nil/false. Two writes (start()
            // saves the record, then we patch it) to avoid changing start()'s public
            // API with an internal-only parameter.
            var updated = persistence.load()
            updated.wasAutoStarted = true
            persistence.save(updated)
        } else if !shouldBeActive && state.isActive && (record.wasAutoStarted ?? false) {
            stop()
        }
    }

    // MARK: - Incoming Watch commands

    /// Hook up the WatchConnectivity service to the controller's state. Call once, after
    /// initializing. Wires both directions:
    /// - Incoming commands (`start`, `stop`, `startBreak`) become method calls.
    /// - Incoming state snapshots become `handleRemoteSnapshot` calls.
    public func wireUpConnectivity() {
        connectivity.onCommandReceived = { [weak self] command, cycleId in
            guard let self else { return }
            Task { @MainActor in
                switch command {
                case .start:
                    self.start()
                case .stop:
                    self.stop()
                case .startBreak:
                    if let cycleId = cycleId {
                        self.handleStartBreakAction(cycleId: cycleId)
                    }
                }
            }
        }
        connectivity.onSnapshotReceived = { [weak self] snapshot in
            guard let self else { return }
            Task { @MainActor in
                self.handleRemoteSnapshot(snapshot)
            }
        }
    }

    /// Activate the underlying connectivity service. Call once at launch, before
    /// `wireUpConnectivity()`. Exposed as a method so apps don't need direct access to
    /// the `connectivity` property.
    public func activateConnectivity() {
        connectivity.activate()
    }

    /// Processes an incoming WCSession snapshot from the paired device. Implements the
    /// acknowledgment-sync rule: if a remote ack just happened (incoming `breakActiveStartedAt`
    /// newly set), cancel our delivered notification for the acked cycle and disarm our
    /// local alarm.
    ///
    /// Idempotent: calling with the same snapshot twice produces the same end state.
    /// Protected by a staleness guard: snapshots older than the local `lastUpdatedAt` are
    /// dropped so out-of-order delivery can't clobber newer state.
    public func handleRemoteSnapshot(_ snapshot: SessionSnapshot) {
        let local = persistence.load()

        // Staleness guard: ignore older-than-local snapshots.
        let localStamp = local.lastUpdatedAt ?? .distantPast
        guard snapshot.updatedAt > localStamp else { return }

        // Detect remote state changes that require local cleanup.
        let remoteAckedBreak = snapshot.breakActiveStartedAt != nil && local.breakActiveStartedAt == nil
        let remoteStopped = !snapshot.sessionActive && local.sessionActive

        if (remoteAckedBreak || remoteStopped), let cycleId = local.currentCycleId {
            scheduler.cancel(identifiers: CascadeBuilder.identifiers(for: cycleId))
            alarm.disarm(cycleId: cycleId)
            if remoteStopped {
                scheduler.cancelAll()
            }
        }

        // Persist the new snapshot locally and reconcile to update the in-memory
        // state + UI. Without reconcile, the UI wouldn't update until the next
        // 1-second tick from RootView.
        persistence.save(SessionRecord(from: snapshot))
        Task { await reconcileOnLaunch() }
    }

    // MARK: - Helpers

    private func broadcastSnapshot(for record: SessionRecord) {
        let snapshot = SessionSnapshot(
            sessionActive: record.sessionActive,
            currentCycleId: record.currentCycleId,
            cycleStartedAt: record.cycleStartedAt,
            breakActiveStartedAt: record.breakActiveStartedAt,
            updatedAt: clock()
        )
        connectivity.broadcast(snapshot)
    }
}
