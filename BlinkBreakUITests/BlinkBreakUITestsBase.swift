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
//  Timer overrides: `launchForIntegrationTest` sets BB_BREAK_INTERVAL and
//  BB_LOOKAWAY_DURATION (3 s each by default) so tests exercise a full 20-20-20
//  cycle in a few seconds, plus BB_UI_TESTING=1 (system default alarm sound;
//  see UITestSupport.swift). All three are honored only in DEBUG builds.
//
//  AlarmKit permission: before the first launch of a run, `AlarmPermission`
//  answers the real "Allow … to schedule alarms and timers?" prompt once.
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
    /// through SwiftUI's 250ms state-change animation; 1 second was too tight.
    func launchForIntegrationTest(
        breakIntervalSeconds: TimeInterval = 3,
        lookAwayDurationSeconds: TimeInterval = 3,
        resetDefaults: Bool = true
    ) {
        launchEnvironment["BB_UI_TESTING"] = "1"
        launchEnvironment["BB_BREAK_INTERVAL"] = String(breakIntervalSeconds)
        launchEnvironment["BB_LOOKAWAY_DURATION"] = String(lookAwayDurationSeconds)
        if resetDefaults {
            // Ask the app to wipe everything it stores before first use.
            launchArguments.append("-BB_RESET_DEFAULTS")
        }
        AlarmPermission.grantIfNeeded()
        launch()
    }

    /// Wait for a button with the given accessibility identifier to exist, up to `timeout` seconds.
    /// Fails the test if it doesn't appear.
    func waitForButton(_ id: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let button = buttons[id]
        let exists = button.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "Button \"\(id)\" did not appear within \(timeout)s", file: file, line: line)
        return button
    }

    /// Wait for an accessibility element (any element) with the given identifier to exist.
    func waitForElement(_ id: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = descendants(matching: .any).matching(identifier: id).firstMatch
        let exists = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "Element \"\(id)\" did not appear within \(timeout)s", file: file, line: line)
        return element
    }

    /// Wait for a button to NOT exist (i.e. state transitioned away from where it was showing).
    func waitForButtonToDisappear(_ id: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let button = buttons[id]
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: button)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Button \"\(id)\" did not disappear within \(timeout)s", file: file, line: line)
    }
}

/// Answers AlarmKit's "Allow … to schedule alarms and timers?" prompt once per
/// test run, before any test body starts.
///
/// The prompt is a SpringBoard alert that iOS shows the first time the app
/// schedules an alarm (its first Start), and it stays up until answered. The
/// simulator is erased before each run and `simctl privacy` has no AlarmKit
/// service, so the suite has to answer it through the UI, as a user would.
/// Doing that once, up front, means every test starts with permission granted
/// (like any launch after the first on a real device), whatever order the
/// tests run in and however they wait.
@MainActor
enum AlarmPermission {

    private static var isGranted = false

    static func grantIfNeeded() {
        guard !isGranted else { return }

        // A throwaway launch: fresh data, the default 20-minute interval so no
        // break fires, and the UI-test alarm sound.
        let app = XCUIApplication()
        app.launchEnvironment["BB_UI_TESTING"] = "1"
        app.launchArguments.append("-BB_RESET_DEFAULTS")
        app.launch()
        app.waitForButton(A11y.Idle.startButton).tap()

        // Start either asks for permission or, if this install already has
        // it (e.g. the test runner restarted mid-run), goes straight to running.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        let running = app.buttons[A11y.Running.stopButton]
        let promptOrRunning = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in allow.exists || running.exists },
            object: nil
        )
        _ = XCTWaiter().wait(for: [promptOrRunning], timeout: 10)
        if allow.exists {
            allow.tap()
        }

        // Back to idle so the throwaway session leaves no alarm behind.
        app.waitForButton(A11y.Running.stopButton).tap()
        _ = app.waitForButton(A11y.Idle.startButton)
        app.terminate()
        isGranted = true
    }
}

/// Accessibility identifier constants — centralized so test files don't drift from views.
enum A11y {
    enum Idle {
        static let startButton = "button.idle.start"
        static let feedbackButton = "button.idle.feedback"
    }
    enum Running {
        static let stopButton = "button.running.stop"
        static let countdown = "label.running.countdown"
        static let takeBreakNowButton = "button.running.takeBreakNow"
        static let pauseButton = "button.running.pause"
    }
    enum Paused {
        static let resumeButton = "button.paused.resume"
        static let stopButton = "button.paused.stop"
        static let untilLabel = "label.paused.until"
    }
    enum BreakPending {
        static let startBreakButton = "button.breakPending.startBreak"
        static let stopButton = "button.breakPending.stop"
    }
    enum BreakActive {
        static let stopButton = "button.breakActive.stop"
        static let message = "label.breakActive.message"
    }
    enum PermissionDenied {
        static let openSettingsButton = "button.permissionDenied.openSettings"
    }
    enum Schedule {
        static let section = "section.schedule"
        static let statusLabel = "label.schedule.status"
    }
}
