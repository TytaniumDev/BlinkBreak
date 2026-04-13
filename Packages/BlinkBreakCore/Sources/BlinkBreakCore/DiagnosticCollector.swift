//
//  DiagnosticCollector.swift
//  BlinkBreakCore
//
//  Gathers diagnostic data from all sources into a DiagnosticReport. Pure function:
//  dependencies in, report out. The iOS app target injects the real scheduler,
//  persistence, and device info; tests inject mocks.
//
//  Flutter analogue: a service class that reads from multiple repositories and
//  assembles a diagnostics payload for upload.
//

import Foundation

/// Assembles a `DiagnosticReport` from the current app state, persistence, pending
/// notifications, Watch connectivity status, and log buffer.
public struct DiagnosticCollector: Sendable {

    private let scheduler: NotificationSchedulerProtocol
    private let persistence: PersistenceProtocol
    private let logBuffer: LogBuffer
    private let sessionState: SessionState
    private let watchIsPaired: Bool
    private let watchIsReachable: Bool

    public init(
        scheduler: NotificationSchedulerProtocol,
        persistence: PersistenceProtocol,
        logBuffer: LogBuffer,
        sessionState: SessionState,
        watchIsPaired: Bool,
        watchIsReachable: Bool
    ) {
        self.scheduler = scheduler
        self.persistence = persistence
        self.logBuffer = logBuffer
        self.sessionState = sessionState
        self.watchIsPaired = watchIsPaired
        self.watchIsReachable = watchIsReachable
    }

    /// Collect all diagnostic data into a report. Async because fetching pending
    /// notifications is async.
    public func collect(deviceInfo: DeviceInfo) async -> DiagnosticReport {
        let record = persistence.load()
        let schedule = persistence.loadSchedule() ?? .empty
        let pending = await scheduler.pendingRequests()
        let logs = logBuffer.drain()

        return DiagnosticReport(
            timestamp: Date(),
            deviceInfo: deviceInfo,
            sessionState: sessionState.description,
            sessionRecord: record,
            weeklySchedule: schedule,
            pendingNotifications: pending,
            watchIsPaired: watchIsPaired,
            watchIsReachable: watchIsReachable,
            watchLastSyncedAt: record.lastUpdatedAt,
            logEntries: logs
        )
    }
}
