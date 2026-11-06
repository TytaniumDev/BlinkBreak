//
//  MeetingSkipTests.swift
//  BlinkBreakCoreTests
//
//  The pure pieces of meeting skipping: which events count as meetings, and
//  which 20-minute slot a break lands on once meetings are skipped.
//

import Testing
@testable import BlinkBreakCore

@Suite("Meeting skipping — slot math")
struct MeetingSkipSlotTests {

    let interval: TimeInterval = 20 * 60

    func slot(_ fire: Date, _ meetings: [(Date, Date)]) -> Date {
        MeetingSkip.firstFreeSlot(
            from: fire,
            interval: interval,
            meetings: meetings.map { DateInterval(start: $0.0, end: $0.1) }
        )
    }

    @Test("no meetings → unchanged")
    func noMeetings() {
        #expect(slot(monday(10, 20), []) == monday(10, 20))
    }

    @Test("a meeting elsewhere → unchanged")
    func meetingElsewhere() {
        #expect(slot(monday(10, 20), [(monday(11), monday(12))]) == monday(10, 20))
    }

    @Test("inside a meeting → first slot after it, keeping the rhythm")
    func insideMeeting() {
        // 10:20 and 10:40 are inside 10:15–10:45; 11:00 is free.
        #expect(slot(monday(10, 20), [(monday(10, 15), monday(10, 45))]) == monday(11))
    }

    @Test("a meeting starting exactly at the slot counts")
    func startsAtSlot() {
        #expect(slot(monday(10, 20), [(monday(10, 20), monday(10, 30))]) == monday(10, 40))
    }

    @Test("a meeting ending exactly at the slot doesn't")
    func endsAtSlot() {
        #expect(slot(monday(10, 20), [(monday(10), monday(10, 20))]) == monday(10, 20))
    }

    @Test("back-to-back meetings are both skipped")
    func backToBack() {
        let meetings = [(monday(10), monday(10, 30)), (monday(10, 30), monday(11, 10))]
        #expect(slot(monday(10, 20), meetings) == monday(11, 20))
    }
}

@Suite("Meeting skipping — which events count")
struct MeetingSettingsTests {

    let settings = MeetingSettings(isEnabled: true)

    @Test("a busy, timed, accepted event is a meeting")
    func busyTimed() {
        #expect(settings.isMeeting(meeting((10, 0), (11, 0))))
    }

    @Test("all-day events don't count")
    func allDay() {
        #expect(!settings.isMeeting(meeting((0, 0), (23, 59), isAllDay: true)))
    }

    @Test("events marked Free don't count")
    func free() {
        #expect(!settings.isMeeting(meeting((10, 0), (11, 0), isBusy: false)))
    }

    @Test("declined events don't count")
    func declined() {
        #expect(!settings.isMeeting(meeting((10, 0), (11, 0), isDeclined: true)))
    }

    @Test("events on an excluded calendar don't count")
    func excludedCalendar() {
        let settings = MeetingSettings(isEnabled: true, excludedCalendarIds: ["family"])
        #expect(!settings.isMeeting(meeting((10, 0), (11, 0), calendarId: "family")))
        #expect(settings.isMeeting(meeting((10, 0), (11, 0), calendarId: "work")))
    }

    @Test("zero-length events don't count")
    func zeroLength() {
        #expect(!settings.isMeeting(meeting((10, 0), (10, 0))))
    }
}
