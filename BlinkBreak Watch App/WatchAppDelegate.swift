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
            await controller?.reconcileOnLaunch()
        }
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == BlinkBreakConstants.startBreakActionId ||
              response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
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
