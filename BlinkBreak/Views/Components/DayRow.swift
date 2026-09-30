//
//  DayRow.swift
//  BlinkBreak
//
//  A single row in the schedule day list. Shows the day name, time range
//  (tappable to expand the pickers), and an enable/disable toggle.
//
//  Stateless: the parent owns the Bindings. Time rounding and keeping the end
//  after the start live in `DaySchedule.settingStart` / `settingEnd` (Core).
//
//  Flutter analogue: a ListTile-style widget with a Switch trailing widget.
//

import BlinkBreakCore
import SwiftUI

struct DayRow: View {
    let dayName: String
    @Binding var daySchedule: DaySchedule
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Enable \(dayName)", isOn: $daySchedule.isEnabled)
                    .labelsHidden()
                    .tint(.green)
                    .scaleEffect(0.8)
                    .frame(width: 40)

                Text(dayName)
                    .font(.subheadline.weight(.medium))
                    .opacity(daySchedule.isEnabled ? 1.0 : 0.4)

                Spacer()

                if daySchedule.isEnabled {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Text(timeRangeText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .accessibilityHint(isExpanded ? "Collapses the time pickers" : "Expands the time pickers")
                } else {
                    Text("Off")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))

            if isExpanded && daySchedule.isEnabled {
                VStack(spacing: 8) {
                    DatePicker("Start", selection: startBinding, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: endBinding, displayedComponents: .hourAndMinute)
                }
                .datePickerStyle(.compact)
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.03))
            }
        }
    }

    private var timeRangeText: String {
        "\(formatScheduleTime(daySchedule.startTime)) \u{2013} \(formatScheduleTime(daySchedule.endTime))"
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { Self.date(from: daySchedule.startTime) },
            set: { date in
                let (hour, minute) = Self.hourAndMinute(of: date)
                daySchedule = daySchedule.settingStart(hour: hour, minute: minute)
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { Self.date(from: daySchedule.endTime) },
            set: { date in
                let (hour, minute) = Self.hourAndMinute(of: date)
                daySchedule = daySchedule.settingEnd(hour: hour, minute: minute)
            }
        )
    }

    /// Today's date at the stored time, for the DatePicker to edit.
    private static func date(from time: DateComponents) -> Date {
        Calendar.current.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: Date()) ?? Date()
    }

    private static func hourAndMinute(of date: Date) -> (Int, Int) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0, parts.minute ?? 0)
    }
}

#Preview("Enabled") {
    ZStack {
        CalmBackground()
        DayRow(
            dayName: "Mon",
            daySchedule: .constant(.nineToFive(isEnabled: true)),
            isExpanded: .constant(false)
        )
        .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}

#Preview("Disabled") {
    ZStack {
        CalmBackground()
        DayRow(
            dayName: "Sat",
            daySchedule: .constant(.nineToFive(isEnabled: false)),
            isExpanded: .constant(false)
        )
        .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}

#Preview("Expanded") {
    ZStack {
        CalmBackground()
        DayRow(
            dayName: "Mon",
            daySchedule: .constant(.nineToFive(isEnabled: true)),
            isExpanded: .constant(true)
        )
        .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}
