//
//  CalmBackground.swift
//  BlinkBreak
//
//  The dark teal/charcoal background used for idle, running, and lookAway states.
//  Centralized here so a visual iteration PR only touches this one file to
//  rebrand all the passive screens at once.
//

import SwiftUI

/// Dark teal background applied to idle, running, and lookAway screens.
/// Edge-to-edge, ignores safe areas.
///
/// Flutter analogue: a `Container` with a fixed decoration used as the scaffold background.
struct CalmBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.06, blue: 0.08),
                Color(red: 0.02, green: 0.10, blue: 0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

#Preview {
    CalmBackground()
}
