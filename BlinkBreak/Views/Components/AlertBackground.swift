//
//  AlertBackground.swift
//  BlinkBreak
//
//  The bold red full-bleed background used only during the breakPending state.
//  Intentional visual departure from the calm theme to make it unmistakable
//  that the app is demanding attention.
//

import SwiftUI

/// Full-bleed red background used only on the breakPending alert screen.
///
/// Flutter analogue: a Scaffold with a red background color, edge-to-edge.
struct AlertBackground: View {
    var body: some View {
        Color("BackgroundAlert")
            .ignoresSafeArea()
    }
}

#Preview {
    AlertBackground()
}
