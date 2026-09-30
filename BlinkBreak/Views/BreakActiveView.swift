//
//  BreakActiveView.swift
//  BlinkBreak
//
//  The breakActive-state view. Calm dark theme. No countdown UI — the entire point
//  of the 20-second rest is to stop looking at screens. It's here only for the
//  rare case the user opens the app mid-break; the look-away alarm rings when
//  the 20 seconds are up.
//
//  The only interactive element is Stop, in case the user is ending their
//  session entirely.
//

import BlinkBreakCore
import SwiftUI

struct BreakActiveView<Controller: SessionControllerProtocol>: View {

    let controller: Controller

    var body: some View {
        AdaptiveScreen {
            VStack(spacing: 16) {
                EyebrowLabel(text: "Looking away")

                Spacer(minLength: 24)

                Text("Don't look at this screen.\nAn alarm will let you know when your 20 seconds are up.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityIdentifier("label.breakActive.message")

                Spacer(minLength: 24)
            }
        } actions: {
            StopButton(identifier: "button.breakActive.stop") {
                await controller.stop()
            }
        }
    }
}

#Preview {
    ZStack {
        CalmBackground()
        BreakActiveView(controller: PreviewSessionController.breakActive)
            .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}
