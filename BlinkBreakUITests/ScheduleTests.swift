//
//  ScheduleTests.swift
//  BlinkBreakUITests
//
//  Integration tests for the weekly schedule feature.
//

import XCTest

final class ScheduleTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForIntegrationTest()
    }

    func testIdleViewShowsScheduleSection() {
        let section = app.otherElements[A11y.Schedule.section]
        XCTAssertTrue(section.waitForExistence(timeout: 5),
                      "Schedule section should be visible on idle screen")
    }

    func testStartButtonExistsWithSchedule() {
        let startButton = app.buttons[A11y.Idle.startButton]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5),
                      "Start button should exist alongside schedule")
        startButton.tap()

        let stopButton = app.buttons[A11y.Running.stopButton]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5),
                      "Should transition to running after tapping Start")
    }
}
