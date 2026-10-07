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

@MainActor
final class ReconciliationUITests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    func test_startThenRelaunchBeforeBreak_preservesRunningState() {
        // First launch: start a fresh session, verify running state, terminate.
        // The break alarm is booked 30 s out, so it can't fire before the
        // relaunch below (terminate + relaunch takes ~5 s).
        let app = XCUIApplication()
        app.launchForIntegrationTest(breakIntervalSeconds: 30)
        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.Running.stopButton)
        app.terminate()

        // Second launch: NO reset of defaults, so the persisted record survives.
        let relaunched = XCUIApplication()
        relaunched.launchForIntegrationTest(breakIntervalSeconds: 30, resetDefaults: false)

        // Expect running state: the persisted record plus the still-pending
        // system alarm decide the state, not the relaunch's interval.
        _ = relaunched.waitForButton(A11y.Running.stopButton)
    }

    func test_startThenRelaunchAfterBreakTime_keepsSessionGoing() {
        // First launch: start a session with short intervals, then terminate.
        let app = XCUIApplication()
        app.launchForIntegrationTest()
        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.Running.stopButton)
        app.terminate()

        // Let the break come due with no app running.
        sleep(5)

        // Relaunch without resetting. Either the break alarm is still ringing
        // (breakPending), or it's already gone and reconcile skipped ahead to the
        // next cycle (running). The session must not silently end.
        let relaunched = XCUIApplication()
        relaunched.launchForIntegrationTest(resetDefaults: false)

        let breakPending = relaunched.buttons[A11y.BreakPending.startBreakButton]
        let running = relaunched.buttons[A11y.Running.stopButton]
        let eitherState = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in breakPending.exists || running.exists },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [eitherState], timeout: 10),
            .completed,
            "After terminate + wait + relaunch, the session should still be active"
        )
    }

    func test_startThenRelaunchDuringBreakActive_preservesBreakActiveState() {
        // Start, wait for break, ack → breakActive, terminate inside breakActive window.
        let app = XCUIApplication()
        // Use a long breakActive duration so we have time to terminate + relaunch before it expires.
        app.launchForIntegrationTest(lookAwayDurationSeconds: 20)

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakPending.startBreakButton, timeout: 10)
        app.buttons[A11y.BreakPending.startBreakButton].tap()
        _ = app.waitForElement(A11y.BreakActive.message, timeout: 5)

        app.terminate()

        // Relaunch without resetting defaults. The persisted record is in the
        // look-away phase and we're still within the 20-second window.
        let relaunched = XCUIApplication()
        relaunched.launchForIntegrationTest(lookAwayDurationSeconds: 20, resetDefaults: false)

        _ = relaunched.waitForElement(A11y.BreakActive.message, timeout: 5)
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
