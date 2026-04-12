//
//  TimeFormatting.swift
//  BlinkBreak
//
//  Shared time formatting for schedule UI components. Uses Foundation's
//  locale-aware formatting so times display correctly for all locales
//  (e.g., 24-hour vs. 12-hour, locale-specific AM/PM strings).
//

import Foundation

func formatScheduleTime(_ components: DateComponents) -> String {
    guard let date = Calendar.current.date(from: components) else { return "" }
    return date.formatted(date: .omitted, time: .shortened)
}

func formatScheduleTime(hour: Int, minute: Int) -> String {
    formatScheduleTime(DateComponents(hour: hour, minute: minute))
}
