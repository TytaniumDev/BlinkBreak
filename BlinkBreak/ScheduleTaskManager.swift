//
//  ScheduleTaskManager.swift
//  BlinkBreak
//
//  Manages background schedule checks via BGAppRefreshTask so the app can
//  auto-start a session when a weekly-schedule window opens. Lives in the app
//  target (not BlinkBreakCore) because BGTaskScheduler is a UIKit-only API.
//
//  Flutter analogue: a platform channel handler that registers WorkManager tasks.
//

import BackgroundTasks
import BlinkBreakCore

final class ScheduleTaskManager {

    private let persistence: PersistenceProtocol
    private let evaluator: ScheduleEvaluatorProtocol
    private let controllerProvider: @MainActor () -> SessionController?

    init(
        persistence: PersistenceProtocol,
        evaluator: ScheduleEvaluatorProtocol,
        controllerProvider: @escaping @MainActor () -> SessionController?
    ) {
        self.persistence = persistence
        self.evaluator = evaluator
        self.controllerProvider = controllerProvider
    }

    // MARK: - BGTask Registration

    /// Register the background task handler early -- must be called before the app
    /// finishes launching (i.e., in `didFinishLaunchingWithOptions`). The handler
    /// is a static method because `BGTaskScheduler.shared.register` must happen
    /// before `UIApplication` returns from launch, before any instance is available.
    static func registerBackgroundTaskHandler(
        persistence: PersistenceProtocol,
        controllerProvider: @escaping @MainActor () -> SessionController?
    ) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BlinkBreakConstants.scheduleTaskId,
            using: nil
        ) { task in
            guard let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundTask(bgTask, persistence: persistence, controllerProvider: controllerProvider)
        }
    }

    private static func handleBackgroundTask(
        _ task: BGAppRefreshTask,
        persistence: PersistenceProtocol,
        controllerProvider: @escaping @MainActor () -> SessionController?
    ) {
        let workTask = Task { @MainActor in
            if let controller = controllerProvider() {
                await controller.reconcile()
            }
            guard !Task.isCancelled else { return }

            // Re-schedule the next background task for the next transition date.
            let evaluator = ScheduleEvaluator(schedule: {
                persistence.loadSchedule() ?? .empty
            })
            guard let nextDate = evaluator.nextTransitionDate(from: Date(), calendar: .current) else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BlinkBreakConstants.scheduleTaskId)
                task.setTaskCompleted(success: true)
                return
            }
            let request = BGAppRefreshTaskRequest(identifier: BlinkBreakConstants.scheduleTaskId)
            request.earliestBeginDate = nextDate
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                // Not actionable -- foreground reconciliation is the reliable path.
            }
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            workTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Scheduling

    func reschedule() {
        guard let nextDate = evaluator.nextTransitionDate(from: Date(), calendar: .current) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BlinkBreakConstants.scheduleTaskId)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: BlinkBreakConstants.scheduleTaskId)
        request.earliestBeginDate = nextDate
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Not actionable -- foreground reconciliation is the reliable path.
        }
    }

    func cancelAll() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BlinkBreakConstants.scheduleTaskId)
    }
}
