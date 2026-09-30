//
//  PausedView.swift
//  BlinkBreak
//
//  The paused-state view. Shown after the user taps Pause during a scheduled
//  session (e.g. to take a nap). No alarms fire until they tap Resume. When the
//  schedule window ends, the pause lapses back to idle and the schedule starts
//  the next window as usual.
//
//  No business logic here. Controller methods called: `start()` (Resume) and
//  `stop()`.
//

import BlinkBreakCore
import SwiftUI

struct PausedView<Controller: SessionControllerProtocol>: View {

    let controller: Controller

    /// End of the schedule window this pause belongs to.
    let until: Date

    var body: some View {
        AdaptiveScreen {
            VStack(spacing: 16) {
                EyebrowLabel(text: "Paused")

                Spacer(minLength: 24)

                Image(systemName: "pause.circle")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityHidden(true)

                Text("Breaks are paused until you resume.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))

                Text("Today's schedule ends at \(until.formatted(date: .omitted, time: .shortened)). "
                     + "BlinkBreak will start again automatically at your next scheduled time.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityIdentifier("label.paused.until")

                Spacer(minLength: 24)
            }
        } actions: {
            VStack(spacing: 12) {
                Button {
                    Task { await controller.start() }
                } label: {
                    Text("Resume")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("button.paused.resume")

                StopButton(identifier: "button.paused.stop") {
                    await controller.stop()
                }
            }
        }
    }
}

#Preview {
    ZStack {
        CalmBackground()
        PausedView(
            controller: PreviewSessionController.paused,
            until: Date().addingTimeInterval(3 * 60 * 60)
        )
        .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}
