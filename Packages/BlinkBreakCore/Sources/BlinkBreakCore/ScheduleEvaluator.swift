//
//  ScheduleEvaluator.swift
//  BlinkBreakCore
//
//  Pure logic for weekly schedule evaluation. Answers two questions:
//  1. "Should a session be active right now?" (shouldBeActive)
//  2. "When is the next time the answer flips?" (nextTransitionDate)
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
}

public struct NoopScheduleEvaluator: ScheduleEvaluatorProtocol {
    public init() {}
    public func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool { false }
    public func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? { nil }
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

    public func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? {
        let sched = schedule()
        guard sched.isEnabled else { return nil }

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

            if date < startDate { return startDate }
            if date >= startDate && date < endDate { return endDate }
        }

        return nil
    }
}
