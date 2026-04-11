//
//  EyebrowLabel.swift
//  BlinkBreak
//
//  A small uppercase label with muted color — used above screen titles to provide
//  context ("BlinkBreak", "Next break in", "Looking away", etc.). Reusable component,
//  ~20 lines, takes only a string.
//

import SwiftUI

/// Small uppercase text with letter spacing, used as a section header above titles.
///
/// Flutter analogue: a `Text` with a custom `TextStyle` wrapped in a stateless widget.
struct EyebrowLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2)
            .tracking(1.5)  // letter-spacing
            .foregroundStyle(.white.opacity(0.6))
    }
}

#Preview {
    EyebrowLabel(text: "Next break in")
        .padding()
        .background(Color.black)
}
