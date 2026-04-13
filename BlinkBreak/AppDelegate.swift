//
//  AppDelegate.swift
//  BlinkBreak
//
//  Hooks notification events into the SessionController. Intentionally tiny —
//  business logic lives in BlinkBreakCore.SessionController; this file only
//  translates platform events into controller method calls.
//
//  Flutter analogue: the native iOS side of a platform plugin — it receives events
//  from iOS and forwards them into your Dart code via a method channel.
//

import UIKit
import UserNotifications
import BackgroundTasks
import BlinkBreakCore

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// The app's SessionController. Set by BlinkBreakApp on first appearance.
    weak var controller: SessionController?

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // BGTaskScheduler registration must happen before the app finishes launching.
        // The controller doesn't exist yet, so we pass a closure that reads it lazily.
        ScheduleTaskManager.registerBackgroundTaskHandler { [weak self] in
            self?.controller
        }

        return true
    }

    // MARK: - Authorization

    /// Requests alert + sound + time-sensitive permission on first launch. Subsequent
    /// launches are a no-op because iOS remembers the user's decision.
    func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .timeSensitive]
        ) { granted, error in
            if let error = error {
                print("[BlinkBreak] notification auth error: \(error)")
            }
            print("[BlinkBreak] notification auth granted: \(granted)")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification is delivered while the app is in the foreground.
    /// By default iOS doesn't show a banner if the app is foregrounded — we explicitly
    /// opt in so break alerts are visible even when the user is actively using the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Trigger a reconcile so the controller picks up the state transition
        // (e.g. running → breakPending) when a notification fires while foregrounded.
        Task { @MainActor in
            await controller?.reconcile()
        }
        completionHandler([.banner, .sound, .list])
    }

    /// Called when the user taps a notification or one of its action buttons.
    /// This is where we handle the "Start break" action — we forward it to
    /// SessionController.handleStartBreakAction with the cycleId extracted from the
    /// notification identifier.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle schedule start notification tap — reconcile state so the controller
        // can auto-start if the schedule window is active.
        if response.notification.request.content.categoryIdentifier == BlinkBreakConstants.scheduleCategoryId {
            Task { @MainActor in
                await controller?.reconcile()
            }
            completionHandler()
            return
        }

        guard response.actionIdentifier == BlinkBreakConstants.startBreakActionId ||
              response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }

        // Extract the cycleId from the notification identifier. The identifier format
        // is either "break.primary.<uuid>" or "break.nudge.<uuid>.<n>" — in both cases
        // the third component is the UUID string.
        let components = response.notification.request.identifier.split(separator: ".")
        guard components.count >= 3,
              let cycleId = UUID(uuidString: String(components[2])) else {
            completionHandler()
            return
        }

        Task { @MainActor in
            self.controller?.handleStartBreakAction(cycleId: cycleId)
            completionHandler()
        }
    }
}
