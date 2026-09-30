//
//  AppLogger.swift
//  BlinkBreakCore
//
//  Tiny logging facade. Messages go to Apple's unified log (Console.app,
//  `log show`) and to an optional sink — the app installs one that mirrors
//  messages into Sentry breadcrumbs so bug reports carry recent history.
//
//  Flutter analogue: a `package:logging` Logger with a single onRecord listener.
//

import Foundation
import Synchronization
#if canImport(os)
import os
#endif

public enum LogLevel: String, Sendable {
    case debug, info, warning, error
}

public final class AppLogger: Sendable {

    public typealias Sink = @Sendable (LogLevel, String) -> Void

    public static let shared = AppLogger()

    private let sink = Mutex<Sink?>(nil)
    #if canImport(os)
    private let osLogger = Logger(subsystem: "com.tytaniumdev.BlinkBreak", category: "BlinkBreak")
    #endif

    public init() {}

    /// Replace the sink. Pass nil to remove it.
    public func setSink(_ newSink: Sink?) {
        sink.withLock { $0 = newSink }
    }

    public func log(_ level: LogLevel, _ message: String) {
        #if canImport(os)
        switch level {
        case .debug: osLogger.debug("\(message, privacy: .public)")
        case .info: osLogger.info("\(message, privacy: .public)")
        case .warning: osLogger.warning("\(message, privacy: .public)")
        case .error: osLogger.error("\(message, privacy: .public)")
        }
        #endif
        sink.withLock { $0 }?(level, message)
    }
}
