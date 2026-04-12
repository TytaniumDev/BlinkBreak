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
    private let evaluator: ScheduleEvaluating
    private let controllerProvider: @MainActor () -> SessionController?

    init(
        persistence: PersistenceProtocol,
        evaluator: ScheduleEvaluating,
        controllerProvider: @escaping @MainActor () -> SessionController?
    ) {
        self.persistence = persistence
        self.evaluator = evaluator
        self.controllerProvider = controllerProvider
    }

    // MARK: - BGTask Registration

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BlinkBreakConstants.scheduleTaskId,
            using: nil
        ) { [weak self] task in
            guard let self, let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundTask(bgTask)
        }
    }

    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task { @MainActor in
            if let controller = controllerProvider() {
                await controller.reconcileOnLaunch()
            }
            scheduleNextBackgroundTask()
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Scheduling

    func reschedule() {
        scheduleNextBackgroundTask()
        scheduleStartTimeNotification()
    }

    private func scheduleNextBackgroundTask() {
        let nextDate = evaluator.nextTransitionDate(from: Date(), calendar: .current)
        let request = BGAppRefreshTaskRequest(identifier: BlinkBreakConstants.scheduleTaskId)
        request.earliestBeginDate = nextDate
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskScheduler.submit can fail in simulator or if called too frequently.
            // Not actionable — foreground reconciliation is the reliable path.
        }
    }

    private func scheduleStartTimeNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["schedule.start"])

        guard let schedule = persistence.loadSchedule(), schedule.isEnabled else { return }
        guard let nextStart = evaluator.nextTransitionDate(from: Date(), calendar: .current) else { return }

        // Only schedule if next transition is a start (not an end).
        let isInsideWindow = evaluator.shouldBeActive(at: Date(), manualStopDate: nil, calendar: .current)
        guard !isInsideWindow else { return }

        let content = UNMutableNotificationContent()
        content.title = "BlinkBreak"
        content.body = "Time for your scheduled eye break session."
        content.categoryIdentifier = BlinkBreakConstants.scheduleCategoryId
        content.interruptionLevel = .timeSensitive

        let comps = Calendar.current.dateComponents(
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
