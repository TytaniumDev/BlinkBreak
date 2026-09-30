//
//  InfrastructureTests.swift
//  BlinkBreakCoreTests
//
//  SerialTaskQueue ordering and AppLogger sink delivery.
//

import Testing
import Synchronization
@testable import BlinkBreakCore

@MainActor
@Suite("SerialTaskQueue")
struct SerialTaskQueueTests {

    @Test("operations run one at a time in submission order, even across awaits")
    func ordering() async {
        let queue = SerialTaskQueue()
        var log: [String] = []

        queue.enqueue {
            log.append("a-start")
            await Task.yield()
            await Task.yield()
            log.append("a-end")
        }
        queue.enqueue { log.append("b") }
        await queue.run { log.append("c") }

        #expect(log == ["a-start", "a-end", "b", "c"])
    }
}

@Suite("AppLogger")
struct AppLoggerTests {

    @Test("messages reach the sink until it's removed")
    func sink() {
        let logger = AppLogger()
        let received = Mutex<[String]>([])
        logger.setSink { level, message in
            received.withLock { $0.append("\(level.rawValue): \(message)") }
        }

        logger.log(.info, "hello")
        logger.setSink(nil)
        logger.log(.error, "dropped")

        #expect(received.withLock { $0 } == ["info: hello"])
    }
}
