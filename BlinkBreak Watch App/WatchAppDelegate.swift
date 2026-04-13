//
//  WatchAppDelegate.swift
//  BlinkBreak Watch App
//
//  Owns the Watch app's SessionController and handles notification delivery.
//
//  Why the delegate owns the controller (instead of the SwiftUI @StateObject):
//  `applicationDidFinishLaunching` is called on every app launch, including
//  background wakes triggered by watchOS delivering a pending
//  `updateApplicationContext` from the iPhone. `.onAppear` in the SwiftUI view
//  only fires when the view actually renders, which doesn't happen during
//  background wakes. Activating WatchConnectivity here guarantees the
//  controller is ready to receive iPhone snapshots (and therefore schedule
//  the Watch-local break notification) even when the user hasn't opened the
//  Watch app.
//

import WatchKit
import UserNotifications
import BlinkBreakCore

@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {

    /// The single SessionController for this Watch app process. Owned by the delegate
    /// so its lifetime matches the app process, and so it exists before any SwiftUI
    /// view has a chance to appear.
    let controller: SessionController

    override init() {
        let scheduler = UNNotificationScheduler()
        scheduler.registerCategories()
        self.controller = SessionController(
            scheduler: scheduler,
            connectivity: WCSessionConnectivity(),
            persistence: UserDefaultsPersistence(),
            alarm: WKExtendedRuntimeSessionAlarm()
        )
        super.init()
    }

    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .timeSensitive]
        ) { granted, _ in
            print("[BlinkBreak Watch] notification auth granted: \(granted)")
        }

        // Activate WatchConnectivity EARLY — here, not in .onAppear — so background
        // launches (watchOS waking the app to deliver a pending iPhone snapshot)
        // can route that snapshot into the controller. Without this, the Watch
        // only picks up iPhone-started sessions when the user opens the app.
        controller.activateConnectivity()
        controller.wireUpConnectivity()
        Task { await controller.reconcile() }
    }

    // MARK: - UNUserNotificationCenterDelegate
    //
    // Apple documents `UNUserNotificationCenterDelegate` methods as being delivered
    // on the main queue, so these methods inherit this class's `@MainActor` isolation
    // and can touch the controller directly (no `nonisolated` + Task hop needed).

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Trigger a reconcile so the controller picks up the state transition
        // (e.g. running → breakPending) when a notification fires while foregrounded.
        Task { await controller.reconcile() }
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

        controller.handleStartBreakAction(cycleId: cycleId)
        completionHandler()
    }
}
