//
//  ScheduleStatusLabel.swift
//  BlinkBreak
//
//  Shows schedule context above the Start button. The status text is
//  computed by ScheduleEvaluator in BlinkBreakCore.
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
        Color("BackgroundCalmTop").ignoresSafeArea()
        ScheduleStatusLabel(text: "Starts at 9:00 AM")
    }
}
