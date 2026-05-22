//
//  LaunchAndIdleTests.swift
//  BlinkBreakUITests
//
//  Sanity tests for app launch and the idle state. These should all pass in
//  well under a second; they don't need the full break cycle timing.
//

import XCTest

final class LaunchAndIdleTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_appLaunches_showsIdleState() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        // The Start button is only shown in the idle state, so its presence
        // confirms both "app launched" and "state is idle".
        _ = app.waitForButton(A11y.Idle.startButton)
    }

    func test_appLaunches_idleStateHasNoStopButton() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        // Sanity: the Stop button (running/breakActive state) must NOT exist in idle.
        _ = app.waitForButton(A11y.Idle.startButton)
        XCTAssertFalse(app.buttons[A11y.Running.stopButton].exists)
        XCTAssertFalse(app.buttons[A11y.BreakActive.stopButton].exists)
    }

    func test_appLaunches_idleStateHasNoStartBreakButton() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        _ = app.waitForButton(A11y.Idle.startButton)
        XCTAssertFalse(app.buttons[A11y.BreakPending.startBreakButton].exists)
    }

    func test_feedbackButton_opensAndDismissesFeedbackSheet() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        // Wait for the feedback button and tap it
        let feedbackButton = app.waitForButton(A11y.Idle.feedbackButton)
        feedbackButton.tap()

        // Verify that the feedback sheet is presented
        let navTitle = app.navigationBars["Feedback"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 2))

        // Find and tap the Cancel button to dismiss it
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists)
        cancelButton.tap()

        // Verify we are back to the idle screen
        _ = app.waitForButton(A11y.Idle.startButton)
    }
}
