//
//  TestFixtures.swift
//  BlinkBreakCoreTests
//
//  Shared helpers for the SessionController suites: a controllable clock, a
//  controllable `sleep`, a GMT calendar with fixed dates, and a fixture that
//  wires them into a SessionController with mocks.
//

import Foundation
import Synchronization
@testable import BlinkBreakCore

/// Mutable "now" shared between a test and the controller's clock closure.
final class NowBox: Sendable {
    private let storage: Mutex<Date>
    init(_ date: Date) { storage = Mutex(date) }
    var value: Date {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

/// A `sleep` that suspends until the test calls `releaseAll()`. Lets tests decide
/// exactly when the controller's grace periods and timed wake-ups end.
final class ManualSleeper: Sendable {
    private let waiters = Mutex<[CheckedContinuation<Void, Never>]>([])

    var pendingCount: Int { waiters.withLock { $0.count } }

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { continuation in
            waiters.withLock { $0.append(continuation) }
        }
    }

    func releaseAll() {
        let released = waiters.withLock { waiters in
            defer { waiters.removeAll() }
            return waiters
        }
        released.forEach { $0.resume() }
    }
}

enum TestCalendar {
    /// Gregorian, GMT, so window math doesn't depend on the machine's time zone.
    static let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// A date in the week of Sun 2026-04-05 … Sat 2026-04-11.
    /// `weekday` uses Foundation numbering: 1 = Sunday … 7 = Saturday.
    static func date(weekday: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        gmt.date(from: DateComponents(
            year: 2026, month: 4, day: 4 + weekday,
            hour: hour, minute: minute, second: second
        ))!
    }
}

/// Wires up a `SessionController` with mocks, a virtual clock, and a manual sleeper.
@MainActor
final class SessionControllerFixture {
    let alarms = MockAlarmScheduler()
    let persistence: InMemoryPersistence
    let now: NowBox
    let sleeper = ManualSleeper()
    let controller: SessionController

    /// Defaults to Monday 10:00 GMT with the schedule off.
    init(
        now: Date = TestCalendar.date(weekday: 2, hour: 10),
        session: SessionRecord = SessionRecord(),
        schedule: WeeklySchedule = .default
    ) {
        let box = NowBox(now)
        let sleeper = sleeper
        self.now = box
        self.persistence = InMemoryPersistence(session: session, schedule: schedule)
        self.controller = SessionController(
            alarmScheduler: alarms,
            persistence: persistence,
            calendar: TestCalendar.gmt,
            clock: { box.value },
            sleep: { await sleeper.sleep($0) }
        )
    }

    var record: SessionRecord { persistence.loadSession() }

    func advance(by seconds: TimeInterval) {
        now.value = now.value.addingTimeInterval(seconds)
    }

    /// Let queued transitions and spawned tasks finish.
    func settle() async {
        for _ in 0..<5 {
            await Task.yield()
            await controller.waitUntilIdle()
        }
    }

    /// End every pending grace period / wake-up, then settle.
    func releaseSleepsAndSettle() async {
        await settle()
        sleeper.releaseAll()
        await settle()
    }

    /// Start a session and return its break alarm ID.
    @discardableResult
    func startRunning() async -> UUID {
        await controller.start()
        return record.alarmId!
    }

    /// Start, let the break come due, and start the break. Returns the look-away alarm ID.
    @discardableResult
    func startLookingAway() async -> UUID {
        await startRunning()
        advance(by: BlinkBreakConstants.breakInterval)
        await controller.startBreak()
        return record.alarmId!
    }
}

extension WeeklySchedule {
    /// Mon–Fri 9–5, master toggle on.
    static let workweekOn: WeeklySchedule = {
        var schedule = WeeklySchedule.default
        schedule.isEnabled = true
        return schedule
    }()
}
