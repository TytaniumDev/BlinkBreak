//
//  WatchRunningView.swift
//  BlinkBreak Watch App
//
//  Running state on the Watch. Shows a large MM:SS countdown to the next break
//  and a Stop button. No ring — the Watch is small enough that plain digits
//  read better than a ring at a glance.
//

import SwiftUI
import BlinkBreakCore

struct WatchRunningView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    let cycleStartedAt: Date

    // Cached formatter for VoiceOver duration string
    private let accessibilityDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.minute, .second]
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
            let remaining = max(0, breakFireTime.timeIntervalSince(context.date))
            let total = Int(remaining.rounded(.up))
            let countdownLabel = String(format: "%02d:%02d", total / 60, total % 60)
            let a11yDuration = accessibilityDurationFormatter.string(from: Double(total)) ?? countdownLabel

            VStack(spacing: 8) {
                Text("NEXT BREAK")
                    .font(.caption2)
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))

                Text(countdownLabel)
                    .font(.system(size: 34, weight: .ultraLight, design: .default))
                    .monospacedDigit()
                    .accessibilityIdentifier("label.running.countdown")
                    .accessibilityLabel("Time remaining")
                    .accessibilityValue(a11yDuration)

                Spacer()

                Button("Stop") {
                    controller.stop()
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.6))
                .accessibilityIdentifier("button.running.stop")
            }
            .padding(.vertical, 8)
        }
    }
}
