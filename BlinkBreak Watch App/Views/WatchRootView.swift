//
//  WatchRootView.swift
//  BlinkBreak Watch App
//
//  Watch-side root view. Same pattern as iOS RootView but with Watch-appropriate
//  sizing and simpler layouts. Switches on SessionState to render one of four
//  child views.
//

import SwiftUI
import BlinkBreakCore

struct WatchRootView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Red background only during breakPending; everything else is dark.
            switch controller.state {
            case .breakPending:
                Color(red: 0.69, green: 0, blue: 0.13).ignoresSafeArea()
            default:
                Color.black.ignoresSafeArea()
            }

            Group {
                switch controller.state {
                case .idle:
                    WatchIdleView(controller: controller)
                case .running(let cycleStartedAt):
                    WatchRunningView(controller: controller, cycleStartedAt: cycleStartedAt)
                case .breakPending:
                    WatchBreakPendingView(controller: controller)
                case .breakActive:
                    WatchBreakActiveView()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: controller.state)
        }
        .foregroundStyle(.white)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await controller.reconcileOnLaunch() }
            }
        }
    }
}
