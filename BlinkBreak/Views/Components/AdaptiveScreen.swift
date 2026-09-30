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
                .scrollBounceBehavior(.basedOnSize)
            }
            actions
                .frame(maxWidth: Layout.readableWidth)
        }
        .padding(Layout.screenPadding)
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
