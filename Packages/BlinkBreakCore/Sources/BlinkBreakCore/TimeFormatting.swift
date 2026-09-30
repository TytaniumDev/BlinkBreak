//
//  TimeFormatting.swift
//  BlinkBreakCore
//
//  Locale-aware time-of-day formatting used by the schedule UI.
//

import Foundation

/// Format a time-of-day from DateComponents into a locale-appropriate short string.
public func formatScheduleTime(_ components: DateComponents, calendar: Calendar = .current) -> String {
    guard let date = calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0,
                                   second: 0, of: Date()) else {
        return ""
    }
    return date.formatted(date: .omitted, time: .shortened)
}
