//
//  TimeFormatting.swift
//  BlinkBreak
//
//  Shared time formatting for schedule UI components.
//

import Foundation

func formatScheduleTime(_ components: DateComponents) -> String {
    let hour = components.hour ?? 0
    let minute = components.minute ?? 0
    let period = hour >= 12 ? "PM" : "AM"
    let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
    return String(format: "%d:%02d %@", displayHour, minute, period)
}

func formatScheduleTime(hour: Int, minute: Int) -> String {
    let period = hour >= 12 ? "PM" : "AM"
    let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
    return String(format: "%d:%02d %@", displayHour, minute, period)
}
