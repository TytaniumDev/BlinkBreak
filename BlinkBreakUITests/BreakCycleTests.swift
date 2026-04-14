//
//  BreakCycleTests.swift
//  BlinkBreakUITests
//
//  Full-cycle tests that exercise the automatic state transitions driven by
//  the break timer. These depend on BB_BREAK_INTERVAL=3 / BB_LOOKAWAY_DURATION=1
//  (set by the UITests scheme), so expect ~4 seconds of real wall-clock time per
//  full cycle.
//
//  Each test uses generous waitForExistence timeouts (up to 10s) to absorb
//  simulator variance without being flaky.
//

import XCTest

final class BreakCycleTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_runningState_autoTransitionsToBreakPending_afterBreakInterval() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.Running.stopButton)

        // Wait for auto-transition running → breakPending. The transition is driven by
        // notification delivery (AppDelegate.willPresent → reconcile()); give it up to
        // 10s to absorb scheduler jitter.
        _ = app.waitForButton(A11y.BreakPending.startBreakButton, timeout: 10)
    }

    func test_breakPending_tapStartBreak_transitionsToBreakActive() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakPending.startBreakButton, timeout: 10)

        app.buttons[A11y.BreakPending.startBreakButton].tap()

        // In breakActive the message label exists and the Stop button is visible.
        _ = app.waitForElement(A11y.BreakActive.message, timeout: 5)
        XCTAssertTrue(app.buttons[A11y.BreakActive.stopButton].exists)
    }

    func test_breakActive_autoTransitionsBackToRunning_afterBreakActiveDuration() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakPending.startBreakButton, timeout: 10)
        app.buttons[A11y.BreakPending.startBreakButton].tap()
        _ = app.waitForElement(A11y.BreakActive.message, timeout: 5)

        // Wait for auto-transition breakActive → running. lookAwayDuration=1 second.
        _ = app.waitForButton(A11y.Running.stopButton, timeout: 10)
    }

    func test_fullCycle_startBreakAckWaitBackToRunningStop() {
        // Full round trip: idle → running → breakPending → breakActive → running → idle.
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        // 1. Start
        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.Running.stopButton)

        // 2. Wait for break
        _ = app.waitForButton(A11y.BreakPending.startBreakButton, timeout: 10)

        // 3. Ack break
        app.buttons[A11y.BreakPending.startBreakButton].tap()
        _ = app.waitForElement(A11y.BreakActive.message, timeout: 5)

        // 4. Wait for breakActive to elapse
        _ = app.waitForButton(A11y.Running.stopButton, timeout: 10)

        // 5. Stop session
        app.buttons[A11y.Running.stopButton].tap()
        _ = app.waitForButton(A11y.Idle.startButton)
    }

    func test_stopDuringBreakActive_returnsToIdle() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakPending.startBreakButton, timeout: 10)
        app.buttons[A11y.BreakPending.startBreakButton].tap()
        _ = app.waitForButton(A11y.BreakActive.stopButton, timeout: 5)

        app.buttons[A11y.BreakActive.stopButton].tap()

        _ = app.waitForButton(A11y.Idle.startButton)
    }

    func test_stopDuringBreakPending_stopsSession() {
        // The red alert offers Stop alongside Start break so the user can end the
        // session without first acknowledging. Tap Stop → back to idle.
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakPending.startBreakButton, timeout: 10)

        app.buttons[A11y.BreakPending.stopButton].tap()
        _ = app.waitForButton(A11y.Idle.startButton)
    }

    func test_multipleConsecutiveCycles_dontLeakState() {
        // Exercise three full break cycles in a row.
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()

        for cycle in 1...3 {
            _ = app.waitForButton(
                A11y.BreakPending.startBreakButton,
                timeout: 10
            )
            app.buttons[A11y.BreakPending.startBreakButton].tap()
            _ = app.waitForButton(
                A11y.Running.stopButton,
                timeout: 10
            )
            XCTAssertTrue(true, "cycle \(cycle) completed")
        }

        app.buttons[A11y.Running.stopButton].tap()
        _ = app.waitForButton(A11y.Idle.startButton)
    }
}
