// swift-tools-version: 5.9
//
// BlinkBreakCore — all business logic for the BlinkBreak app.
//
// Flutter analogue: a plain Dart package in `packages/` that the iOS app depends on.
// Contains no SwiftUI/UIKit code — only the state machine, models, and service
// abstractions. The iOS app target imports it.
//
// macOS is a supported platform so `swift test` works on a developer's Mac without
// needing the iOS SDK.

import PackageDescription

let package = Package(
    name: "BlinkBreakCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
            path: "Sources/BlinkBreakCore"
        ),
        .testTarget(
            name: "BlinkBreakCoreTests",
            dependencies: ["BlinkBreakCore"],
            path: "Tests/BlinkBreakCoreTests"
        )
    ]
)
