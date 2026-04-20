//
//  DiagnosticCollector.swift
//  BlinkBreakCore
//
//  Gathers diagnostic data from all sources into a DiagnosticReport. Pure function:
//  dependencies in, report out. The iOS app target injects persistence + log buffer
//  + device info; tests inject mocks.
//
//  Flutter analogue: a service class that reads from multiple repositories and
//  assembles a diagnostics payload for upload.
//

import Foundation

/// Assembles a `DiagnosticReport` from the current app state, persistence, and log buffer.
public struct DiagnosticCollector: Sendable {

    private let persistence: PersistenceProtocol
    private let logBuffer: LogBuffer
    private let sessionState: SessionState

    public init(
        persistence: PersistenceProtocol,
        logBuffer: LogBuffer,
        sessionState: SessionState
    ) {
        self.persistence = persistence
        self.logBuffer = logBuffer
        self.sessionState = sessionState
    }

    /// Collect all diagnostic data into a report.
    public func collect(deviceInfo: DeviceInfo) async -> DiagnosticReport {
        let record = persistence.load()
        let schedule = persistence.loadSchedule() ?? .empty
        let logs = logBuffer.snapshot()

        return DiagnosticReport(
            timestamp: Date(),
            deviceInfo: deviceInfo,
            sessionState: sessionState.description,
            sessionRecord: record,
            weeklySchedule: schedule,
            logEntries: logs
        )
    }
}
