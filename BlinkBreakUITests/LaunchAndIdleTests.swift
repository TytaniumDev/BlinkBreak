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

        // Sanity: the Stop button (running/lookAway state) must NOT exist in idle.
        _ = app.waitForButton(A11y.Idle.startButton)
        XCTAssertFalse(app.buttons[A11y.Running.stopButton].exists)
        XCTAssertFalse(app.buttons[A11y.LookAway.stopButton].exists)
    }

    func test_appLaunches_idleStateHasNoStartBreakButton() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        _ = app.waitForButton(A11y.Idle.startButton)
        XCTAssertFalse(app.buttons[A11y.BreakActive.startBreakButton].exists)
    }
}
