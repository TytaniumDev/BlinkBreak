//
//  RunningView.swift
//  BlinkBreak
//
//  The running-state view. Shows the countdown ring to the next break, the
//  sound toggle, "Take break now", and Stop. TimelineView ticks the display
//  every second.
//
//  No business logic here — every value shown is derived from `breakAt` and
//  the current wall-clock time.
//

import BlinkBreakCore
import SwiftUI

// Cached so the once-a-second render doesn't allocate a formatter each tick.
private let a11yDurationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    formatter.allowedUnits = [.minute, .second]
    return formatter
}()

struct RunningView<Controller: SessionControllerProtocol>: View {

    let controller: Controller
    /// When the break alarm fires.
    let breakAt: Date

    var body: some View {
        AdaptiveScreen {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                EyebrowLabel(text: "Next break in")

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdown(at: context.date)
                }

                Text("Fires at \(breakAt.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))

                SoundToggleRow(
                    isMuted: controller.muteAlarmSound,
                    onToggle: { controller.updateAlarmSound(muted: $0) }
                )
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
        } actions: {
            VStack(spacing: 12) {
                Button("Take break now") {
                    Task { await controller.takeBreakNow() }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityIdentifier("button.running.takeBreakNow")

                StopButton(identifier: "button.running.stop") {
                    await controller.stop()
                }
            }
        }
    }

    private func countdown(at date: Date) -> some View {
        let interval = BlinkBreakConstants.breakInterval
        let remaining = max(0, breakAt.timeIntervalSince(date))
        let total = Int(remaining.rounded(.up))
        let label = String(format: "%02d:%02d", total / 60, total % 60)
        return CountdownRing(progress: (interval - remaining) / interval, label: label)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time remaining")
            .accessibilityValue(a11yDurationFormatter.string(from: remaining) ?? label)
            .accessibilityIdentifier("label.running.countdown")
    }
}

#Preview {
    ZStack {
        CalmBackground()
        RunningView(
            controller: PreviewSessionController.running,
            breakAt: Date().addingTimeInterval(6 * 60)
        )
        .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}
