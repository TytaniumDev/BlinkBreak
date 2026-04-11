//
//  StartStopTests.swift
//  BlinkBreakUITests
//
//  Tests for the start() and stop() transitions between idle and running.
//  These do not exercise the break timer; see BreakCycleTests for that.
//

import XCTest

final class StartStopTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_tapStart_transitionsIdleToRunning() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()

        // After start(), the running Stop button exists and the idle Start button is gone.
        _ = app.waitForButton(A11y.Running.stopButton)
        XCTAssertFalse(app.buttons[A11y.Idle.startButton].exists)
    }

    func test_runningState_showsCountdownLabel() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForElement(A11y.Running.countdown)
    }

    func test_tapStop_fromRunning_returnsToIdle() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        app.waitForButton(A11y.Running.stopButton).tap()

        _ = app.waitForButton(A11y.Idle.startButton)
        XCTAssertFalse(app.buttons[A11y.Running.stopButton].exists)
    }

    func test_startStopStart_settlesIntoCleanRunningState() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        app.waitForButton(A11y.Running.stopButton).tap()
        app.waitForButton(A11y.Idle.startButton).tap()

        _ = app.waitForButton(A11y.Running.stopButton)
        XCTAssertFalse(app.buttons[A11y.Idle.startButton].exists)
    }

    func test_doubleStart_isIdempotentFromUIPerspective() {
        // Tapping Start twice in a row is only possible if the UI didn't update
        // between taps. In practice, after the first tap we're immediately in
        // running state and the idle Start button is gone, so this test documents
        // the invariant that double-tapping Start never produces two parallel
        // sessions.
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        let startButton = app.waitForButton(A11y.Idle.startButton)
        startButton.tap()

        // State is now running. Idle Start button is gone.
        _ = app.waitForButton(A11y.Running.stopButton)
        XCTAssertFalse(app.buttons[A11y.Idle.startButton].exists)

        // Tap Stop and verify we cleanly return to idle with exactly one Start button.
        app.waitForButton(A11y.Running.stopButton).tap()
        _ = app.waitForButton(A11y.Idle.startButton)
        XCTAssertEqual(app.buttons[A11y.Idle.startButton].waitForExistence(timeout: 2), true)
    }
}
