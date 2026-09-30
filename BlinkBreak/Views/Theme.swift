//
//  Theme.swift
//  BlinkBreak
//
//  The app's colors and layout constants in one place, so a visual-iteration PR
//  changes them here instead of hunting through views.
//
//  Flutter analogue: a `ThemeData` extension with the app's custom colors.
//

import SwiftUI

extension Color {
    /// Top of the calm dark-teal gradient.
    static let calmTop = Color(red: 0.04, green: 0.06, blue: 0.08)
    /// Bottom of the calm dark-teal gradient.
    static let calmBottom = Color(red: 0.02, green: 0.10, blue: 0.12)
    /// The deep red of the "break time" screen.
    static let alertRed = Color(red: 0.69, green: 0.00, blue: 0.13)
}

enum Layout {
    /// Content never gets wider than this, so text and controls stay readable
    /// on iPad and in wide Mac windows.
    static let readableWidth: CGFloat = 560
    /// Padding between the content and the window edge.
    static let screenPadding: CGFloat = 24
}
