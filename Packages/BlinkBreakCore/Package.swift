// swift-tools-version: 6.0
//
// BlinkBreakCore — all business logic for the BlinkBreak app.
//
// Flutter analogue: a plain Dart package in `packages/` that the iOS app depends on.
// Contains no SwiftUI/UIKit code — only the state machine, models, and service
// abstractions. The iOS app target imports it.
//
// Tools version 6.0 compiles in the Swift 6 language mode, so data races are
// compile errors rather than runtime surprises.
//
// macOS is a supported platform so `swift test` works on a developer's Mac without
// needing the iOS SDK. The package also builds and tests on Linux (no Apple-only
// frameworks), which is handy for CI containers and remote agents.

import PackageDescription

let package = Package(
    name: "BlinkBreakCore",
    platforms: [
        .iOS("26.1"),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "BlinkBreakCore",
            targets: ["BlinkBreakCore"]
        )
    ],
    targets: [
        .target(
            name: "BlinkBreakCore",
            path: "Sources/BlinkBreakCore",
            // Explicit so the DEBUG-only test overrides in Constants.swift work the
            // same under `swift test` and when Xcode builds the package.
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .testTarget(
            name: "BlinkBreakCoreTests",
            dependencies: ["BlinkBreakCore"],
            path: "Tests/BlinkBreakCoreTests"
        )
    ]
)
