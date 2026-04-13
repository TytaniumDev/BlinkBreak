//
//  BlinkBreakWatchApp.swift
//  BlinkBreak Watch App
//
//  The watchOS app entry point. Wires up a shared SessionController with the
//  WKExtendedRuntimeSession-backed alarm, an AppDelegate for notification handling,
//  and activates WatchConnectivity so the Watch can receive state snapshots from the
//  iPhone and forward user commands back.
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
            persistence: UserDefaultsPersistence(),
            alarm: WKExtendedRuntimeSessionAlarm()
        )
    }()

    var body: some Scene {
        WindowGroup {
            WatchRootView(controller: controller)
                .onAppear {
                    appDelegate.controller = controller

                    // Activate WatchConnectivity and wire up both directions:
                    // - onCommandReceived: the (rarely-used) Watch→Phone path.
                    // - onSnapshotReceived: iPhone broadcasts state snapshots the
                    //   Watch applies via handleRemoteSnapshot.
                    controller.activateConnectivity()
                    controller.wireUpConnectivity()
                    Task { await controller.reconcile() }
                }
        }
    }
}
