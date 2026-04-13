//
//  PreviewSessionController.swift
//  BlinkBreak
//
//  A lightweight, observable mock of SessionControllerProtocol used exclusively
//  for SwiftUI previews. Lets you render any view in any state inside Xcode
//  Previews without actually running notifications, persistence, or WatchConnectivity.
//
//  Flutter analogue: a stub ChangeNotifier you'd pass to a widget test or
//  Flutter DevTools preview to render without touching real services.
//

import Foundation
import Combine
import BlinkBreakCore

/// A SwiftUI-preview-friendly stand-in for `SessionController`. Conforms to
/// `SessionControllerProtocol` so any view that depends on the protocol can render
/// against this mock.
@MainActor
final class PreviewSessionController: ObservableObject, SessionControllerProtocol {

    @Published var state: SessionState
    @Published var weeklySchedule: WeeklySchedule = .empty

    init(state: SessionState = .idle) {
        self.state = state
    }

    // MARK: - SessionControllerProtocol

    func start() {
        state = .running(cycleStartedAt: Date())
    }

    func stop() {
        state = .idle
    }

    func handleStartBreakAction(cycleId: UUID) {
        state = .breakActive(startedAt: Date())
    }

    func acknowledgeCurrentBreak() {
        state = .breakActive(startedAt: Date())
    }

    func reconcileOnLaunch() async {
        // No-op in previews.
    }

    func updateSchedule(_ schedule: WeeklySchedule) {
        weeklySchedule = schedule
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
