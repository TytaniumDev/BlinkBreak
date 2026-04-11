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

    func test_runningState_autoTransitionsToBreakActive_afterBreakInterval() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.Running.stopButton)

        // Wait for auto-transition running → breakActive. The reconcile tick runs
        // every 1s; break fires at 3s; give it up to 10s to absorb scheduler jitter.
        _ = app.waitForButton(A11y.BreakActive.startBreakButton, timeout: 10)
    }

    func test_breakActive_tapStartBreak_transitionsToLookAway() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakActive.startBreakButton, timeout: 10)

        app.buttons[A11y.BreakActive.startBreakButton].tap()

        // In lookAway the message label exists and the Stop button is visible.
        _ = app.waitForElement(A11y.LookAway.message, timeout: 5)
        XCTAssertTrue(app.buttons[A11y.LookAway.stopButton].exists)
    }

    func test_lookAway_autoTransitionsBackToRunning_afterLookAwayDuration() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakActive.startBreakButton, timeout: 10)
        app.buttons[A11y.BreakActive.startBreakButton].tap()
        _ = app.waitForElement(A11y.LookAway.message, timeout: 5)

        // Wait for auto-transition lookAway → running. lookAwayDuration=1 second.
        _ = app.waitForButton(A11y.Running.stopButton, timeout: 10)
    }

    func test_fullCycle_startBreakAckWaitBackToRunningStop() {
        // Full round trip: idle → running → breakActive → lookAway → running → idle.
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        // 1. Start
        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.Running.stopButton)

        // 2. Wait for break
        _ = app.waitForButton(A11y.BreakActive.startBreakButton, timeout: 10)

        // 3. Ack break
        app.buttons[A11y.BreakActive.startBreakButton].tap()
        _ = app.waitForElement(A11y.LookAway.message, timeout: 5)

        // 4. Wait for lookAway to elapse
        _ = app.waitForButton(A11y.Running.stopButton, timeout: 10)

        // 5. Stop session
        app.buttons[A11y.Running.stopButton].tap()
        _ = app.waitForButton(A11y.Idle.startButton)
    }

    func test_stopDuringLookAway_returnsToIdle() {
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakActive.startBreakButton, timeout: 10)
        app.buttons[A11y.BreakActive.startBreakButton].tap()
        _ = app.waitForButton(A11y.LookAway.stopButton, timeout: 5)

        app.buttons[A11y.LookAway.stopButton].tap()

        _ = app.waitForButton(A11y.Idle.startButton)
    }

    func test_stopDuringBreakActive_isNotDirectlyExposedInUI_butAckThenStopWorks() {
        // BreakActiveView doesn't show a Stop button — the red alert has only
        // "Start break". To stop during breakActive, the user must acknowledge
        // first (going to lookAway) and then stop from there. This test documents
        // that flow.
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakActive.startBreakButton, timeout: 10)

        // Verify no Stop button exists in breakActive.
        XCTAssertFalse(app.buttons[A11y.Running.stopButton].exists)
        XCTAssertFalse(app.buttons[A11y.LookAway.stopButton].exists)

        // Ack, then stop from lookAway.
        app.buttons[A11y.BreakActive.startBreakButton].tap()
        _ = app.waitForButton(A11y.LookAway.stopButton, timeout: 5)
        app.buttons[A11y.LookAway.stopButton].tap()
        _ = app.waitForButton(A11y.Idle.startButton)
    }

    func test_multipleConsecutiveCycles_dontLeakState() {
        // Exercise three full break cycles in a row.
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        app.waitForButton(A11y.Idle.startButton).tap()

        for cycle in 1...3 {
            _ = app.waitForButton(
                A11y.BreakActive.startBreakButton,
                timeout: 10
            )
            app.buttons[A11y.BreakActive.startBreakButton].tap()
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
