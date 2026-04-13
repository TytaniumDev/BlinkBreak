//
//  WatchAppDelegate.swift
//  BlinkBreak Watch App
//
//  Tiny watchOS AppDelegate that handles notification actions and forwards them
//  to the SessionController. Mirrors the iOS AppDelegate's role.
//

import WatchKit
import UserNotifications
import BlinkBreakCore

final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {

    weak var controller: SessionController?

    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .timeSensitive]
        ) { granted, _ in
            print("[BlinkBreak Watch] notification auth granted: \(granted)")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Only handle the explicit "Start break" action button — NOT the default
        // action (tapping the notification body). Tapping the body opens the app,
        // where reconcile() sets state to breakPending and the user can press
        // "Start break" explicitly. Without this guard, tapping a notification that
        // only shows "Dismiss" would silently auto-start the break.
        guard response.actionIdentifier == BlinkBreakConstants.startBreakActionId else {
            completionHandler()
            return
        }

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
