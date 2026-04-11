//
//  RunningView.swift
//  BlinkBreak
//
//  The running-state view. Shows the countdown ring to the next break and a Stop
//  button. Uses a Timer.publish to tick the display every second.
//
//  No business logic here — every value shown is derived from `cycleStartedAt`
//  and the current wall-clock time. The only method we call on the controller
//  is `stop()`.
//

import SwiftUI
import BlinkBreakCore

struct RunningView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    let cycleStartedAt: Date

    /// Local ticker so the countdown label updates every second. Independent of the
    /// RootView's reconcile tick — this one only drives the ring animation.
    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            EyebrowLabel(text: "Next break in")

            CountdownRing(progress: progress, label: countdownLabel)
                .accessibilityIdentifier("label.running.countdown")

            Text("Fires at \(breakFireTimeFormatted)")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            DestructiveButton(title: "Stop") {
                controller.stop()
            }
            .accessibilityIdentifier("button.running.stop")
        }
        .padding(24)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - Derived values

    private var breakFireTime: Date {
        cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
    }

    /// Seconds remaining until the break fires, clamped to [0, breakInterval].
    private var remainingSeconds: TimeInterval {
        max(0, breakFireTime.timeIntervalSince(now))
    }

    /// Countdown label formatted as `MM:SS`.
    private var countdownLabel: String {
        let total = Int(remainingSeconds.rounded(.up))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Progress from 0 (just started) to 1 (break imminent).
    private var progress: Double {
        let total = BlinkBreakConstants.breakInterval
        let elapsed = total - remainingSeconds
        return elapsed / total
    }

    /// Absolute fire time shown to the user as reassurance ("will interrupt me at 2:47 PM").
    private var breakFireTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: breakFireTime)
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
