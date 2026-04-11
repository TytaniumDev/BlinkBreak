//
//  PrimaryButton.swift
//  BlinkBreak
//
//  The filled blue pill button used for the primary action on idle (Start) and
//  for the "Start break" acknowledgment on the break alert.
//

import SwiftUI

/// A filled, pill-shaped primary action button.
///
/// Flutter analogue: `ElevatedButton` with a custom shape and fill.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PrimaryButton(title: "Start", action: {})
        .padding()
        .background(Color.black)
}
