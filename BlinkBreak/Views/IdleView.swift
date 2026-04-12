//
//  IdleView.swift
//  BlinkBreak
//
//  The idle-state view. Shows the app name, a short explainer, and a Start button.
//  No icon per design feedback — explainer text carries the meaning instead.
//

import SwiftUI
import BlinkBreakCore

struct IdleView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "BlinkBreak")

            Text("20-20-20 Rule")
                .font(.title2.weight(.semibold))

            Text("Every 20 minutes, look at something 20 feet away for 20 seconds. Your eyes will thank you.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)

            Spacer()

            PrimaryButton(title: "Start") {
                controller.start()
            }
            .accessibilityIdentifier("button.idle.start")
        }
        .padding(24)
    }
}

#Preview {
    ZStack {
        CalmBackground()
        IdleView(controller: PreviewSessionController.idle)
            .foregroundStyle(.white)
    }
}
