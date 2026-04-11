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

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Red background only during breakActive; everything else is dark.
            switch controller.state {
            case .breakActive:
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
                case .breakActive:
                    WatchBreakActiveView(controller: controller)
                case .lookAway:
                    WatchLookAwayView()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: controller.state)
        }
        .foregroundStyle(.white)
        .onReceive(tick) { _ in
            Task { await controller.reconcileOnLaunch() }
        }
    }
}
