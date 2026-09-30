//
//  PreviewSessionController.swift
//  BlinkBreak
//
//  A lightweight, observable mock of SessionControllerProtocol used exclusively
//  for SwiftUI previews. Lets you render any view in any state inside Xcode
//  Previews without actually running alarms or persistence.
//
//  Flutter analogue: a stub ChangeNotifier you'd pass to a widget to render it
//  without touching real services.
//

import BlinkBreakCore
import Foundation
import Observation

@MainActor
@Observable
final class PreviewSessionController: SessionControllerProtocol {

    var state: SessionState
    var weeklySchedule: WeeklySchedule
    var muteAlarmSound = false
    var authorizationDenied: Bool

    init(
        state: SessionState = .idle,
        weeklySchedule: WeeklySchedule = .default,
        authorizationDenied: Bool = false
    ) {
        self.state = state
        self.weeklySchedule = weeklySchedule
        self.authorizationDenied = authorizationDenied
    }

    // MARK: - SessionControllerProtocol

    func scheduleStatus(at date: Date) -> String? {
        weeklySchedule.statusText(at: date, calendar: .current)
    }

    func start() async {
        state = .running(breakAt: Date().addingTimeInterval(BlinkBreakConstants.breakInterval))
    }

    func stop() async {
        state = .idle
    }

    func startBreak() async {
        state = .breakActive(endsAt: Date().addingTimeInterval(BlinkBreakConstants.lookAwayDuration))
    }

    func takeBreakNow() async {
        state = .breakPending
    }

    func reconcile() async {}

    func updateSchedule(_ schedule: WeeklySchedule) {
        weeklySchedule = schedule
    }

    func updateAlarmSound(muted: Bool) {
        muteAlarmSound = muted
    }

    // MARK: - Preview fixtures

    static var idle: PreviewSessionController { PreviewSessionController() }

    static var idleWithSchedule: PreviewSessionController {
        var schedule = WeeklySchedule.default
        schedule.isEnabled = true
        return PreviewSessionController(weeklySchedule: schedule)
    }

    /// About six minutes left in the cycle.
    static var running: PreviewSessionController {
        PreviewSessionController(state: .running(breakAt: Date().addingTimeInterval(6 * 60)))
    }

    static var breakPending: PreviewSessionController {
        PreviewSessionController(state: .breakPending)
    }

    static var breakActive: PreviewSessionController {
        PreviewSessionController(state: .breakActive(endsAt: Date().addingTimeInterval(15)))
    }

    static var permissionDenied: PreviewSessionController {
        PreviewSessionController(authorizationDenied: true)
    }
}
