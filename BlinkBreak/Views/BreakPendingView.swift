//
//  BreakPendingView.swift
//  BlinkBreak
//
//  The breakPending-state view: full-bleed red alert with a large "Start break"
//  button. Shown when the app is open while the break alarm rings; otherwise the
//  system alarm UI does this job.
//
//  Contains zero business logic: "Start break" calls `controller.startBreak()`.
//

import BlinkBreakCore
import SwiftUI

struct BreakPendingView<Controller: SessionControllerProtocol>: View {

    let controller: Controller

    var body: some View {
        AdaptiveScreen {
            VStack(spacing: 16) {
                Spacer(minLength: 0)

                EyebrowLabel(text: "Break time")

                Text("Look at something\n20 feet away")
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Focus on a distant object for 20 seconds to rest your eyes.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
        } actions: {
            VStack(spacing: 12) {
                Button {
                    Task { await controller.startBreak() }
                } label: {
                    Text("Start break")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color.alertRed)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.white)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("button.breakPending.startBreak")

                StopButton(identifier: "button.breakPending.stop") {
                    await controller.stop()
                }
            }
        }
    }
}

#Preview {
    ZStack {
        AlertBackground()
        BreakPendingView(controller: PreviewSessionController.breakPending)
            .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}
