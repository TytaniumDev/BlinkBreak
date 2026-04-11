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

    // MARK: - Dependencies

    private let scheduler: NotificationSchedulerProtocol
    private let connectivity: WatchConnectivityProtocol
    private let persistence: PersistenceProtocol
    private let clock: @Sendable () -> Date

    // MARK: - Init

    /// - Parameters:
    ///   - scheduler: Notification scheduler. Use `UNNotificationScheduler()` in production,
    ///     `MockNotificationScheduler()` in tests.
    ///   - connectivity: WatchConnectivity wrapper. Use `WCSessionConnectivity()` in production,
    ///     `NoopConnectivity()` in tests / on macOS.
    ///   - persistence: Session record storage. Use `UserDefaultsPersistence()` in production,
    ///     `InMemoryPersistence()` in tests.
    ///   - clock: Closure returning "now". Defaults to `{ Date() }`. Tests pass a closure
    ///     backed by a mutable fake date so they can advance virtual time.
    public init(
        scheduler: NotificationSchedulerProtocol,
        connectivity: WatchConnectivityProtocol,
        persistence: PersistenceProtocol,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scheduler = scheduler
        self.connectivity = connectivity
        self.persistence = persistence
        self.clock = clock
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
            lookAwayStartedAt: nil
        )
        persistence.save(record)

        // Schedule the six-notification cascade for this cycle.
        for notification in CascadeBuilder.buildBreakCascade(cycleId: cycleId, cycleStartedAt: cycleStartedAt) {
            scheduler.schedule(notification)
        }

        state = .running(cycleStartedAt: cycleStartedAt)
        broadcastSnapshot(for: record)
    }

    /// Stops the current session. Transitions any-state → idle. Cancels all pending notifications.
    public func stop() {
        scheduler.cancelAll()
        persistence.save(.idle)
        state = .idle
        broadcastSnapshot(for: .idle)
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

        // 1. Cancel all cascade notifications for this cycle (pending and delivered).
        scheduler.cancel(identifiers: CascadeBuilder.identifiers(for: cycleId))

        // 2. The user is about to start looking away. Generate a new cycleId for the NEXT cycle.
        let lookAwayStartedAt = clock()
        let nextCycleId = UUID()
        let nextCycleStartedAt = lookAwayStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)

        // 3. Schedule the "done, back to work" notification. Uses the OLD cycleId so it shares
        //    the thread-identifier with the cascade it completes — groups cleanly in Notification
        //    Center.
        scheduler.schedule(
            CascadeBuilder.buildDoneNotification(cycleId: cycleId, lookAwayStartedAt: lookAwayStartedAt)
        )

        // 4. Schedule the next cycle's cascade. It will start firing 20 seconds + 20 minutes from now.
        for notification in CascadeBuilder.buildBreakCascade(cycleId: nextCycleId, cycleStartedAt: nextCycleStartedAt) {
            scheduler.schedule(notification)
        }

        // 5. Persist the new state. currentCycleId is the NEW one; cycleStartedAt is the NEW one.
        //    lookAwayStartedAt records the start of the current 20s window.
        let newRecord = SessionRecord(
            sessionActive: true,
            currentCycleId: nextCycleId,
            cycleStartedAt: nextCycleStartedAt,
            lookAwayStartedAt: lookAwayStartedAt
        )
        persistence.save(newRecord)

        // 6. Update UI state and broadcast to the Watch.
        state = .lookAway(lookAwayStartedAt: lookAwayStartedAt)
        broadcastSnapshot(for: newRecord)
    }

    /// Acknowledges the current break cycle from inside the app (e.g. the user tapped
    /// "Start break" on the foregrounded `BreakActiveView` instead of on a notification).
    /// Resolves the current cycleId from persistence and forwards to `handleStartBreakAction`.
    public func acknowledgeCurrentBreak() {
        guard let cycleId = persistence.load().currentCycleId else { return }
        handleStartBreakAction(cycleId: cycleId)
    }

    /// Rebuilds the in-memory `state` from the persisted record + pending notifications +
    /// the current clock. Never trusts in-memory state. Called on launch, on foreground,
    /// and periodically by views to detect automatic state transitions (running → breakActive,
    /// lookAway → running).
    public func reconcileOnLaunch() async {
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

        // Case 3: if we're still inside the lookAway window, show lookAway.
        if let lookAwayStartedAt = record.lookAwayStartedAt {
            let lookAwayEnd = lookAwayStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)
            if now < lookAwayEnd {
                state = .lookAway(lookAwayStartedAt: lookAwayStartedAt)
                return
            }
            // lookAway has already elapsed. Clear the stale field in persistence and fall
            // through to the running/breakActive check below. The persisted cycleStartedAt
            // already points to the next cycle (set when handleStartBreakAction ran).
            var cleared = record
            cleared.lookAwayStartedAt = nil
            persistence.save(cleared)
            broadcastSnapshot(for: cleared)
        }

        // Case 4: break time hasn't arrived yet → running.
        let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        if now < breakFireTime {
            state = .running(cycleStartedAt: cycleStartedAt)
            return
        }

        // Case 5: break time has arrived. Check whether any cascade notifications are still
        // pending for the current cycleId — if so, we're in breakActive waiting for ack.
        // If not, the cascade fully fired without acknowledgment and we should fall back to idle.
        let pending = Set(await scheduler.pendingIdentifiers())
        let cascadeIds = Set(CascadeBuilder.identifiers(for: currentCycleId))
        if !pending.isDisjoint(with: cascadeIds) {
            state = .breakActive(cycleStartedAt: cycleStartedAt)
        } else {
            // Nothing pending for this cycle — cascade ran out with no ack.
            persistence.save(.idle)
            state = .idle
            broadcastSnapshot(for: .idle)
        }
    }

    // MARK: - Incoming Watch commands

    /// Hook up a `WatchConnectivityProtocol` so commands from the Watch are routed here.
    /// Call once, after initializing the controller.
    public func wireUpWatchCommands() {
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
    }

    // MARK: - Helpers

    private func broadcastSnapshot(for record: SessionRecord) {
        let snapshot = SessionSnapshot(
            sessionActive: record.sessionActive,
            currentCycleId: record.currentCycleId,
            cycleStartedAt: record.cycleStartedAt,
            lookAwayStartedAt: record.lookAwayStartedAt,
            updatedAt: clock()
        )
        connectivity.broadcast(snapshot)
    }
}
