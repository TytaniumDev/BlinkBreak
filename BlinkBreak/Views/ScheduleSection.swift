//
//  ScheduleSection.swift
//  BlinkBreak
//
//  The schedule configuration block that lives inline on IdleView. Contains the
//  master toggle, 7 day rows, and expanding time pickers.
//
//  Flutter analogue: a Column widget with a SwitchListTile header and a ListView of
//  day rows, backed by a ChangeNotifier that persists on every change.
//

import BlinkBreakCore
import SwiftUI

struct ScheduleSection<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    @State private var expandedDay: Weekday?

    // Computed once at process start. A locale change that moves the first weekday
    // (e.g. US Sunday-first → UK Monday-first) requires an app restart to reflect —
    // acceptable since iOS restarts the app on most locale switches anyway.
    private static let orderedWeekdays: [Weekday] = {
        let first = Calendar.current.firstWeekday
        return (0..<7).compactMap { Weekday(calendarWeekday: (first + $0 - 1) % 7 + 1) }
    }()

    private let dayNames: [Weekday: String] = [
        .sunday: "Sun", .monday: "Mon", .tuesday: "Tue", .wednesday: "Wed",
        .thursday: "Thu", .friday: "Fri", .saturday: "Sat"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Schedule")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("Enable Schedule", isOn: scheduleToggleBinding)
                    .labelsHidden()
                    .tint(.green)
            }
            .padding(.bottom, 10)

            if controller.weeklySchedule.isEnabled {
                VStack(spacing: 1) {
                    ForEach(Self.orderedWeekdays, id: \.self) { weekday in
                        DayRow(
                            dayName: dayNames[weekday] ?? "",
                            daySchedule: dayBinding(for: weekday),
                            isExpanded: expandedBinding(for: weekday)
                        )
                        .clipShape(rowShape(for: weekday))
                    }
                }
            }
        }
        .accessibilityIdentifier("section.schedule")
    }

    private var scheduleToggleBinding: Binding<Bool> {
        Binding(
            get: { controller.weeklySchedule.isEnabled },
            set: { newValue in
                var schedule = controller.weeklySchedule
                if schedule.days.isEmpty && newValue {
                    schedule = .default
                } else {
                    schedule.isEnabled = newValue
                }
                controller.updateSchedule(schedule)
            }
        )
    }

    private func dayBinding(for weekday: Weekday) -> Binding<DaySchedule> {
        Binding(
            get: {
                controller.weeklySchedule.days[weekday] ?? DaySchedule(
                    isEnabled: false,
                    startTime: DateComponents(hour: 9, minute: 0),
                    endTime: DateComponents(hour: 17, minute: 0)
                )
            },
            set: { newDay in
                var schedule = controller.weeklySchedule
                schedule.days[weekday] = newDay
                controller.updateSchedule(schedule)
            }
        )
    }

    private func expandedBinding(for weekday: Weekday) -> Binding<Bool> {
        Binding(
            get: { expandedDay == weekday },
            set: { isExpanding in
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedDay = isExpanding ? weekday : nil
                }
            }
        )
    }

    private func rowShape(for weekday: Weekday) -> some Shape {
        let isFirst = weekday == Self.orderedWeekdays.first
        let isLast = weekday == Self.orderedWeekdays.last
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? 10 : 2,
            bottomLeadingRadius: isLast ? 10 : 2,
            bottomTrailingRadius: isLast ? 10 : 2,
            topTrailingRadius: isFirst ? 10 : 2
        )
    }
}

#Preview("Enabled") {
    ZStack {
        Color("BackgroundCalmTop").ignoresSafeArea()
        ScheduleSection(controller: {
            let c = PreviewSessionController(state: .idle)
            c.weeklySchedule = .default
            return c
        }())
            .foregroundStyle(.white)
            .padding(24)
    }
}

#Preview("Disabled") {
    ZStack {
        Color("BackgroundCalmTop").ignoresSafeArea()
        ScheduleSection(controller: PreviewSessionController(state: .idle))
            .foregroundStyle(.white)
            .padding(24)
    }
}
