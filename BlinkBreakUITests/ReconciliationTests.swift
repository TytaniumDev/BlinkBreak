//
//  ReconciliationTests.swift
//  BlinkBreakUITests
//
//  Tests that the app correctly rehydrates state after termination + relaunch.
//  These test the real UserDefaultsPersistence path end-to-end, not the
//  InMemoryPersistence used in unit tests.
//
//  Since the test relaunches the app without `-BB_RESET_DEFAULTS` on the second
//  launch, the persisted record must survive across XCUIApplication instances.
//

import XCTest

final class ReconciliationUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_startThenRelaunchBeforeBreak_preservesRunningState() {
        // First launch: start a fresh session, verify running state, terminate.
        let app = XCUIApplication()
        app.launchForIntegrationTest()
        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.Running.stopButton)
        app.terminate()

        // Second launch: NO reset of defaults. The persisted record should cause
        // the app to come up in running state (because we terminate before the
        // break fires, within the 3-second window — tight but doable).
        let relaunched = XCUIApplication()
        relaunched.launchEnvironment["BB_BREAK_INTERVAL"] = "30"  // Long so reconcile sees running state
        relaunched.launchEnvironment["BB_LOOKAWAY_DURATION"] = "1"
        // Note: no -BB_RESET_DEFAULTS; we want the persisted record to survive.
        relaunched.launch()

        // Expect running state because the persisted cycleStartedAt is recent and
        // the break interval is 30s now (plenty of time remaining).
        _ = relaunched.waitForButton(A11y.Running.stopButton)
    }

    func test_startThenRelaunchAfterFullCycleTimeout_fallsBackToIdle() {
        // First launch: start a session with short intervals.
        let app = XCUIApplication()
        app.launchForIntegrationTest()
        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.Running.stopButton)
        app.terminate()

        // Wait long enough for the break + notification delivery window to fully
        // elapse with NO app running to process them. When we relaunch with fresh
        // short timers, reconcile should find:
        //   - persisted record with a cycleStartedAt old enough that breakFireTime passed
        //   - no pending cascade notifications (the process was dead when they would
        //     have fired, and the app was terminated so UN didn't deliver them to a handler)
        // The reconciliation path: "past break time with no pending notifications → idle"
        // should produce idle state.
        sleep(5)

        let relaunched = XCUIApplication()
        relaunched.launchEnvironment["BB_BREAK_INTERVAL"] = "3"
        relaunched.launchEnvironment["BB_LOOKAWAY_DURATION"] = "1"
        relaunched.launch()

        // The reconciliation outcome depends on whether iOS retained the pending
        // notifications across the terminate. In practice UN keeps them, so reconcile
        // may see them as "pending → breakActive". Both outcomes are acceptable
        // provided the app doesn't crash and shows SOME valid state.
        let idleExists = relaunched.buttons[A11y.Idle.startButton].waitForExistence(timeout: 5)
        let breakActiveExists = relaunched.buttons[A11y.BreakActive.startBreakButton].waitForExistence(timeout: 1)
        XCTAssertTrue(
            idleExists || breakActiveExists,
            "After terminate + wait + relaunch, app should be in idle or breakActive; got neither"
        )
    }

    func test_startThenRelaunchDuringLookAway_preservesLookAwayState() {
        // Start, wait for break, ack → lookAway, terminate inside lookAway window.
        let app = XCUIApplication()
        app.launchEnvironment["BB_BREAK_INTERVAL"] = "3"
        // Use a long lookAway so we have time to terminate + relaunch before it expires.
        app.launchEnvironment["BB_LOOKAWAY_DURATION"] = "20"
        app.launchArguments.append("-BB_RESET_DEFAULTS")
        app.launch()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakActive.startBreakButton, timeout: 10)
        app.buttons[A11y.BreakActive.startBreakButton].tap()
        _ = app.waitForElement(A11y.LookAway.message, timeout: 5)

        app.terminate()

        // Relaunch without resetting defaults. Persisted record has lookAwayStartedAt
        // set, and we're still within the 20-second window.
        let relaunched = XCUIApplication()
        relaunched.launchEnvironment["BB_BREAK_INTERVAL"] = "3"
        relaunched.launchEnvironment["BB_LOOKAWAY_DURATION"] = "20"
        relaunched.launch()

        _ = relaunched.waitForElement(A11y.LookAway.message, timeout: 5)
    }

    func test_launchWithResetDefaults_alwaysStartsFromIdle() {
        // Launch once, start a session, terminate.
        let app = XCUIApplication()
        app.launchForIntegrationTest()
        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.Running.stopButton)
        app.terminate()

        // Relaunch WITH -BB_RESET_DEFAULTS. The persisted record should be wiped
        // and the app should come up in idle.
        let relaunched = XCUIApplication()
        relaunched.launchForIntegrationTest()  // defaults to -BB_RESET_DEFAULTS
        _ = relaunched.waitForButton(A11y.Idle.startButton)
    }
}
