//
//  PreviewSessionController.swift
//  BlinkBreak
//
//  A lightweight, observable mock of SessionControllerProtocol used exclusively
//  for SwiftUI previews. Lets you render any view in any state inside Xcode
//  Previews without actually running alarms or persistence.
//
//  Flutter analogue: a stub ChangeNotifier you'd pass to a widget test or
//  Flutter DevTools preview to render without touching real services.
//

import BlinkBreakCore
import Combine
import Foundation

/// A SwiftUI-preview-friendly stand-in for `SessionController`. Conforms to
/// `SessionControllerProtocol` so any view that depends on the protocol can render
/// against this mock.
@MainActor
final class PreviewSessionController: ObservableObject, SessionControllerProtocol {

    @Published var state: SessionState
    @Published var weeklySchedule: WeeklySchedule = .empty
    @Published var muteAlarmSound: Bool = false

    init(state: SessionState = .idle) {
        self.state = state
    }

    // MARK: - SessionControllerProtocol

    func start() async {
        state = .running(cycleStartedAt: Date())
    }

    func stop() async {
        state = .idle
    }

    func acknowledgeCurrentBreak() async {
        state = .breakActive(startedAt: Date())
    }

    func reconcile() async {
        // No-op in previews.
    }

    func updateSchedule(_ schedule: WeeklySchedule) {
        weeklySchedule = schedule
    }

    func updateAlarmSound(muted: Bool) async {
        muteAlarmSound = muted
    }

    func triggerBreakNow() async {
        // No-op in previews.
    }

    // MARK: - Preview fixtures

    /// Preview states for each scenario a view might render.
    static let idle = PreviewSessionController(state: .idle)

    static var running: PreviewSessionController {
        PreviewSessionController(
            state: .running(cycleStartedAt: Date().addingTimeInterval(-14 * 60))  // ~14 min into a cycle
        )
    }

    static var breakPending: PreviewSessionController {
        PreviewSessionController(
            state: .breakPending(cycleStartedAt: Date().addingTimeInterval(-20 * 60))
        )
    }

    static var breakActive: PreviewSessionController {
        PreviewSessionController(
            state: .breakActive(startedAt: Date().addingTimeInterval(-5))
        )
    }
}
