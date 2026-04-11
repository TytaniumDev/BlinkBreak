// swift-tools-version: 5.9
//
// BlinkBreakCore — all business logic for the BlinkBreak app (iOS + watchOS).
//
// Flutter analogue: this is the equivalent of a plain Dart package in `packages/` that
// both your iOS app and watchOS app depend on. It contains no SwiftUI/UIKit/WatchKit code,
// only the state machine, models, and service abstractions. Both app targets import it.
//
// We declare macOS as a supported platform so `swift test` works on a developer's Mac
// without needing the iOS SDK — the concrete WatchConnectivity implementation is guarded
// with `#if canImport(WatchConnectivity)` so it's only compiled on iOS/watchOS.

import PackageDescription

let package = Package(
    name: "BlinkBreakCore",
    // Minimum platforms. macOS is included so the package can be tested on a dev Mac
    // without Xcode.app; the real app targets that import this package are iOS 17+ / watchOS 10+.
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
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
