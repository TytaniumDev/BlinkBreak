//
//  MeetingIntegrationTests.swift
//  BlinkBreakCoreTests
//
//  SessionController with "skip breaks during meetings": breaks booked into a
//  meeting move to the next free 20-minute slot, both when they're booked and
//  when the calendar or the setting changes afterwards.
//

import Testing
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — meeting skipping")
struct MeetingIntegrationTests {

    typealias Fixture = SessionControllerFixture
    let interval = BlinkBreakConstants.breakInterval
    let enabled = MeetingSettings(isEnabled: true)

    // MARK: - Booking

    @Test("setting off → the break is booked inside the meeting as usual")
    func offIgnoresMeetings() async {
        let f = Fixture()
        f.calendarEvents.addEvent(meeting((10, 15), (10, 45)))

        await f.startRunning()

        #expect(f.alarms.lastScheduled?.fireDate == monday(10, 20))
    }

    @Test("start → the first break skips a meeting")
    func startSkipsMeeting() async {
        let f = Fixture(meetingSettings: enabled)
        f.calendarEvents.addEvent(meeting((10, 15), (10, 45)))

        await f.startRunning()

        #expect(f.alarms.lastScheduled?.fireDate == monday(11))
        #expect(f.controller.state == .running(breakAt: monday(11)))
    }

    @Test("next cycle → the next break skips a meeting")
    func nextCycleSkipsMeeting() async {
        let f = Fixture(meetingSettings: enabled)
        f.calendarEvents.addEvent(meeting((10, 30), (11, 0)))
        let first = await f.startRunning()
        #expect(f.alarms.lastScheduled?.fireDate == monday(10, 20))

        f.advance(by: interval)
        await f.controller.respond(to: .skip, alarmId: first)

        // 10:40 is in the meeting; 11:00 is when it ends.
        #expect(f.alarms.lastScheduled?.fireDate == monday(11))
    }

    @Test("events that don't count as meetings are ignored")
    func nonMeetingsIgnored() async {
        let f = Fixture(meetingSettings: MeetingSettings(isEnabled: true, excludedCalendarIds: ["family"]))
        f.calendarEvents.addEvent(meeting((10, 15), (10, 45), calendarId: "family"))
        f.calendarEvents.addEvent(meeting((10, 15), (10, 45), isBusy: false))
        f.calendarEvents.addEvent(meeting((10, 15), (10, 45), isDeclined: true))
        f.calendarEvents.addEvent(meeting((0, 0), (23, 59), isAllDay: true))

        await f.startRunning()

        #expect(f.alarms.lastScheduled?.fireDate == monday(10, 20))
    }

    @Test("calendar access revoked → breaks are booked as usual")
    func accessRevoked() async {
        let f = Fixture(meetingSettings: enabled)
        f.calendarEvents.addEvent(meeting((10, 15), (10, 45)))
        f.calendarEvents.stubAccess(.denied)

        await f.startRunning()

        #expect(f.alarms.lastScheduled?.fireDate == monday(10, 20))
    }

    // MARK: - Changes after booking

    @Test("a meeting added after booking moves the booked break")
    func calendarChangeMovesBreak() async {
        let f = Fixture(meetingSettings: enabled)
        let first = await f.startRunning()

        f.calendarEvents.addEvent(meeting((10, 15), (10, 45)))
        f.calendarEvents.simulateChange()
        await f.settle()

        #expect(f.alarms.cancelled.contains(first))
        #expect(f.alarms.lastScheduled?.fireDate == monday(11))
        #expect(f.record.alarmFiresAt == monday(11))
        #expect(f.alarms.systemAlarmIds == [f.record.alarmId!])
    }

    @Test("reconcile picks up a meeting added while the app was closed")
    func reconcileMovesBreak() async {
        let f = Fixture(meetingSettings: enabled)
        await f.startRunning()
        f.calendarEvents.addEvent(meeting((10, 15), (10, 45)))

        await f.controller.reconcile()

        #expect(f.record.alarmFiresAt == monday(11))
    }

    @Test("a ringing break alarm is left alone")
    func ringingUntouched() async {
        let f = Fixture(meetingSettings: enabled)
        let first = await f.startRunning()
        f.advance(by: interval)
        f.alarms.simulateAlerting(first)
        await f.settle()

        f.calendarEvents.addEvent(meeting((10, 15), (10, 45)))
        f.calendarEvents.simulateChange()
        await f.settle()

        #expect(f.record.alarmId == first)
        #expect(!f.alarms.cancelled.contains(first))
    }

    @Test("rest of a manual session's window is meetings → the session stops")
    func windowEndsDuringMeeting() async {
        // Manual start at 16:30 inside Mon 9–5: the session stops at 17:00.
        let f = Fixture(now: monday(16, 30), schedule: .workweekOn, meetingSettings: enabled)
        await f.startRunning()
        #expect(f.record.alarmFiresAt == monday(16, 50))

        f.calendarEvents.addEvent(meeting((16, 45), (17, 30)))
        f.calendarEvents.simulateChange()
        await f.settle()

        #expect(f.controller.state == .idle)
        #expect(f.record.phase != .running)
        #expect(!f.alarms.scheduled.contains { $0.fireDate == monday(17, 30) })
    }

    // MARK: - Settings

    @Test("turning it on asks for access and moves the booked break")
    func enableMovesBreak() async {
        let f = Fixture()
        f.calendarEvents.stubAccess(.notDetermined, grantsOnRequest: true)
        f.calendarEvents.addEvent(meeting((10, 15), (10, 45)))
        await f.startRunning()

        await f.controller.updateMeetingSettings(enabled)

        #expect(f.calendarEvents.requestCount == 1)
        #expect(f.controller.meetingSettings == enabled)
        #expect(f.persistence.loadMeetingSettings() == enabled)
        #expect(f.controller.calendarAccessDenied == false)
        #expect(f.record.alarmFiresAt == monday(11))
    }

    @Test("access refused → stays off and reports it")
    func enableDenied() async {
        let f = Fixture()
        f.calendarEvents.stubAccess(.notDetermined, grantsOnRequest: false)
        f.calendarEvents.addEvent(meeting((10, 15), (10, 45)))
        await f.startRunning()

        await f.controller.updateMeetingSettings(enabled)

        #expect(f.controller.meetingSettings.isEnabled == false)
        #expect(f.persistence.loadMeetingSettings().isEnabled == false)
        #expect(f.controller.calendarAccessDenied)
        #expect(f.record.alarmFiresAt == monday(10, 20))
    }

    @Test("excluding the meeting's calendar doesn't move a booked break earlier")
    func excludingNeverMovesEarlier() async {
        let f = Fixture(meetingSettings: enabled)
        f.calendarEvents.addEvent(meeting((10, 15), (10, 45), calendarId: "family"))
        await f.startRunning()
        #expect(f.record.alarmFiresAt == monday(11))

        await f.controller.updateMeetingSettings(MeetingSettings(isEnabled: true, excludedCalendarIds: ["family"]))

        #expect(f.record.alarmFiresAt == monday(11))
        #expect(f.controller.meetingSettings.excludedCalendarIds == ["family"])
    }

    @Test("reconcile reports calendar access revoked in Settings")
    func reconcileReportsDenied() async {
        let f = Fixture(meetingSettings: enabled)
        f.calendarEvents.stubAccess(.denied)

        await f.controller.reconcile()

        #expect(f.controller.calendarAccessDenied)
    }

    @Test("access granted in Settings after a refusal clears the hint on reconcile")
    func reconcileClearsDenied() async {
        let f = Fixture()
        f.calendarEvents.stubAccess(.notDetermined, grantsOnRequest: false)
        await f.controller.updateMeetingSettings(enabled)
        #expect(f.controller.calendarAccessDenied)

        f.calendarEvents.stubAccess(.authorized)
        await f.controller.reconcile()

        #expect(f.controller.calendarAccessDenied == false)
    }

    @Test("availableCalendars lists the provider's calendars")
    func calendarsListed() async {
        let f = Fixture()
        let work = CalendarInfo(id: "work", title: "Work", accountTitle: "iCloud")
        f.calendarEvents.setCalendars([work])

        #expect(await f.controller.availableCalendars() == [work])
    }
}
