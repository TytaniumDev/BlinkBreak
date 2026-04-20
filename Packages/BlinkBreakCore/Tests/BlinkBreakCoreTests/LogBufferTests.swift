//
//  LogBufferTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the in-memory log ring buffer used by bug reports.
//

@testable import BlinkBreakCore
import Testing

@Suite("LogBuffer")
struct LogBufferTests {

    @Test("log appends entries with correct level and message")
    func logAppendsEntries() {
        let buffer = LogBuffer(capacity: 10)
        buffer.log(.info, "hello")
        buffer.log(.error, "oops")

        let entries = buffer.snapshot()
        #expect(entries.count == 2)
        #expect(entries[0].level == .info)
        #expect(entries[0].message == "hello")
        #expect(entries[1].level == .error)
        #expect(entries[1].message == "oops")
    }

    @Test("snapshot returns entries in insertion order with timestamps")
    func snapshotReturnsInOrder() {
        let buffer = LogBuffer(capacity: 10)
        buffer.log(.debug, "first")
        buffer.log(.warning, "second")

        let entries = buffer.snapshot()
        #expect(entries[0].timestamp <= entries[1].timestamp)
    }

    @Test("oldest entries evict when capacity is exceeded")
    func evictsOldestWhenFull() {
        let buffer = LogBuffer(capacity: 3)
        buffer.log(.info, "a")
        buffer.log(.info, "b")
        buffer.log(.info, "c")
        buffer.log(.info, "d")

        let entries = buffer.snapshot()
        #expect(entries.count == 3)
        #expect(entries[0].message == "b")
        #expect(entries[1].message == "c")
        #expect(entries[2].message == "d")
    }

    @Test("snapshot does not clear the buffer")
    func snapshotDoesNotClear() {
        let buffer = LogBuffer(capacity: 10)
        buffer.log(.info, "persistent")

        _ = buffer.snapshot()
        let entries = buffer.snapshot()
        #expect(entries.count == 1)
        #expect(entries[0].message == "persistent")
    }

    @Test("concurrent writes do not crash")
    func threadSafety() async {
        let buffer = LogBuffer(capacity: 100)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    buffer.log(.info, "msg-\(i)")
                }
            }
        }
        let entries = buffer.snapshot()
        #expect(entries.count == 100)
    }
}
