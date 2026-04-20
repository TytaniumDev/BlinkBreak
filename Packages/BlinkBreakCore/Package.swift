// swift-tools-version: 6.2
//
// BlinkBreakCore — all business logic for the BlinkBreak iOS app.
//
// Flutter analogue: a plain Dart package in `packages/` that the iOS app depends on.
// Contains no SwiftUI/UIKit code — only the state machine, models, and service
// abstractions. The iOS app target imports this package and provides the SwiftUI
// + AlarmKit layer on top.
//
// We declare macOS as a supported platform so `swift test` works on a developer's Mac
// without needing the iOS SDK.

import PackageDescription

let package = Package(
    name: "BlinkBreakCore",
    // Minimum platforms. macOS is included so the package can be tested on a dev Mac
    // without Xcode.app. The package itself is platform-agnostic; the iOS app target
    // that imports it sets its own iOS 26.1 deployment floor in project.yml.
    platforms: [
        .iOS(.v26),
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
    ],
    swiftLanguageModes: [.v5]
)
