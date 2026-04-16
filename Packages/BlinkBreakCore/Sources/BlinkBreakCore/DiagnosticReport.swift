//
//  DiagnosticReport.swift
//  BlinkBreakCore
//
//  Value types for the bug report payload. All fields are Codable and PII-free.
//  The iOS app target constructs DeviceInfo from UIDevice/Bundle.main and passes it
//  to DiagnosticCollector; Core never imports UIKit.
//
//  Flutter analogue: a data class that a diagnostics service serializes to JSON
//  before sending to a crash/bug reporting backend.
//

import Foundation

/// Device and app metadata. Constructed by the iOS app target (which has access to UIDevice
/// and Bundle.main) and passed into DiagnosticCollector. Keeps BlinkBreakCore free of UI
/// framework imports.
public struct DeviceInfo: Codable, Sendable {
    public let iosVersion: String
    public let deviceModel: String
    public let appVersion: String
    public let buildNumber: String
    public let isTestFlight: Bool

    public init(
        iosVersion: String,
        deviceModel: String,
        appVersion: String,
        buildNumber: String,
        isTestFlight: Bool
    ) {
        self.iosVersion = iosVersion
        self.deviceModel = deviceModel
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.isTestFlight = isTestFlight
    }
}

/// Identifier and fire date for a pending notification. Content/body is deliberately
/// excluded to keep the report PII-free.
public struct PendingNotificationInfo: Codable, Sendable {
    public let identifier: String
    public let fireDate: Date?

    public init(identifier: String, fireDate: Date?) {
        self.identifier = identifier
        self.fireDate = fireDate
    }
}

/// The complete diagnostic payload attached to a bug report GitHub issue.
/// Every field is a value type, Codable, and contains no PII.
public struct DiagnosticReport: Codable, Sendable {
    public let timestamp: Date
    public let deviceInfo: DeviceInfo
    public let sessionState: String
    public let sessionRecord: SessionRecord
    public let weeklySchedule: WeeklySchedule
    public let pendingNotifications: [PendingNotificationInfo]
    public let logEntries: [LogEntry]

    public init(
        timestamp: Date,
        deviceInfo: DeviceInfo,
        sessionState: String,
        sessionRecord: SessionRecord,
        weeklySchedule: WeeklySchedule,
        pendingNotifications: [PendingNotificationInfo],
        logEntries: [LogEntry]
    ) {
        self.timestamp = timestamp
        self.deviceInfo = deviceInfo
        self.sessionState = sessionState
        self.sessionRecord = sessionRecord
        self.weeklySchedule = weeklySchedule
        self.pendingNotifications = pendingNotifications
        self.logEntries = logEntries
    }
}
