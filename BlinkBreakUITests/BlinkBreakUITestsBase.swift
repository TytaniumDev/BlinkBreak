//
//  BlinkBreakUITestsBase.swift
//  BlinkBreakUITests
//
//  Shared helpers for the XCUITest integration suite.
//
//  IMPORTANT: This suite is slow and should only be run as a final verification
//  step, not during iteration. Use ./scripts/test.sh for the fast unit-test loop
//  and ./scripts/test-integration.sh for this suite.
//
//  Timer overrides: the scheme sets BB_BREAK_INTERVAL=3 and BB_LOOKAWAY_DURATION=1
//  so tests exercise a full 20-20-20 cycle in ~4 seconds of wall-clock time.
//

import XCTest

/// Base helpers used by every test class. Subclass `XCTestCase` directly — this
/// file only provides shared utilities via extensions on XCUIElement and XCUIApplication.
extension XCUIApplication {

    /// Launch the app with the fast-timer environment variables set. Tests that
    /// need to override or clear persisted state can pass additional arguments.
    ///
    /// Defaults: 3-second break interval, 3-second breakActive duration. The breakActive
    /// needs to be wide enough for XCUITest to observe the transient breakActive state
    /// through SwiftUI's 250ms state-change animation and the 1-second reconcile
    /// tick; 1 second was too tight.
    func launchForIntegrationTest(
        breakIntervalSeconds: TimeInterval = 3,
        lookAwayDurationSeconds: TimeInterval = 3,
        resetDefaults: Bool = true
    ) {
        launchEnvironment["BB_BREAK_INTERVAL"] = String(breakIntervalSeconds)
        launchEnvironment["BB_LOOKAWAY_DURATION"] = String(lookAwayDurationSeconds)
        if resetDefaults {
            // Ask the app to wipe the UserDefaults session record before first use.
            launchArguments.append("-BB_RESET_DEFAULTS")
        }
        launch()
    }

    /// Wait for a button with the given accessibility identifier to exist, up to `timeout` seconds.
    /// Fails the test if it doesn't appear.
    func waitForButton(_ id: String, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) -> XCUIElement {
        let button = buttons[id]
        let exists = button.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "Button \"\(id)\" did not appear within \(timeout)s", file: file, line: line)
        return button
    }

    /// Wait for an accessibility element (any element) with the given identifier to exist.
    func waitForElement(_ id: String, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) -> XCUIElement {
        let element = descendants(matching: .any).matching(identifier: id).firstMatch
        let exists = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "Element \"\(id)\" did not appear within \(timeout)s", file: file, line: line)
        return element
    }

    /// Wait for a button to NOT exist (i.e. state transitioned away from where it was showing).
    func waitForButtonToDisappear(_ id: String, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        let button = buttons[id]
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: button)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Button \"\(id)\" did not disappear within \(timeout)s", file: file, line: line)
    }
}

/// Accessibility identifier constants — centralized so test files don't drift from views.
enum A11y {
    enum Idle {
        static let startButton = "button.idle.start"
    }
    enum Running {
        static let stopButton = "button.running.stop"
        static let countdown = "label.running.countdown"
        static let takeBreakNowButton = "button.running.takeBreakNow"
    }
    enum BreakPending {
        static let startBreakButton = "button.breakPending.startBreak"
        static let stopButton = "button.breakPending.stop"
    }
    enum BreakActive {
        static let stopButton = "button.breakActive.stop"
        static let message = "label.breakActive.message"
    }
    enum Schedule {
        static let section = "section.schedule"
        static let statusLabel = "label.schedule.status"
    }
}
