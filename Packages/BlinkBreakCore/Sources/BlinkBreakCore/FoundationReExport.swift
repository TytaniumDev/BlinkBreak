//
//  FoundationReExport.swift
//  BlinkBreakCore
//
//  Re-exports Foundation through BlinkBreakCore so consumers (especially test files)
//  don't need to `import Foundation` themselves. This is needed to work around a
//  cross-import issue in the Command Line Tools swift toolchain: when a file imports
//  both `Foundation` and the Swift Testing framework (`import Testing`), the compiler
//  tries to auto-import `_Testing_Foundation`, which ships in CLT without a
//  swiftmodule file — causing "no such module '_Testing_Foundation'" errors.
//
//  By re-exporting Foundation from inside BlinkBreakCore via `@_exported`, test files
//  can `@testable import BlinkBreakCore` alone (no explicit `import Foundation`) and
//  still use `Date`, `UUID`, `NSLock`, etc. That keeps the cross-import from firing.
//

@_exported import Foundation
