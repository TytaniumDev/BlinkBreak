//
//  BlinkBreakWatchApp.swift
//  BlinkBreak Watch App
//
//  The watchOS app entry point. The SessionController is owned by WatchAppDelegate
//  (see the file comment there for why) — this struct just reads it and plumbs it
//  into the SwiftUI view hierarchy.
//

import SwiftUI
import BlinkBreakCore

@main
struct BlinkBreakWatchApp: App {

    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView(controller: appDelegate.controller)
        }
    }
}
