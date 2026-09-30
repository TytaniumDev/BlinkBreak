//
//  StopButton.swift
//  BlinkBreak
//
//  The full-width "Stop" button shared by every active-session screen.
//  ⌘. triggers it from a hardware keyboard (iPad, Mac).
//
//  Flutter analogue: a small stateless OutlinedButton wrapper.
//

import SwiftUI

struct StopButton: View {
    /// Accessibility identifier used by the UI tests (e.g. "button.running.stop").
    let identifier: String
    let action: @MainActor () async -> Void

    var body: some View {
        Button(role: .destructive) {
            Task { await action() }
        } label: {
            Text("Stop")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.white)
        .keyboardShortcut(".", modifiers: .command)
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    StopButton(identifier: "preview") {}
        .padding()
        .background(Color.calmTop)
}
