//
//  BlinkBreakAlarmDismissIntent.swift
//  BlinkBreak
//
//  Shared protocol for the two AlarmKit secondary-button intents (StartBreakIntent
//  and EndBreakIntent). Both do the same thing — cancel the alerting alarm by ID —
//  but AppIntents requires distinct types so the user-facing title/description are
//  registered correctly in Spotlight and Shortcuts.
//

import AlarmKit
import AppIntents
import Foundation

@available(iOS 26.1, *)
protocol BlinkBreakAlarmDismissIntent: LiveActivityIntent {
    var alarmID: String { get }
}

@available(iOS 26.1, *)
extension BlinkBreakAlarmDismissIntent {
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.cancel(id: id)
        }
        return .result()
    }
}
