//
//  ScheduleStatusLabel.swift
//  BlinkBreak
//
//  Shows schedule context above the Start button: "Starts at 9:00 AM",
//  "Active until 5:00 PM", or nothing when schedule is disabled.
//
//  Stateless: takes a WeeklySchedule and the current date, computes the label.
//
//  Flutter analogue: a simple Text widget driven by a computed string.
//

import SwiftUI
import BlinkBreakCore

struct ScheduleStatusLabel: View {
    let schedule: WeeklySchedule
    let now: Date

    var body: some View {
        if let text = statusText {
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityIdentifier("label.schedule.status")
        }
    }

    private var statusText: String? {
        guard schedule.isEnabled else { return nil }

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        guard let day = schedule.days[weekday], day.isEnabled,
              let startHour = day.startTime.hour, let startMinute = day.startTime.minute,
              let endHour = day.endTime.hour, let endMinute = day.endTime.minute else {
            return nextStartText(from: now, calendar: cal)
        }

        let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        if currentMinutes < startMinutes {
            return "Starts at \(formatTime(hour: startHour, minute: startMinute))"
        } else if currentMinutes < endMinutes {
            return "Active until \(formatTime(hour: endHour, minute: endMinute))"
        } else {
            return nextStartText(from: now, calendar: cal)
        }
    }

    private func nextStartText(from date: Date, calendar cal: Calendar) -> String? {
        for dayOffset in 1...7 {
            guard let future = cal.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let wd = cal.component(.weekday, from: future)
            if let d = schedule.days[wd], d.isEnabled,
               let h = d.startTime.hour, let m = d.startTime.minute {
                let dayName = cal.shortWeekdaySymbols[wd - 1]
                return "Next: \(dayName) \(formatTime(hour: h, minute: m))"
            }
        }
        return nil
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}

#Preview("Before window") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        ScheduleStatusLabel(schedule: .default, now: Date())
    }
}
