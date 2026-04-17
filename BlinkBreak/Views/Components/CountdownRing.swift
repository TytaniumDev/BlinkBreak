//
//  CountdownRing.swift
//  BlinkBreak
//
//  A circular progress ring that shows the time remaining until the next break.
//  Purely visual — takes a progress (0...1) and a label string. No business logic.
//
//  The ring animates via SwiftUI's implicit animation when `progress` changes.
//

import SwiftUI

/// A thin circular progress ring with a centered label.
///
/// Flutter analogue: `CircularProgressIndicator` with a custom child widget in its center.
struct CountdownRing: View {
    /// Progress of the countdown, from 0.0 (just started) to 1.0 (break imminent).
    let progress: Double

    /// Text shown in the center of the ring, typically `MM:SS`.
    let label: String

    /// Optional accessibility label text. If nil, `label` is used.
    var accessibilityLabelText: String? = nil

    /// The ring's color — defaults to the app accent color.
    var ringColor: Color = .accentColor

    var body: some View {
        ZStack {
            // Background ring (full circle, dim).
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 6)

            // Foreground ring (grows clockwise as progress increases).
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                // Rotate so 12 o'clock is the start position.
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            // Centered countdown label.
            Text(label)
                .font(.system(size: 40, weight: .ultraLight, design: .default))
                .monospacedDigit()  // stable width as digits change
                .foregroundStyle(.white)
        }
        .frame(width: 180, height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(accessibilityLabelText ?? label)
    }
}

#Preview {
    VStack(spacing: 24) {
        CountdownRing(progress: 0.2, label: "14:32")
        CountdownRing(progress: 0.8, label: "03:12")
    }
    .padding()
    .background(Color.black)
}
