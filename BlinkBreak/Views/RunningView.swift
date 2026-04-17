//
//  RunningView.swift
//  BlinkBreak
//
//  The running-state view. Shows the countdown ring to the next break and a Stop
//  button. Uses TimelineView to tick the display every second.
//
//  No business logic here — every value shown is derived from `cycleStartedAt`
//  and the current wall-clock time. The only method we call on the controller
//  is `stop()`.
//

import SwiftUI
import BlinkBreakCore

// Cache the a11y duration formatter to avoid allocations in the TimelineView render loop
private let a11yDurationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    formatter.allowedUnits = [.minute, .second]
    return formatter
}()

struct RunningView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    let cycleStartedAt: Date

    private var breakFireTime: Date {
        cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remainingSeconds = max(0, breakFireTime.timeIntervalSince(context.date))
            let total = Int(remainingSeconds.rounded(.up))
            let countdownLabel = String(format: "%02d:%02d", total / 60, total % 60)
            let progress = (BlinkBreakConstants.breakInterval - remainingSeconds) / BlinkBreakConstants.breakInterval

            VStack(spacing: 20) {
                EyebrowLabel(text: "Next break in")

                CountdownRing(progress: progress, label: countdownLabel)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Time remaining")
                    .accessibilityValue(a11yDurationFormatter.string(from: remainingSeconds) ?? countdownLabel)
                    .accessibilityIdentifier("label.running.countdown")

                Text("Fires at \(breakFireTimeFormatted)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Button(role: .destructive) {
                    controller.stop()
                } label: {
                    Text("Stop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)
                .accessibilityIdentifier("button.running.stop")
            }
            .padding(24)
        }
    }

    /// Absolute fire time shown to the user as reassurance ("will interrupt me at 2:47 PM").
    private var breakFireTimeFormatted: String {
        return breakFireTime.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    ZStack {
        CalmBackground()
        RunningView(
            controller: PreviewSessionController.running,
            cycleStartedAt: Date().addingTimeInterval(-14 * 60)
        )
        .foregroundStyle(.white)
    }
}
