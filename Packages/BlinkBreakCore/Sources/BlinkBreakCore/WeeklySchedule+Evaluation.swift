//
//  WeeklySchedule+Evaluation.swift
//  BlinkBreakCore
//
//  Pure date math over a WeeklySchedule. Answers:
//  1. "Should a session be running at this moment?" (isActive)
//  2. "When does the next window open?" (nextWindowStart)
//  3. "When does the current (or next) window close?" (currentOrNextWindowEnd)
//  4. "What should the idle screen say?" (statusText)
//
//  Everything takes an explicit Calendar so tests can pin the time zone.
//
//  Flutter analogue: extension methods on a plain Dart data class.
//

import Foundation

extension WeeklySchedule {

    /// The window scheduled on the calendar day containing `date`, or nil when
    /// that day is off.
    public func window(onDayOf date: Date, calendar: Calendar) -> DateInterval? {
        let day = day(calendar.component(.weekday, from: date))
        guard day.hasActiveWindow else { return nil }
        // bySettingHour (rather than adding minutes to midnight) keeps wall-clock
        // times correct on daylight-saving transition days.
        guard let start = calendar.date(bySettingHour: day.startMinutes / 60, minute: day.startMinutes % 60,
                                        second: 0, of: date),
              let end = calendar.date(bySettingHour: day.endMinutes / 60, minute: day.endMinutes % 60,
                                      second: 0, of: date),
              end > start else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    /// The window containing `date` (start inclusive, end exclusive), if any.
    public func activeWindow(at date: Date, calendar: Calendar) -> DateInterval? {
        guard isEnabled,
              let window = window(onDayOf: date, calendar: calendar),
              date >= window.start, date < window.end else {
            return nil
        }
        return window
    }

    /// True when a session should be running at `date`. A manual stop inside the
    /// current window keeps it off for the rest of that window.
    public func isActive(at date: Date, manualStopDate: Date? = nil, calendar: Calendar) -> Bool {
        guard let window = activeWindow(at: date, calendar: calendar) else { return false }
        if let stop = manualStopDate, stop >= window.start, stop < window.end {
            return false
        }
        return true
    }

    /// The first window start strictly after `date`, looking up to a week ahead.
    public func nextWindowStart(after date: Date, calendar: Calendar) -> Date? {
        guard isEnabled else { return nil }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  let window = window(onDayOf: day, calendar: calendar),
                  window.start > date else {
                continue
            }
            return window.start
        }
        return nil
    }

    /// The end of the window containing `date`, or — between windows — the end of
    /// the next one. Nil when the schedule is off or has no enabled days. Bounds
    /// manually started and paused sessions.
    public func currentOrNextWindowEnd(from date: Date, calendar: Calendar) -> Date? {
        guard isEnabled else { return nil }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  let window = window(onDayOf: day, calendar: calendar),
                  date < window.end else {
                continue
            }
            return window.end
        }
        return nil
    }

    /// Short status line for the idle screen, e.g. "Starts at 9:00 AM",
    /// "Active until 5:00 PM", or "Next: Mon 9:00 AM". Nil when the schedule is off.
    public func statusText(at date: Date, calendar: Calendar) -> String? {
        guard isEnabled else { return nil }
        if let window = activeWindow(at: date, calendar: calendar) {
            return "Active until \(Self.time(window.end, calendar))"
        }
        guard let next = nextWindowStart(after: date, calendar: calendar) else { return nil }
        if calendar.isDate(next, inSameDayAs: date) {
            return "Starts at \(Self.time(next, calendar))"
        }
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: next) - 1]
        return "Next: \(weekday) \(Self.time(next, calendar))"
    }

    private static func time(_ date: Date, _ calendar: Calendar) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
