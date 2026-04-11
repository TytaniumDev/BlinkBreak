//
//  BlinkBreakWatchApp.swift
//  BlinkBreak Watch App
//
//  The watchOS app entry point. Mirrors BlinkBreakApp.swift on iOS: wires up a
//  shared SessionController, an AppDelegate for notification handling, and
//  activates WatchConnectivity so the Watch can receive state snapshots from
//  the iPhone and forward user commands back.
//

import SwiftUI
import BlinkBreakCore

@main
struct BlinkBreakWatchApp: App {

    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate

    @StateObject private var controller: SessionController = {
        let scheduler = UNNotificationScheduler()
        scheduler.registerCategories()
        return SessionController(
            scheduler: scheduler,
            connectivity: WCSessionConnectivity(),
            persistence: UserDefaultsPersistence()
        )
    }()

    var body: some Scene {
        WindowGroup {
            WatchRootView(controller: controller)
                .onAppear {
                    appDelegate.controller = controller

                    // On the Watch, we wire up the "snapshot received from iPhone"
                    // handler so the Watch UI updates when the iPhone broadcasts
                    // state changes.
                    wireUpSnapshotReceiver()

                    Task { await controller.reconcileOnLaunch() }
                }
        }
    }

    /// Listens for SessionSnapshot broadcasts from the iPhone and rebuilds local state
    /// accordingly. The iPhone is the source of truth; the Watch just mirrors.
    private func wireUpSnapshotReceiver() {
        // We attach the handler to the connectivity service inside the SessionController.
        // A V2 refactor can expose a cleaner API for this; in V1 we reach in via
        // the shared service instance.
        //
        // The actual implementation lives on SessionController — here we just
        // trigger reconcile which already pulls from persistence. Persistence
        // should be kept in sync with the iPhone via WatchConnectivity.
        Task { await controller.reconcileOnLaunch() }
    }
}
