//
//  ScheduleTaskManager.swift
//  BlinkBreak
//
//  Manages background schedule checks via BGAppRefreshTask and schedules a local
//  notification at the next start time as a reliable fallback. Lives in the app
//  target (not BlinkBreakCore) because BGTaskScheduler and UNUserNotificationCenter
//  are UIKit/UserNotifications APIs.
//
//  Flutter analogue: a platform channel handler that registers WorkManager tasks
//  and schedules AlarmManager alarms.
//

import BackgroundTasks
import UserNotifications
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
    static func registerBackgroundTaskHandler(controllerProvider: @escaping @MainActor () -> SessionController?) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BlinkBreakConstants.scheduleTaskId,
            using: nil
        ) { task in
            guard let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundTask(bgTask, controllerProvider: controllerProvider)
        }
    }

    private static func handleBackgroundTask(
        _ task: BGAppRefreshTask,
        controllerProvider: @escaping @MainActor () -> SessionController?
    ) {
        let workTask = Task { @MainActor in
            if let controller = controllerProvider() {
                await controller.reconcile()
            }
            guard !Task.isCancelled else { return }

            // Re-schedule the next background task for the next transition date.
            let evaluator = ScheduleEvaluator(schedule: {
                UserDefaultsPersistence().loadSchedule() ?? .empty
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
        scheduleNextBackgroundTask()
        scheduleStartTimeNotification()
    }

    private func scheduleNextBackgroundTask() {
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

    private func scheduleStartTimeNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["schedule.start"])

        let now = Date()
        let calendar = Calendar.current
        guard let schedule = persistence.loadSchedule(), schedule.isEnabled else { return }
        guard let nextStart = evaluator.nextTransitionDate(from: now, calendar: calendar) else { return }

        // Only schedule if next transition is a start (not an end).
        let isInsideWindow = evaluator.shouldBeActive(at: now, manualStopDate: nil, calendar: calendar)
        guard !isInsideWindow else { return }

        let content = UNMutableNotificationContent()
        content.title = "BlinkBreak"
        content.body = "Time for your scheduled eye break session."
        content.categoryIdentifier = BlinkBreakConstants.scheduleCategoryId
        content.interruptionLevel = .timeSensitive

        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: nextStart
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "schedule.start", content: content, trigger: trigger)
        center.add(request) { _ in }
    }

    func cancelAll() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BlinkBreakConstants.scheduleTaskId)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["schedule.start"])
    }
}
