//
//  BlinkBreakApp.swift
//  BlinkBreak
//
//  The iOS app's entry point. In SwiftUI, your app is described by a struct that
//  conforms to the `App` protocol and is marked with `@main`. The `body` of that
//  struct describes the scene tree — in our case, a single `WindowGroup` containing
//  a `RootView`.
//
//  Flutter analogue: this is `void main() { runApp(MyApp()); }` + the root `MaterialApp`.
//

import SwiftUI

@main
struct BlinkBreakApp: App {

    init() {
        // Release-only crash / error reporting. No-op in DEBUG.
        SentryBootstrap.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView(controller: AppEnvironment.controller)
                .environment(\.feedbackReporter, AppEnvironment.feedbackReporter)
        }
    }
}
