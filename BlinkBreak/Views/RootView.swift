//
//  RootView.swift
//  BlinkBreak
//
//  The single top-level view that switches between the four state-specific views.
//  Observes the SessionController via the protocol and dispatches to the right
//  child view for the current state.
//
//  This is the only view that "knows" the state machine — every other view is
//  unaware of the global state and just does its one job.
//
//  Flutter analogue: think of this as a Consumer<SessionController> with a
//  switch expression that returns the appropriate child widget.
//

import SwiftUI
import BlinkBreakCore

struct RootView<Controller: SessionControllerProtocol>: View {

    /// The session controller driving the app. Injected from BlinkBreakApp so that
    /// previews can substitute a PreviewSessionController.
    @ObservedObject var controller: Controller

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Swap the background based on state so the red alert is unmistakable.
            switch controller.state {
            case .breakPending:
                AlertBackground()
            default:
                CalmBackground()
            }

            // Swap the foreground content based on state.
            Group {
                switch controller.state {
                case .idle:
                    IdleView(controller: controller)
                case .running(let cycleStartedAt):
                    RunningView(controller: controller, cycleStartedAt: cycleStartedAt)
                case .breakPending:
                    BreakPendingView(controller: controller)
                case .breakActive:
                    BreakActiveView(controller: controller)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: controller.state)
        }
        .foregroundStyle(.white)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await controller.reconcile() }
            }
        }
    }
}

#Preview("Idle") {
    RootView(controller: PreviewSessionController.idle)
}

#Preview("Running") {
    RootView(controller: PreviewSessionController.running)
}

#Preview("Break Pending") {
    RootView(controller: PreviewSessionController.breakPending)
}

#Preview("Break Active") {
    RootView(controller: PreviewSessionController.breakActive)
}
