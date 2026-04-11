//
//  BlinkBreakApp.swift
//  BlinkBreak
//
//  The iOS app's entry point. In SwiftUI, your app is described by a struct that
//  conforms to the `App` protocol and is marked with `@main`. The `body` of that
//  struct describes the scene tree — in our case, a single `WindowGroup` containing
//  a `RootView`.
//
//  Flutter analogue: this is `void main() { runApp(MyApp()); }` + the root `MaterialApp`.
//

import SwiftUI
import BlinkBreakCore

@main
struct BlinkBreakApp: App {

    // @UIApplicationDelegateAdaptor is how SwiftUI apps hook a classic UIKit-style
    // AppDelegate into the modern SwiftUI lifecycle. We use it to register the
    // UNUserNotificationCenterDelegate so the app can respond to notification taps.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // XCUITest hook: when launched with `-BB_RESET_DEFAULTS`, wipe the persisted
        // session record so each integration test starts from a clean idle state.
        // Production launches never pass this flag.
        if CommandLine.arguments.contains("-BB_RESET_DEFAULTS") {
            UserDefaults.standard.removeObject(forKey: BlinkBreakConstants.sessionRecordKey)
        }
    }

    // @StateObject owns an observable object for the entire lifetime of the app.
    // Flutter analogue: a top-level ChangeNotifierProvider that lives for as long
    // as the app runs. Views deeper in the tree observe this via @ObservedObject /
    // @EnvironmentObject.
    @StateObject private var controller: SessionController = {
        let scheduler = UNNotificationScheduler()
        scheduler.registerCategories()
        return SessionController(
            scheduler: scheduler,
            connectivity: WCSessionConnectivity(),
            persistence: UserDefaultsPersistence(),
            alarm: NoopSessionAlarm()
        )
    }()

    var body: some Scene {
        WindowGroup {
            RootView(controller: controller)
                .onAppear {
                    // Hand the controller to the AppDelegate so notification action
                    // taps can be routed to SessionController.handleStartBreakAction.
                    appDelegate.controller = controller
                    appDelegate.requestNotificationAuthorizationIfNeeded()

                    // Activate WatchConnectivity and wire up both directions:
                    // - onCommandReceived: the (rarely-used) Watch→Phone command path.
                    // - onSnapshotReceived: when the Watch broadcasts a break
                    //   acknowledgment, handleRemoteSnapshot cancels our delivered
                    //   iPhone notification and disarms our (noop) alarm.
                    controller.activateConnectivity()
                    controller.wireUpConnectivity()
                    Task { await controller.reconcileOnLaunch() }
                }
        }
    }
}
