//
//  DiagnosticCollectorTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the diagnostic report assembly logic.
//

import Testing
@testable import BlinkBreakCore

@Suite("DiagnosticCollector")
struct DiagnosticCollectorTests {

    private static let testDeviceInfo = DeviceInfo(
        iosVersion: "17.4",
        deviceModel: "iPhone15,2",
        appVersion: "0.1.0",
        buildNumber: "42",
        isTestFlight: true
    )

    @Test("collect assembles a complete report from all sources")
    func collectAssemblesReport() async {
        let scheduler = MockNotificationScheduler()
        scheduler.schedule(ScheduledNotification(
            identifier: "break.primary.test",
            title: "T",
            body: "B",
            fireDate: Date(timeIntervalSince1970: 1_700_001_200),
            isTimeSensitive: true,
            threadIdentifier: "thread",
            categoryIdentifier: nil
        ))

        let persistence = InMemoryPersistence()
        let record = SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            breakActiveStartedAt: nil,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        persistence.save(record)

        let logBuffer = LogBuffer(capacity: 10)
        logBuffer.log(.info, "test log entry")

        let collector = DiagnosticCollector(
            scheduler: scheduler,
            persistence: persistence,
            logBuffer: logBuffer,
            sessionState: .running(cycleStartedAt: Date(timeIntervalSince1970: 1_700_000_000))
        )

        let report = await collector.collect(deviceInfo: Self.testDeviceInfo)

        #expect(report.deviceInfo.iosVersion == "17.4")
        #expect(report.deviceInfo.isTestFlight == true)
        #expect(report.sessionState == "running")
        #expect(report.sessionRecord.sessionActive == true)
        #expect(report.pendingNotifications.count == 1)
        #expect(report.pendingNotifications[0].identifier == "break.primary.test")
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
            scheduler: MockNotificationScheduler(),
            persistence: persistence,
            logBuffer: LogBuffer(capacity: 10),
            sessionState: .idle
        )

        let report = await collector.collect(deviceInfo: Self.testDeviceInfo)
        #expect(report.weeklySchedule.isEnabled == true)
    }
}
