//
//  LogBuffer.swift
//  BlinkBreakCore
//
//  Thread-safe in-memory ring buffer for diagnostic logs. Code throughout BlinkBreakCore
//  writes short messages here; the bug report collector drains the buffer when submitting.
//
//  Flutter analogue: similar to a bounded List<LogEntry> behind a mutex, read by a
//  diagnostics screen or crash reporter.
//

import Foundation

/// Severity level for a log entry.
public enum LogLevel: String, Codable, Sendable {
    case debug, info, warning, error
}

/// A single log entry with a timestamp, severity, and developer-written message.
public struct LogEntry: Codable, Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
}

/// Thread-safe ring buffer that holds up to `capacity` log entries. When full, the oldest
/// entry is evicted to make room for the new one.
///
/// Usage:
/// ```swift
/// LogBuffer.shared.log(.info, "reconcile: rebuilt state from persisted record")
/// ```
public final class LogBuffer: @unchecked Sendable {

    /// Shared instance used throughout BlinkBreakCore. Capacity of 500 entries.
    public static let shared = LogBuffer(capacity: 500)

    private let lock = NSLock()
    private var storage: [LogEntry]
    private let capacity: Int

    /// Create a buffer with the given maximum capacity. Use `LogBuffer.shared` in production;
    /// create isolated instances in tests.
    public init(capacity: Int) {
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    /// Append a log entry at the current time. If the buffer is full, the oldest entry
    /// is evicted.
    public func log(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        lock.lock()
        defer { lock.unlock() }
        if storage.count >= capacity {
            storage.removeFirst()
        }
        storage.append(entry)
    }

    /// Return all buffered entries in insertion order. Does not clear the buffer.
    public func drain() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
