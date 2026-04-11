//
//  WatchIdleView.swift
//  BlinkBreak Watch App
//
//  Idle state on the Watch. A single Start button. No explainer text — screen
//  real estate is too precious, and the user already knows what the app does.
//

import SwiftUI
import BlinkBreakCore

struct WatchIdleView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    var body: some View {
        VStack(spacing: 12) {
            Text("BlinkBreak")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Button("Start") {
                controller.start()
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        }
        .padding(.vertical, 10)
    }
}
