//
//  RootView.swift
//  BlinkBreak
//
//  The single top-level view that switches between the state-specific views.
//  This is the only view that "knows" the state machine — every other view is
//  unaware of the global state and just does its one job.
//
//  It also re-syncs the controller whenever the app becomes active, which
//  covers first launch too (`initial: true`).
//
//  Flutter analogue: a Consumer<SessionController> with a switch expression
//  that returns the appropriate child widget.
//

import BlinkBreakCore
import SwiftUI

struct RootView<Controller: SessionControllerProtocol>: View {

    /// Injected from BlinkBreakApp so previews can substitute a PreviewSessionController.
    /// `@Observable` means SwiftUI re-renders when any property read here changes.
    let controller: Controller

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Swap the background based on state so the red alert is unmistakable.
            if controller.state == .breakPending {
                AlertBackground()
            } else {
                CalmBackground()
            }

            Group {
                if controller.authorizationDenied, controller.state == .idle {
                    PermissionDeniedView()
                } else {
                    switch controller.state {
                    case .idle:
                        IdleView(controller: controller)
                    case .running(let breakAt):
                        RunningView(controller: controller, breakAt: breakAt)
                    case .breakPending:
                        BreakPendingView(controller: controller)
                    case .breakActive:
                        BreakActiveView(controller: controller)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: controller.state)
        }
        .foregroundStyle(.white)
        // The app is always dark; this keeps system controls (toggles, pickers,
        // sheets) legible on the dark backgrounds.
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await controller.reconcile() }
            }
        }
    }
}

#Preview("Idle") {
    RootView(controller: PreviewSessionController.idleWithSchedule)
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

#Preview("Permission Denied") {
    RootView(controller: PreviewSessionController.permissionDenied)
}

#Preview("Landscape", traits: .landscapeLeft) {
    RootView(controller: PreviewSessionController.running)
}
