//
//  LookAwayView.swift
//  BlinkBreak
//
//  The lookAway-state view. Calm dark theme. No countdown UI — the entire point
//  of the 20-second rest is to stop looking at screens. The user doesn't need
//  to see this view; it's here only for the rare case they foreground the app
//  mid-break. A haptic on the Watch will tell them when the 20 seconds are up.
//
//  The only interactive element is the Stop button, in case the user is ending
//  their session entirely.
//

import SwiftUI
import BlinkBreakCore

struct LookAwayView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    var body: some View {
        VStack(spacing: 16) {
            EyebrowLabel(text: "Looking away")

            Spacer()

            Text("Don't look at this screen.\nWe'll haptic you when your 20 seconds are up.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 32)
                .accessibilityIdentifier("label.lookAway.message")

            Spacer()

            DestructiveButton(title: "Stop") {
                controller.stop()
            }
            .accessibilityIdentifier("button.lookAway.stop")
        }
        .padding(24)
    }
}

#Preview {
    ZStack {
        CalmBackground()
        LookAwayView(controller: PreviewSessionController.lookAway)
    }
}
