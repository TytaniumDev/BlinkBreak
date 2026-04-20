//
//  DiagnosticCollectorTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the diagnostic report assembly logic.
//

@testable import BlinkBreakCore
import Foundation
import Testing

@Suite("DiagnosticCollector")
struct DiagnosticCollectorTests {

    private static let testDeviceInfo = DeviceInfo(
        iosVersion: "17.4",
        deviceModel: "iPhone15,2",
        appVersion: "0.1.0",
        buildNumber: "42",
        isTestFlight: true
    )

    @Test("collect assembles a report from persistence + log buffer + device info")
    func collectAssemblesReport() async {
        let persistence = InMemoryPersistence()
        let record = SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            breakActiveStartedAt: nil
        )
        persistence.save(record)

        let logBuffer = LogBuffer(capacity: 10)
        logBuffer.log(.info, "test log entry")

        let collector = DiagnosticCollector(
            persistence: persistence,
            logBuffer: logBuffer,
            sessionState: .running(cycleStartedAt: Date(timeIntervalSince1970: 1_700_000_000))
        )

        let report = await collector.collect(deviceInfo: Self.testDeviceInfo)

        #expect(report.deviceInfo.iosVersion == "17.4")
        #expect(report.deviceInfo.isTestFlight == true)
        #expect(report.sessionState == "running")
        #expect(report.sessionRecord.sessionActive == true)
        #expect(report.logEntries.count == 1)
        #expect(report.logEntries[0].message == "test log entry")
    }

    @Test("collect includes weekly schedule from persistence")
    func collectIncludesSchedule() async {
        let persistence = InMemoryPersistence()
        var schedule = WeeklySchedule.empty
        schedule.isEnabled = true
        persistence.saveSchedule(schedule)

        let collector = DiagnosticCollector(
            persistence: persistence,
            logBuffer: LogBuffer(capacity: 10),
            sessionState: .idle
        )

        let report = await collector.collect(deviceInfo: Self.testDeviceInfo)
        #expect(report.weeklySchedule.isEnabled == true)
    }
}
