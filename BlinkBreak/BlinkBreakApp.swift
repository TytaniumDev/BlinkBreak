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
    // BGTaskScheduler handler before the app finishes launching.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // XCUITest hook: when launched with `-BB_RESET_DEFAULTS`, wipe the persisted
        // session record so each integration test starts from a clean idle state.
        // Production launches never pass this flag.
        if CommandLine.arguments.contains("-BB_RESET_DEFAULTS") {
            UserDefaults.standard.removeObject(forKey: BlinkBreakConstants.sessionRecordKey)
            UserDefaults.standard.removeObject(forKey: BlinkBreakConstants.alarmSoundMutedKey)
        }

        // Release-only crash / error reporting. No-op in DEBUG.
        SentryBootstrap.start()
    }

    // Shared instances used by both the SessionController and the ScheduleTaskManager
    // so we don't create duplicate persistence / evaluator objects.
    private static let sharedPersistence = UserDefaultsPersistence()
    private static let sharedEvaluator = ScheduleEvaluator(schedule: {
        sharedPersistence.loadSchedule() ?? .empty
    })

    @MainActor
    private static let sharedAlarmScheduler = AlarmKitScheduler()

    // @StateObject owns an observable object for the entire lifetime of the app.
    // Flutter analogue: a top-level ChangeNotifierProvider that lives for as long
    // as the app runs. Views deeper in the tree observe this via @ObservedObject /
    // @EnvironmentObject.
    @StateObject private var controller: SessionController = {
        SessionController(
            alarmScheduler: sharedAlarmScheduler,
            persistence: sharedPersistence,
            scheduleEvaluator: sharedEvaluator
        )
    }()

    @State private var scheduleTaskManager: ScheduleTaskManager?

    var body: some Scene {
        WindowGroup {
            ShakeDetectorView(
                content: RootView(controller: controller, scheduleEvaluator: Self.sharedEvaluator),
                persistence: Self.sharedPersistence,
                sessionState: controller.state
            )
                .onAppear {
                    appDelegate.controller = controller

                    // Request AlarmKit authorization on first launch. Subsequent launches
                    // are a no-op because iOS remembers the user's decision.
                    Task {
                        _ = try? await Self.sharedAlarmScheduler.requestAuthorizationIfNeeded()
                    }

                    Task { await controller.reconcile() }

                    // Set up the ScheduleTaskManager for foreground schedule checks.
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
