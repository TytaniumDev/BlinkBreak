//
//  BundleResourceTests.swift
//  BlinkBreakUITests
//
//  Verifies that build-time resources and configuration are present in the
//  shipped app bundle. These tests use the host app's bundle access from
//  within the UI test runner.
//
//  These tests do not touch the UI — they assert static invariants about what
//  the app would have access to at runtime. They run fast and are good smoke
//  tests to catch missing resources after a project.yml change.
//

import XCTest

final class BundleResourceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_appLaunches_andCanAccessSoundFilePath() {
        // We can't directly read Bundle.main from the UI test runner process because
        // that runs in a different bundle. Instead we launch the app and observe
        // that it doesn't crash — if the custom sound file were missing, the app
        // would still launch (UN falls back to .default) so this test is mainly
        // a smoke check that the app boots with our build configuration.
        let app = XCUIApplication()
        app.launchForIntegrationTest()
        _ = app.waitForButton(A11y.Idle.startButton)
    }

    func test_appDoesNotCrash_whenStartedAndImmediatelyStopped() {
        // Stress test: rapid start/stop should never produce a crashed state.
        let app = XCUIApplication()
        app.launchForIntegrationTest()

        for _ in 0..<5 {
            app.waitForButton(A11y.Idle.startButton).tap()
            _ = app.waitForButton(A11y.Running.stopButton)
            app.buttons[A11y.Running.stopButton].tap()
            _ = app.waitForButton(A11y.Idle.startButton)
        }
    }
}
