//
//  DayRow.swift
//  BlinkBreak
//
//  A single row in the schedule day list. Shows the day name, time range
//  (tappable to expand picker), and an enable/disable toggle.
//
//  Stateless: takes all values as parameters. Parent manages the Binding.
//
//  Flutter analogue: a ListTile-style widget with a Switch trailing widget.
//

import SwiftUI
import BlinkBreakCore

struct DayRow: View {
    let dayName: String
    @Binding var daySchedule: DaySchedule
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("", isOn: $daySchedule.isEnabled)
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(timeRangeText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
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
                    DatePicker("Start", selection: startTimeBinding,
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "en_US"))
                    DatePicker("End", selection: endTimeBinding,
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "en_US"))
                }
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

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: { dateFromComponents(daySchedule.startTime) },
            set: { newDate in
                let cal = Calendar.current
                let h = cal.component(.hour, from: newDate)
                let rawM = cal.component(.minute, from: newDate)
                let m = (rawM / 5) * 5
                daySchedule.startTime = DateComponents(hour: h, minute: m)
            }
        )
    }

    private var endTimeBinding: Binding<Date> {
        Binding(
            get: { dateFromComponents(daySchedule.endTime) },
            set: { newDate in
                let cal = Calendar.current
                let h = cal.component(.hour, from: newDate)
                let rawM = cal.component(.minute, from: newDate)
                let m = (rawM / 5) * 5
                daySchedule.endTime = DateComponents(hour: h, minute: m)
            }
        )
    }

    private func dateFromComponents(_ comps: DateComponents) -> Date {
        let cal = Calendar.current
        var dc = cal.dateComponents([.year, .month, .day], from: Date())
        dc.hour = comps.hour ?? 0
        dc.minute = comps.minute ?? 0
        return cal.date(from: dc) ?? Date()
    }
}

#Preview("Enabled") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        DayRow(
            dayName: "Monday",
            daySchedule: .constant(DaySchedule(
                isEnabled: true,
                startTime: DateComponents(hour: 9, minute: 0),
                endTime: DateComponents(hour: 17, minute: 0)
            )),
            isExpanded: .constant(false)
        ).foregroundStyle(.white)
    }
}

#Preview("Disabled") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        DayRow(
            dayName: "Saturday",
            daySchedule: .constant(DaySchedule(
                isEnabled: false,
                startTime: DateComponents(hour: 9, minute: 0),
                endTime: DateComponents(hour: 17, minute: 0)
            )),
            isExpanded: .constant(false)
        ).foregroundStyle(.white)
    }
}

#Preview("Expanded") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        DayRow(
            dayName: "Monday",
            daySchedule: .constant(DaySchedule(
                isEnabled: true,
                startTime: DateComponents(hour: 9, minute: 0),
                endTime: DateComponents(hour: 17, minute: 0)
            )),
            isExpanded: .constant(true)
        ).foregroundStyle(.white)
    }
}
