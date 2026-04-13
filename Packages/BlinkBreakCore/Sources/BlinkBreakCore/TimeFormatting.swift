//
//  TimeFormatting.swift
//  BlinkBreakCore
//
//  Locale-aware time formatting used by schedule status text and UI components.
//

import Foundation

/// Format a time-of-day from DateComponents into a locale-appropriate short string.
public func formatScheduleTime(_ components: DateComponents) -> String {
    guard let date = Calendar.current.date(from: components) else { return "" }
    return date.formatted(date: .omitted, time: .shortened)
}

/// Convenience overload accepting hour/minute directly.
public func formatScheduleTime(hour: Int, minute: Int) -> String {
    formatScheduleTime(DateComponents(hour: hour, minute: minute))
}
