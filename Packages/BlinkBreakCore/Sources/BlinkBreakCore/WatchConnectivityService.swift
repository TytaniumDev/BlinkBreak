//
//  WatchConnectivityService.swift
//  BlinkBreakCore
//
//  Protocol abstraction over WCSession, plus a real implementation guarded by
//  `#if canImport(WatchConnectivity)` so the package still builds on macOS (for tests).
//
//  The iPhone is the source of truth:
//  - iPhone broadcasts state changes via `updateApplicationContext` (latest-wins).
//  - Watch forwards user commands via `sendMessage` (live request/response).
//  - On activation, the Watch reads `receivedApplicationContext` to pick up any
//    state the iPhone sent while the Watch app wasn't running.
//
//  Flutter analogue: think of this as a platform-channel wrapper you'd have one
//  implementation on iOS and a no-op on web/desktop.
//

import Foundation

// MARK: - Public value types

/// A snapshot of session state, small enough to fit in a WatchConnectivity payload.
/// Sent from iPhone to Watch via `updateApplicationContext`.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public let sessionActive: Bool
    public let currentCycleId: UUID?
    public let cycleStartedAt: Date?
    public let breakActiveStartedAt: Date?
    public let updatedAt: Date

    /// Backwards-compatible coding keys: `breakActiveStartedAt` is encoded as
    /// `"lookAwayStartedAt"` so existing Watch wire payloads decode without migration.
    enum CodingKeys: String, CodingKey {
        case sessionActive
        case currentCycleId
        case cycleStartedAt
        case breakActiveStartedAt = "lookAwayStartedAt"
        case updatedAt
    }

    public init(
        sessionActive: Bool,
        currentCycleId: UUID?,
        cycleStartedAt: Date?,
        breakActiveStartedAt: Date?,
        updatedAt: Date
    ) {
        self.sessionActive = sessionActive
        self.currentCycleId = currentCycleId
        self.cycleStartedAt = cycleStartedAt
        self.breakActiveStartedAt = breakActiveStartedAt
        self.updatedAt = updatedAt
    }
}

/// A command sent from the Watch to the iPhone via `sendMessage`.
public enum WatchCommand: String, Codable, Sendable {
    case start
    case stop
    case startBreak
}

// MARK: - Protocol

/// Abstracts WatchConnectivity so SessionController can depend on a protocol, not WCSession.
public protocol WatchConnectivityProtocol: AnyObject, Sendable {

    /// Activate the underlying WCSession. Call once at launch. No-op if already activated
    /// or if the platform doesn't support WatchConnectivity (e.g. macOS tests).
    func activate()

    /// Whether the session has been activated and is ready to send messages.
    var isActivated: Bool { get }

    /// Broadcast the given state snapshot to the paired device. Used by the iPhone only.
    /// Latest-wins: overwrites any previous snapshot that hasn't been delivered yet.
    func broadcast(_ snapshot: SessionSnapshot)

    /// Send a command to the paired device. Used by the Watch only to forward user actions.
    /// The reply handler fires with `true` if the command was accepted, `false` otherwise.
    /// Errors (e.g. other device unreachable) are reported via the error handler.
    func send(
        command: WatchCommand,
        cycleId: UUID?,
        replyHandler: @escaping (Bool) -> Void,
        errorHandler: @escaping (Error) -> Void
    )

    /// Called when a remote snapshot arrives. The iPhone rarely receives one (iPhone is
    /// source of truth). The Watch receives these to update its local UI.
    var onSnapshotReceived: ((SessionSnapshot) -> Void)? { get set }

    /// Called when a remote command arrives. The iPhone receives these from the Watch.
    var onCommandReceived: ((WatchCommand, UUID?) -> Void)? { get set }
}

// MARK: - No-op implementation (tests + macOS)

/// A `WatchConnectivityProtocol` that does nothing. Used in tests and on macOS where the
/// real WatchConnectivity framework is unavailable.
public final class NoopConnectivity: WatchConnectivityProtocol, @unchecked Sendable {

    public init() {}

    public var isActivated: Bool { true }

    public func activate() {}

    public func broadcast(_ snapshot: SessionSnapshot) {}

    public func send(
        command: WatchCommand,
        cycleId: UUID?,
        replyHandler: @escaping (Bool) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) {
        replyHandler(true)
    }

    public var onSnapshotReceived: ((SessionSnapshot) -> Void)?
    public var onCommandReceived: ((WatchCommand, UUID?) -> Void)?
}

// MARK: - Real implementation (iOS + watchOS only)

#if canImport(WatchConnectivity)
import WatchConnectivity

/// The production implementation of `WatchConnectivityProtocol`, wrapping `WCSession.default`.
/// Only compiled on iOS and watchOS; macOS tests use `NoopConnectivity`.
public final class WCSessionConnectivity: NSObject, WatchConnectivityProtocol, @unchecked Sendable {

    private let session: WCSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public var onSnapshotReceived: ((SessionSnapshot) -> Void)?
    public var onCommandReceived: ((WatchCommand, UUID?) -> Void)?

    public override init() {
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    public var isActivated: Bool {
        session?.activationState == .activated
    }

    public func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    public func broadcast(_ snapshot: SessionSnapshot) {
        guard let session, session.activationState == .activated else { return }
        guard let data = try? encoder.encode(snapshot) else { return }
        // updateApplicationContext replaces any previous pending snapshot. Perfect for
        // latest-wins state broadcasts.
        try? session.updateApplicationContext(["snapshot": data])
    }

    public func send(
        command: WatchCommand,
        cycleId: UUID?,
        replyHandler: @escaping (Bool) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) {
        guard let session, session.activationState == .activated, session.isReachable else {
            errorHandler(WatchConnectivityError.notReachable)
            return
        }
        var message: [String: Any] = ["command": command.rawValue]
        if let cycleId = cycleId {
            message["cycleId"] = cycleId.uuidString
        }
        session.sendMessage(
            message,
            replyHandler: { reply in
                let accepted = (reply["accepted"] as? Bool) ?? false
                replyHandler(accepted)
            },
            errorHandler: errorHandler
        )
    }
}

// MARK: - WCSessionDelegate conformance (real impl only)

extension WCSessionConnectivity: WCSessionDelegate {

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        // Read any application context the paired device sent while this app wasn't
        // running. Without this, a freshly-installed Watch app won't pick up the
        // iPhone's current state until the iPhone sends a NEW snapshot.
        // Dispatch to main so wireUpConnectivity() (which sets onSnapshotReceived)
        // has completed before we fire the callback.
        let context = session.receivedApplicationContext
        guard let data = context["snapshot"] as? Data,
              let snapshot = try? decoder.decode(SessionSnapshot.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshotReceived?(snapshot)
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so iPhone-side state broadcasts keep working after a Watch switch.
        session.activate()
    }
    #endif

    public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        guard let snapshot = try? decoder.decode(SessionSnapshot.self, from: data) else { return }
        onSnapshotReceived?(snapshot)
    }

    public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let raw = message["command"] as? String,
              let command = WatchCommand(rawValue: raw) else {
            replyHandler(["accepted": false])
            return
        }
        let cycleId = (message["cycleId"] as? String).flatMap(UUID.init(uuidString:))
        onCommandReceived?(command, cycleId)
        replyHandler(["accepted": true])
    }
}

public enum WatchConnectivityError: Error {
    case notReachable
}
#endif
