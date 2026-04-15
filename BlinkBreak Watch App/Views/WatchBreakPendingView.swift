//
//  WatchBreakPendingView.swift
//  BlinkBreak Watch App
//
//  Break-pending state on the Watch. Full-bleed red with a large Start break button
//  plus a secondary Stop action for ending the session without acknowledging the break.
//  This is what the user sees when they raise their wrist after feeling the haptic cascade.
//

import SwiftUI
import BlinkBreakCore

struct WatchBreakPendingView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    var body: some View {
        VStack(spacing: 8) {
            Text("LOOK AWAY")
                .font(.caption2)
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.9))

            Text("20 ft")
                .font(.title.weight(.semibold))

            Spacer()

            Button("Start break") {
                controller.acknowledgeCurrentBreak()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(Color(red: 0.69, green: 0, blue: 0.13))
            .accessibilityIdentifier("button.breakPending.startBreak")

            Button("Stop", role: .destructive) {
                controller.stop()
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .accessibilityIdentifier("button.breakPending.stop")
        }
        .padding(.vertical, 10)
    }
}
