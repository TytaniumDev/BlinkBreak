//
//  BreakPendingView.swift
//  BlinkBreak
//
//  The breakPending-state view. Full-bleed red alert with a large "Start break"
//  button. Only shown when the app is foregrounded during the cascade — backgrounded
//  users see the notifications instead.
//
//  Contains zero business logic: the "Start break" button calls
//  `controller.acknowledgeCurrentBreak()` and the controller looks up its own
//  cycleId from persistence. The view doesn't know or care about cycleIds.
//

import SwiftUI
import BlinkBreakCore

struct BreakPendingView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            EyebrowLabel(text: "Break time")

            Text("Look at something\n20 feet away")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("Focus on a distant object for 20 seconds to rest your eyes.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    controller.acknowledgeCurrentBreak()
                } label: {
                    Text("Start break")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.white)
                .foregroundStyle(Color(red: 0.69, green: 0.00, blue: 0.13))
                .accessibilityIdentifier("button.breakPending.startBreak")

                Button(role: .destructive) {
                    controller.stop()
                } label: {
                    Text("Stop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)
                .accessibilityIdentifier("button.breakPending.stop")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

#Preview {
    ZStack {
        AlertBackground()
        BreakPendingView(controller: PreviewSessionController.breakPending)
    }
}
