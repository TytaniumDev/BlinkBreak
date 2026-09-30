//
//  ScheduleStatusLabel.swift
//  BlinkBreak
//
//  Shows schedule context above the Start button. The status text comes from
//  `SessionControllerProtocol.scheduleStatus(at:)`.
//

import SwiftUI

struct ScheduleStatusLabel: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityIdentifier("label.schedule.status")
        }
    }
}

#Preview("Before window") {
    ZStack {
        CalmBackground()
        ScheduleStatusLabel(text: "Starts at 9:00 AM")
    }
}
