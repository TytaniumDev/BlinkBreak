//
//  WatchBreakActiveView.swift
//  BlinkBreak Watch App
//
//  Break-active state on the Watch. Minimal — the user should NOT be staring at
//  their wrist during the 20-second break. A gentle "look 20 ft away" message
//  plus a subtle "we'll tap you when done" reassurance is all we need.
//

import SwiftUI

struct WatchBreakActiveView: View {

    var body: some View {
        VStack(spacing: 8) {
            Text("Look 20 ft away")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("label.breakActive.message")

            Text("We'll tap you when it's time")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
