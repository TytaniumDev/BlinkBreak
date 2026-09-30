//
//  PausedView.swift
//  BlinkBreak
//
//  The paused-state view. Shown after the user taps Pause during a scheduled
//  session (e.g. to take a nap). No alarms fire until they tap Resume. When the
//  schedule window ends, the controller lapses the pause back to idle and the
//  schedule auto-starts the next window as usual.
//
//  No business logic here. Controller methods called: `start()` (Resume) and
//  `stop()`.
//

import SwiftUI
import BlinkBreakCore

struct PausedView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller

    /// End of the schedule window this pause belongs to.
    let until: Date

    var body: some View {
        VStack(spacing: 16) {
            EyebrowLabel(text: "Paused")

            Spacer()

            Image(systemName: "pause.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)

            Text("Breaks are paused until you resume.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))

            Text("Today's schedule ends at \(untilFormatted). BlinkBreak will start again automatically at your next scheduled time.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
                .accessibilityIdentifier("label.paused.until")

            Spacer()

            Button {
                controller.start()
            } label: {
                Text("Resume")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("button.paused.resume")

            Button(role: .destructive) {
                controller.stop()
            } label: {
                Text("Stop")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.white)
            .accessibilityIdentifier("button.paused.stop")
        }
        .padding(24)
    }

    private var untilFormatted: String {
        until.formatted(date: .omitted, time: .shortened)
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
}
