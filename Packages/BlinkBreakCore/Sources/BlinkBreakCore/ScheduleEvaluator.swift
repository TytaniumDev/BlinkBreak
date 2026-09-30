//
//  ScheduleEvaluator.swift
//  BlinkBreakCore
//
//  Pure logic for weekly schedule evaluation. Answers three questions:
//  1. "Should a session be active right now?" (shouldBeActive)
//  2. "When is the next time the answer flips?" (nextTransitionDate)
//  3. "When does the current (or next) schedule window end?" (currentOrNextWindowEnd)
//
//  Has zero dependencies on UIKit, notifications, or SessionController.
//  SessionController consults this during reconcile().
//
//  Flutter analogue: a plain Dart class with no Flutter imports, fully unit-testable.
//

import Foundation

public protocol ScheduleEvaluatorProtocol: Sendable {
    func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool
    func nextTransitionDate(from date: Date, calendar: Calendar) -> Date?
    /// The end of the schedule window containing `date`, or — if `date` is between
    /// windows — the end of the next window. Nil when the schedule is disabled or has
    /// no enabled days. Used to decide when a manually started or paused session
    /// should hand control back to the schedule.
    func currentOrNextWindowEnd(from date: Date, calendar: Calendar) -> Date?
    func statusText(at date: Date, calendar: Calendar) -> String?
}

public struct NoopScheduleEvaluator: ScheduleEvaluatorProtocol {
    public init() {}
    public func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool { false }
    public func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? { nil }
    public func currentOrNextWindowEnd(from date: Date, calendar: Calendar) -> Date? { nil }
    public func statusText(at date: Date, calendar: Calendar) -> String? { nil }
}

public final class ScheduleEvaluator: ScheduleEvaluatorProtocol, @unchecked Sendable {

    private let schedule: @Sendable () -> WeeklySchedule

    public init(schedule: @escaping @Sendable () -> WeeklySchedule) {
        self.schedule = schedule
    }

    public func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool {
        let sched = schedule()
        guard sched.isEnabled else { return false }

        let weekday = calendar.component(.weekday, from: date)
        guard let day = sched.days[weekday], day.isEnabled else { return false }

        guard let startHour = day.startTime.hour, let startMinute = day.startTime.minute,
              let endHour = day.endTime.hour, let endMinute = day.endTime.minute else {
            return false
        }

        let currentMinutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        guard currentMinutes >= startMinutes && currentMinutes < endMinutes else { return false }

        // Manual stop override: if the user stopped during today's window, don't auto-restart.
        if let stopDate = manualStopDate {
            let stopWeekday = calendar.component(.weekday, from: stopDate)
            if stopWeekday == weekday && calendar.isDate(stopDate, inSameDayAs: date) {
                let stopMinutes = calendar.component(.hour, from: stopDate) * 60
                    + calendar.component(.minute, from: stopDate)
                if stopMinutes >= startMinutes && stopMinutes < endMinutes {
                    return false
                }
            }
        }

        return true
    }

    public func statusText(at date: Date, calendar: Calendar) -> String? {
        let sched = schedule()
        guard sched.isEnabled else { return nil }

        let weekday = calendar.component(.weekday, from: date)
        if let day = sched.days[weekday], day.isEnabled,
           let startHour = day.startTime.hour, let startMinute = day.startTime.minute,
           let endHour = day.endTime.hour, let endMinute = day.endTime.minute {

            let currentMinutes = calendar.component(.hour, from: date) * 60
                + calendar.component(.minute, from: date)
            let startMinutes = startHour * 60 + startMinute
            let endMinutes = endHour * 60 + endMinute

            if currentMinutes < startMinutes {
                return "Starts at \(formatScheduleTime(hour: startHour, minute: startMinute))"
            } else if currentMinutes < endMinutes {
                return "Active until \(formatScheduleTime(hour: endHour, minute: endMinute))"
            }
        }

        return nextStartText(from: date, schedule: sched, calendar: calendar)
    }

    private func nextStartText(from date: Date, schedule sched: WeeklySchedule, calendar: Calendar) -> String? {
        for dayOffset in 1...7 {
            guard let future = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let wd = calendar.component(.weekday, from: future)
            if let d = sched.days[wd], d.isEnabled,
               let h = d.startTime.hour, let m = d.startTime.minute {
                let dayName = calendar.shortWeekdaySymbols[wd - 1]
                return "Next: \(dayName) \(formatScheduleTime(hour: h, minute: m))"
            }
        }
        return nil
    }

    public func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? {
        for window in upcomingWindows(from: date, calendar: calendar) {
            if date < window.start { return window.start }
            if date < window.end { return window.end }
        }
        return nil
    }

    public func currentOrNextWindowEnd(from date: Date, calendar: Calendar) -> Date? {
        // Skip malformed windows (end at or before start) — `shouldBeActive` never
        // treats them as open, so they can't bound a session either.
        upcomingWindows(from: date, calendar: calendar)
            .first(where: { $0.start < $0.end && date < $0.end })?.end
    }

    /// Concrete start/end dates for each enabled day's window, from the day containing
    /// `date` through the same weekday next week, in chronological order.
    private func upcomingWindows(from date: Date, calendar: Calendar) -> [(start: Date, end: Date)] {
        let sched = schedule()
        guard sched.isEnabled else { return [] }

        var windows: [(start: Date, end: Date)] = []
        for dayOffset in 0..<8 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: checkDate)
            guard let day = sched.days[weekday], day.isEnabled,
                  let startHour = day.startTime.hour, let startMinute = day.startTime.minute,
                  let endHour = day.endTime.hour, let endMinute = day.endTime.minute else {
                continue
            }

            var startComps = calendar.dateComponents([.year, .month, .day], from: checkDate)
            startComps.hour = startHour
            startComps.minute = startMinute
            startComps.second = 0
            guard let startDate = calendar.date(from: startComps) else { continue }

            var endComps = startComps
            endComps.hour = endHour
            endComps.minute = endMinute
            guard let endDate = calendar.date(from: endComps) else { continue }

            windows.append((start: startDate, end: endDate))
        }
        return windows
    }
}
