//
//  DestructiveButton.swift
//  BlinkBreak
//
//  An outlined pill button used for destructive-but-not-dangerous actions
//  like Stop. Visually less prominent than PrimaryButton so it doesn't compete
//  for attention with the main CTA.
//

import SwiftUI

/// An outlined pill-shaped button used for Stop / cancel actions.
///
/// Flutter analogue: `OutlinedButton` with a custom shape.
struct DestructiveButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DestructiveButton(title: "Stop", action: {})
        .padding()
        .background(Color.black)
}
