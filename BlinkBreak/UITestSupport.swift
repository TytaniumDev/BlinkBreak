//
//  UITestSupport.swift
//  BlinkBreak
//
//  Hooks for the XCUITest integration suite, all compiled out of Release builds.
//
//  - `BB_UI_TESTING=1` (environment): alarms use the system default sound
//    instead of a bundled file. The simulator's SpringBoard crashes playing a
//    custom alarm sound, and can't load the default one, so runs stay up and
//    quiet. AlarmKit permission is NOT bypassed: the tests answer the real
//    system prompt (see `AlarmPermission` in BlinkBreakUITestsBase.swift).
//  - `-BB_RESET_DEFAULTS` (launch argument): wipe stored data at launch so each
//    test starts from a clean idle state.
//
//  The cycle durations are shortened separately, via `BB_BREAK_INTERVAL` /
//  `BB_LOOKAWAY_DURATION` (see BlinkBreakConstants).
//

import Foundation

enum UITestSupport {

    static let isActive: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["BB_UI_TESTING"] == "1"
        #else
        false
        #endif
    }()

    static let resetRequested: Bool = {
        #if DEBUG
        CommandLine.arguments.contains("-BB_RESET_DEFAULTS")
        #else
        false
        #endif
    }()
}
