//
//  CompositeCalendarProviderTests.swift
//  BlinkBreakCoreTests
//
//  Several calendar sources presented as one, and the offline event cache.
//

import Testing
@testable import BlinkBreakCore

@Suite("Calendar sources — composite")
struct CompositeCalendarProviderTests {

    let phone: MockCalendarProvider
    let google: MockCalendarProvider
    // One composite per test: each mock's change stream allows a single listener.
    let composite: CompositeCalendarProvider

    init() {
        let phone = MockCalendarProvider()
        let google = MockCalendarProvider()
        self.phone = phone
        self.google = google
        composite = CompositeCalendarProvider([phone, google])
    }

    @Test("events and calendars from every source are combined")
    func combined() async {
        phone.addEvent(meeting((10, 0), (10, 30), calendarId: "home"))
        google.addEvent(meeting((11, 0), (11, 30), calendarId: "work"))
        let home = CalendarInfo(id: "home", title: "Home", accountTitle: "iCloud")
        let work = CalendarInfo(id: "work", title: "Work", accountTitle: "Google")
        phone.setCalendars([home])
        google.setCalendars([work])

        let events = await composite.events(from: monday(9), to: monday(12))
        #expect(Set(events.map(\.calendarId)) == ["home", "work"])
        #expect(await composite.calendars() == [home, work])
    }

    @Test("authorized when any source is")
    func anyAuthorized() async {
        phone.stubAccess(.denied)
        google.stubAccess(.authorized)
        #expect(await composite.accessStatus() == .authorized)
    }

    @Test("denied when none is authorized and one is denied")
    func deniedWins() async {
        phone.stubAccess(.denied)
        google.stubAccess(.notDetermined)
        #expect(await composite.accessStatus() == .denied)
    }

    @Test("not determined when no source has answered")
    func notDetermined() async {
        phone.stubAccess(.notDetermined)
        google.stubAccess(.notDetermined)
        #expect(await composite.accessStatus() == .notDetermined)
    }

    @Test("requestAccess asks every source and is granted if any grants")
    func requestAccess() async {
        phone.stubAccess(.notDetermined, grantsOnRequest: false)
        google.stubAccess(.authorized)

        #expect(await composite.requestAccess())
        #expect(phone.requestCount == 1)
        #expect(google.requestCount == 1)
    }

    @Test("a change in any source is reported")
    func changesMerged() async {
        var iterator = composite.changes.makeAsyncIterator()
        google.simulateChange()
        #expect(await iterator.next() != nil)
    }
}

@Suite("Calendar sources — offline cache")
struct CalendarEventCacheTests {

    @Test("returns cached events overlapping the range")
    func overlapping() {
        let cache = CalendarEventCache(
            fetchedFrom: monday(9),
            fetchedTo: monday(17),
            events: [meeting((10, 0), (10, 30)), meeting((14, 0), (15, 0))]
        )
        #expect(cache.events(from: monday(10, 15), to: monday(12)) == [meeting((10, 0), (10, 30))])
        #expect(cache.events(from: monday(10, 30), to: monday(14)).isEmpty)
    }

    @Test("round-trips through JSON")
    func codable() throws {
        let cache = CalendarEventCache(fetchedFrom: monday(9), fetchedTo: monday(17), events: [meeting((10, 0), (10, 30))])
        let decoded = try JSONDecoder().decode(CalendarEventCache.self, from: JSONEncoder().encode(cache))
        #expect(decoded == cache)
    }
}
