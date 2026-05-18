//
//  ScreenshotTests.swift
//  BlinkBreakUITests
//
//  Captures App Store marketing screenshots by driving the app to each key
//  state and attaching a full-screen capture to the test result bundle.
//
//  This is NOT part of the regular integration suite — it's gated on the
//  BB_CAPTURE_SCREENSHOTS environment variable so ./scripts/test-integration.sh
//  skips it. Run it explicitly via ./scripts/capture-screenshots.sh (or the
//  Xcode scheme) against each device you need App Store assets for.
//
//  How to extract the PNGs after a run:
//    1. The capture script runs xcodebuild with -resultBundlePath build/screenshots.xcresult
//    2. Unpack attachments with:
//         xcrun xcresulttool export attachments \
//             --path build/screenshots.xcresult \
//             --output-path build/screenshots
//    3. The attachments land as PNGs named after each test + timestamp.
//
//  App Store Connect requires 6.9" iPhone screenshots (iPhone 16 Pro Max:
//  1320 × 2868 portrait). Run against a matching simulator.
//

import XCTest

final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        // Skip unless explicitly opted in. This keeps the regular integration
        // suite fast and prevents accidental captures in CI.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BB_CAPTURE_SCREENSHOTS"] == "1",
            "Set BB_CAPTURE_SCREENSHOTS=1 to run screenshot capture."
        )
    }

    // MARK: - Screens

    func test_capture_01_idle() throws {
        let app = launched()
        _ = app.waitForButton(A11y.Idle.startButton)
        snapshot(app, named: "01-idle")
    }

    func test_capture_02_running() throws {
        let app = launched(breakInterval: 600) // long enough to not auto-transition mid-capture
        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.Running.stopButton)
        // Let the countdown ring render a frame.
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, named: "02-running")
    }

    func test_capture_03_breakPending() throws {
        let app = launched(breakInterval: 3)
        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakPending.startBreakButton, timeout: 10)
        snapshot(app, named: "03-break-pending")
    }

    func test_capture_04_breakActive() throws {
        let app = launched(breakInterval: 3, lookAwayDuration: 60)
        app.waitForButton(A11y.Idle.startButton).tap()
        _ = app.waitForButton(A11y.BreakPending.startBreakButton, timeout: 10)
        app.buttons[A11y.BreakPending.startBreakButton].tap()
        _ = app.waitForElement(A11y.BreakActive.message, timeout: 5)
        Thread.sleep(forTimeInterval: 0.5)
        snapshot(app, named: "04-break-active")
    }

    // MARK: - Helpers

    private func launched(
        breakInterval: TimeInterval = 600,
        lookAwayDuration: TimeInterval = 20
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchForIntegrationTest(
            breakIntervalSeconds: breakInterval,
            lookAwayDurationSeconds: lookAwayDuration
        )
        return app
    }

    private func snapshot(_ app: XCUIApplication, named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
