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

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            Text("NEXT BREAK")
                .font(.caption2)
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))

            Text(countdownLabel)
                .font(.system(size: 34, weight: .ultraLight, design: .default))
                .monospacedDigit()

            Spacer()

            Button("Stop") {
                controller.stop()
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.6))
        }
        .padding(.vertical, 8)
        .onReceive(ticker) { now = $0 }
    }

    private var countdownLabel: String {
        let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        let remaining = max(0, breakFireTime.timeIntervalSince(now))
        let total = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
