//
//  MockWatchConnectivity.swift
//  BlinkBreakCoreTests
//
//  A test-only WatchConnectivityProtocol that records broadcasts and lets tests
//  simulate incoming commands/snapshots.
//

@testable import BlinkBreakCore

final class MockWatchConnectivity: WatchConnectivityProtocol, @unchecked Sendable {

    // MARK: - State

    private let lock = NSLock()
    private(set) var broadcasts: [SessionSnapshot] = []
    private(set) var activateCount: Int = 0
    var isActivated: Bool = true

    var onSnapshotReceived: ((SessionSnapshot) -> Void)?
    var onCommandReceived: ((WatchCommand, UUID?) -> Void)?

    // MARK: - Protocol

    func activate() {
        lock.withLock {
            activateCount += 1
        }
    }

    func broadcast(_ snapshot: SessionSnapshot) {
        lock.withLock {
            broadcasts.append(snapshot)
        }
    }

    func send(
        command: WatchCommand,
        cycleId: UUID?,
        replyHandler: @escaping (Bool) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) {
        replyHandler(true)
    }

    // MARK: - Test helpers

    var lastBroadcast: SessionSnapshot? {
        lock.withLock {
            return broadcasts.last
        }
    }

    func reset() {
        lock.withLock {
            broadcasts.removeAll()
            activateCount = 0
        }
    }
}
