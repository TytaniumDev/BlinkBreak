//
//  RehostedCoreTests.swift
//  BlinkBreakTests
//
//  A stub file so the BlinkBreakTests target has at least one source file for
//  Xcode / xcodebuild to build. The real tests live in
//  `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/` and are run via
//  `swift test` from inside the package. This target exists so
//  `xcodebuild test -scheme BlinkBreak` also runs them through the regular
//  iOS test scheme path used by GitHub Actions.
//
//  When the user installs full Xcode.app, they can add imports here to surface
//  the BlinkBreakCoreTests suite via the iOS scheme — or leave the stub as-is
//  and rely on `swift test` for the core tests.
//

import Testing
@testable import BlinkBreakCore

@Suite("BlinkBreakTests rehost")
struct RehostedCoreTests {

    @Test("BlinkBreakCore is importable from the iOS test target")
    func importsOK() {
        // Sanity: ensure the core library is linked into this target.
        #expect(BlinkBreakConstants.breakInterval == 20 * 60)
    }
}
