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

    /// A periodic tick used to drive countdown UIs and detect automatic state
    /// transitions (running → breakActive, lookAway → running). Fires once per second.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Swap the background based on state so the red alert is unmistakable.
            switch controller.state {
            case .breakActive:
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
                case .breakActive:
                    BreakActiveView(controller: controller)
                case .lookAway:
                    LookAwayView(controller: controller)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: controller.state)
        }
        .foregroundStyle(.white)
        .onReceive(tick) { _ in
            // Every second, ask the controller to reconcile. This picks up the
            // running → breakActive transition when the clock crosses the threshold.
            Task { await controller.reconcileOnLaunch() }
        }
    }
}

#Preview("Idle") {
    RootView(controller: PreviewSessionController.idle)
}

#Preview("Running") {
    RootView(controller: PreviewSessionController.running)
}

#Preview("Break Active") {
    RootView(controller: PreviewSessionController.breakActive)
}

#Preview("Look Away") {
    RootView(controller: PreviewSessionController.lookAway)
}
