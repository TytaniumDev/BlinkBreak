//
//  NotificationSchedulerTests.swift
//  BlinkBreakCoreTests
//
//  Tests for CascadeBuilder — the pure functions that build the break notification
//  and the done notification for a cycle. The real UN-backed scheduler is a thin
//  wrapper and not meaningfully testable without the full framework, so we only
//  test the builders.
//

import Testing
@testable import BlinkBreakCore

@Suite("CascadeBuilder")
struct NotificationSchedulerTests {

    let cycleId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("buildDoneNotification fires at lookAwayStartedAt + 20 s and is not time-sensitive")
    func doneNotification() {
        let lookAwayStart = Date(timeIntervalSince1970: 2_000_000_000)
        let done = CascadeBuilder.buildDoneNotification(cycleId: cycleId, lookAwayStartedAt: lookAwayStart)

        #expect(done.identifier == BlinkBreakConstants.doneIdPrefix + cycleId.uuidString)
        #expect(done.fireDate == lookAwayStart.addingTimeInterval(BlinkBreakConstants.lookAwayDuration))
        #expect(done.isTimeSensitive == false)
        #expect(done.categoryIdentifier == nil)
    }

    @Test("identifiers(for:) returns the break + done identifiers for a cycle")
    func allIdentifiersForCycle() {
        let ids = CascadeBuilder.identifiers(for: cycleId)
        #expect(ids.count == 2)
        #expect(ids.contains(BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString))
        #expect(ids.contains(BlinkBreakConstants.doneIdPrefix + cycleId.uuidString))
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

    @Test("buildBreakNotification produces exactly one notification with the right identifier")
    func buildBreakNotificationIsSingle() {
        let n = CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: startedAt)
        #expect(n.identifier == BlinkBreakConstants.breakPrimaryIdPrefix + cycleId.uuidString)
    }

    @Test("buildBreakNotification fires at cycleStartedAt + breakInterval")
    func buildBreakNotificationFireDate() {
        let n = CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: startedAt)
        #expect(n.fireDate == startedAt.addingTimeInterval(BlinkBreakConstants.breakInterval))
    }

    @Test("buildBreakNotification is time-sensitive with the break category")
    func buildBreakNotificationFlags() {
        let n = CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: startedAt)
        #expect(n.isTimeSensitive)
        #expect(n.categoryIdentifier == BlinkBreakConstants.breakCategoryId)
        #expect(n.threadIdentifier == cycleId.uuidString)
    }

    @Test("buildBreakNotification uses the break-alarm.caf custom sound")
    func buildBreakNotificationSoundName() {
        let n = CascadeBuilder.buildBreakNotification(cycleId: cycleId, cycleStartedAt: startedAt)
        #expect(n.soundName == "break-alarm.caf")
    }
}
