//
//  AdaptiveScreen.swift
//  BlinkBreak
//
//  The layout every screen uses so it works at any window size — iPhone in
//  either orientation, iPad split view / Stage Manager, and resizable Mac
//  windows. Content is capped at a readable width and centered; it fills the
//  height when there's room (so Spacers still push things apart) and scrolls
//  when there isn't. The action buttons stay pinned at the bottom.
//
//  Flutter analogue: a `LayoutBuilder` + `ConstrainedBox(minHeight:)` inside a
//  `SingleChildScrollView`, with a bottom button bar.
//

import SwiftUI

struct AdaptiveScreen<Content: View, Actions: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { proxy in
                ScrollView {
                    content
                        .frame(maxWidth: Layout.readableWidth)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                // Inset the content inside the scroll view rather than padding the
                // scroll view itself. A ScrollView clips to its bounds, and some
                // controls (the iOS 26 switch) draw a little past their frame, so the
                // scroll view needs room beyond the content's edges or they get cut.
                .contentMargins(.horizontal, Layout.screenPadding, for: .scrollContent)
                .scrollBounceBehavior(.basedOnSize)
            }
            actions
                .frame(maxWidth: Layout.readableWidth)
                .padding(.horizontal, Layout.screenPadding)
        }
        .padding(.vertical, Layout.screenPadding)
    }
}

#Preview {
    ZStack {
        CalmBackground()
        AdaptiveScreen {
            VStack {
                Text("Content")
                Spacer()
                Text("Bottom of content")
            }
        } actions: {
            Button("Action") {}
                .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
    }
}
