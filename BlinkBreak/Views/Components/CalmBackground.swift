//
//  CalmBackground.swift
//  BlinkBreak
//
//  The dark teal/charcoal background used for idle, running, and breakActive states.
//

import SwiftUI

/// Dark teal background applied to idle, running, and breakActive screens.
/// Edge-to-edge, ignores safe areas.
///
/// Flutter analogue: a `Container` with a fixed decoration used as the scaffold background.
struct CalmBackground: View {
    var body: some View {
        LinearGradient(colors: [.calmTop, .calmBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

#Preview {
    CalmBackground()
}
