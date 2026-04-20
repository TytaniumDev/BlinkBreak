//
//  AppDelegate.swift
//  BlinkBreak
//
//  Tiny lifecycle hook. Registers the BGTaskScheduler handler before the
//  app finishes launching (required by iOS) and holds a weak reference to
//  the SessionController so the background task can drive reconciliation.
//
//  Flutter analogue: the native iOS side of a platform plugin — it receives events
//  from iOS and forwards them into your Dart code via a method channel.
//

import UIKit
import BackgroundTasks
import BlinkBreakCore

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// The app's SessionController. Set by BlinkBreakApp on first appearance.
    weak var controller: SessionController?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // BGTaskScheduler registration must happen before the app finishes launching.
        // The controller doesn't exist yet, so we pass a closure that reads it lazily.
        ScheduleTaskManager.registerBackgroundTaskHandler { [weak self] in
            self?.controller
        }

        return true
    }
}
