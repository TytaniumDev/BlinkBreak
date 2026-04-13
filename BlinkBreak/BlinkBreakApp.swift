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
import WatchConnectivity

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

    // Shared instances used by both the SessionController and the ScheduleTaskManager
    // so we don't create duplicate persistence / evaluator objects.
    private static let sharedPersistence = UserDefaultsPersistence()
    private static let sharedEvaluator = ScheduleEvaluator(schedule: {
        sharedPersistence.loadSchedule() ?? .empty
    })

    private static let sharedScheduler = UNNotificationScheduler()

    // @StateObject owns an observable object for the entire lifetime of the app.
    // Flutter analogue: a top-level ChangeNotifierProvider that lives for as long
    // as the app runs. Views deeper in the tree observe this via @ObservedObject /
    // @EnvironmentObject.
    @StateObject private var controller: SessionController = {
        sharedScheduler.registerCategories()
        return SessionController(
            scheduler: sharedScheduler,
            connectivity: WCSessionConnectivity(),
            persistence: sharedPersistence,
            alarm: NoopSessionAlarm(),
            scheduleEvaluator: sharedEvaluator
        )
    }()

    @State private var scheduleTaskManager: ScheduleTaskManager?

    var body: some Scene {
        WindowGroup {
            ShakeDetectorView(
                content: RootView(controller: controller, scheduleEvaluator: Self.sharedEvaluator),
                scheduler: Self.sharedScheduler,
                persistence: Self.sharedPersistence,
                sessionState: controller.state,
                watchIsPaired: WCSession.isSupported() ? WCSession.default.isPaired : false,
                watchIsReachable: WCSession.isSupported() ? WCSession.default.isReachable : false
            )
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
                    Task { await controller.reconcile() }

                    // Set up the ScheduleTaskManager for foreground schedule checks
                    // and local notification fallback at the next scheduled start time.
                    // BGTask registration happens in AppDelegate.didFinishLaunching.
                    let manager = ScheduleTaskManager(
                        persistence: Self.sharedPersistence,
                        evaluator: Self.sharedEvaluator,
                        controllerProvider: { [weak controller] in controller }
                    )
                    manager.reschedule()
                    scheduleTaskManager = manager
                }
                .onChange(of: controller.weeklySchedule) { _, _ in
                    scheduleTaskManager?.reschedule()
                }
        }
    }
}
