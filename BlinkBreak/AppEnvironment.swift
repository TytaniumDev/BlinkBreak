//
//  AppEnvironment.swift
//  BlinkBreak
//
//  The composition root: builds the one SessionController the whole process
//  shares. The UI and the alarm App Intents both go through it, so a button
//  tapped on an alarm and a button tapped in the app are serialized on the
//  same queue.
//
//  Everything is created lazily on first use. That matters when iOS launches
//  the app in the background just to run an intent — no scene or view exists
//  then, but the controller still does.
//
//  Flutter analogue: the top-level `Provider`s / service locator set up in `main()`.
//

import BlinkBreakCore
import Foundation

@MainActor
enum AppEnvironment {

    static let controller: SessionController = {
        let persistence = UserDefaultsPersistence()
        if UITestSupport.resetRequested {
            persistence.removeAll()
        } else {
            persistence.removeLegacyData()
        }
        return SessionController(alarmScheduler: AlarmKitScheduler(), persistence: persistence)
    }()

    static let feedbackReporter: any FeedbackReporting = SentryFeedbackReporter {
        [
            "session_state": controller.state.description,
            "schedule_enabled": String(controller.weeklySchedule.isEnabled)
        ]
    }

    /// Entry point for the alarm App Intents.
    static func respond(_ response: AlarmResponse, alarmID: String) async {
        guard let id = UUID(uuidString: alarmID) else {
            AppLogger.shared.log(.error, "intent \(response.rawValue): invalid alarm ID")
            return
        }
        await controller.respond(to: response, alarmId: id)
    }
}
