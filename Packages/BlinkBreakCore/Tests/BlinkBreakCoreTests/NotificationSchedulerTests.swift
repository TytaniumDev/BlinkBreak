//
//  NotificationSchedulerTests.swift
//  BlinkBreakCoreTests
//
//  Tests for CascadeBuilder — the pure function that builds the six-notification
//  cascade. The real UN-backed scheduler is a thin wrapper and not meaningfully
//  testable without the full framework, so we only test the builder.
//

import Testing
@testable import BlinkBreakCore

@Suite("CascadeBuilder")
struct NotificationSchedulerTests {

    let cycleId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("buildBreakCascade produces 1 primary + 5 nudges = 6 notifications")
    func cascadeCount() {
        let cascade = CascadeBuilder.buildBreakCascade(cycleId: cycleId, cycleStartedAt: startedAt)
        #expect(cascade.count == 1 + BlinkBreakConstants.nudgeCount)
    }

    @Test("primary cascade notification fires at cycleStartedAt + 20 min")
    func primaryFireTime() {
        let cascade = CascadeBuilder.buildBreakCascade(cycleId: cycleId, cycleStartedAt: startedAt)
        let primary = cascade[0]
        #expect(primary.identifier == BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString)
        #expect(primary.fireDate == startedAt.addingTimeInterval(BlinkBreakConstants.breakInterval))
    }

    @Test("nudges fire at 5-second intervals after the primary")
    func nudgeFireTimes() {
        let cascade = CascadeBuilder.buildBreakCascade(cycleId: cycleId, cycleStartedAt: startedAt)
        let primaryFireDate = startedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)

        for n in 1...BlinkBreakConstants.nudgeCount {
            let nudge = cascade[n]
            let expected = primaryFireDate.addingTimeInterval(BlinkBreakConstants.nudgeInterval * Double(n))
            #expect(nudge.fireDate == expected, "nudge \(n) fire date")
            #expect(nudge.identifier.hasPrefix(BlinkBreakConstants.breakNudgeIdPrefix))
            #expect(nudge.identifier.hasSuffix(".\(n)"))
        }
    }

    @Test("all cascade notifications share the cycle UUID as thread identifier")
    func sharedThreadId() {
        let cascade = CascadeBuilder.buildBreakCascade(cycleId: cycleId, cycleStartedAt: startedAt)
        let ids = Set(cascade.map(\.threadIdentifier))
        #expect(ids == [cycleId.uuidString])
    }

    @Test("all cascade notifications are marked time-sensitive")
    func allTimeSensitive() {
        let cascade = CascadeBuilder.buildBreakCascade(cycleId: cycleId, cycleStartedAt: startedAt)
        let result = cascade.allSatisfy { $0.isTimeSensitive }
        #expect(result)
    }

    @Test("all cascade notifications reference the break category")
    func allInBreakCategory() {
        let cascade = CascadeBuilder.buildBreakCascade(cycleId: cycleId, cycleStartedAt: startedAt)
        let result = cascade.allSatisfy { $0.categoryIdentifier == BlinkBreakConstants.breakCategoryId }
        #expect(result)
    }

    @Test("buildDoneNotification fires at lookAwayStartedAt + 20 s and is not time-sensitive")
    func doneNotification() {
        let lookAwayStart = Date(timeIntervalSince1970: 2_000_000_000)
        let done = CascadeBuilder.buildDoneNotification(cycleId: cycleId, lookAwayStartedAt: lookAwayStart)

        #expect(done.identifier == BlinkBreakConstants.doneIdPrefix + cycleId.uuidString)
        #expect(done.fireDate == lookAwayStart.addingTimeInterval(BlinkBreakConstants.lookAwayDuration))
        #expect(done.isTimeSensitive == false)
        #expect(done.categoryIdentifier == nil)
    }

    @Test("identifiers(for:) enumerates every notification tied to a cycle")
    func allIdentifiersForCycle() {
        let ids = CascadeBuilder.identifiers(for: cycleId)

        #expect(ids.count == 2 + BlinkBreakConstants.nudgeCount)
        #expect(ids.contains(BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString))
        #expect(ids.contains(BlinkBreakConstants.doneIdPrefix + cycleId.uuidString))
        for n in 1...BlinkBreakConstants.nudgeCount {
            #expect(ids.contains("\(BlinkBreakConstants.breakNudgeIdPrefix)\(cycleId.uuidString).\(n)"))
        }
    }

    @Test("ScheduledNotification carries an optional soundName, defaulting to nil")
    func soundNameDefaultsToNil() {
        let notification = ScheduledNotification(
            identifier: "test",
            title: "t", body: "b",
            fireDate: startedAt,
            isTimeSensitive: true,
            threadIdentifier: "thread",
            categoryIdentifier: nil
        )
        #expect(notification.soundName == nil)
    }

    @Test("ScheduledNotification stores a custom soundName when provided")
    func soundNameStoresCustom() {
        let notification = ScheduledNotification(
            identifier: "test",
            title: "t", body: "b",
            fireDate: startedAt,
            isTimeSensitive: true,
            threadIdentifier: "thread",
            categoryIdentifier: nil,
            soundName: "break-alarm.caf"
        )
        #expect(notification.soundName == "break-alarm.caf")
    }
}
