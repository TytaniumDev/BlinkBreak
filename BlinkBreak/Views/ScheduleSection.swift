//
//  ScheduleSection.swift
//  BlinkBreak
//
//  The schedule configuration block that lives inline on IdleView. Contains the
//  on/off toggle, 7 day rows, and expanding time pickers.
//
//  Flutter analogue: a Column widget with a SwitchListTile header and a list of
//  day rows, backed by a ChangeNotifier that persists on every change.
//

import BlinkBreakCore
import SwiftUI

struct ScheduleSection<Controller: SessionControllerProtocol>: View {

    let controller: Controller
    @State private var expandedDay: Int?

    /// Weekdays (1 = Sunday … 7 = Saturday) starting from the locale's first day.
    private static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first + $0 - 1) % 7 + 1 }
    }

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
                            dayName: Calendar.current.shortWeekdaySymbols[weekday - 1],
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
            set: { isEnabled in
                var schedule = controller.weeklySchedule
                schedule.isEnabled = isEnabled
                controller.updateSchedule(schedule)
            }
        )
    }

    private func dayBinding(for weekday: Int) -> Binding<DaySchedule> {
        Binding(
            get: { controller.weeklySchedule.day(weekday) },
            set: { day in
                var schedule = controller.weeklySchedule
                schedule.days[weekday] = day
                controller.updateSchedule(schedule)
            }
        )
    }

    private func expandedBinding(for weekday: Int) -> Binding<Bool> {
        Binding(
            get: { expandedDay == weekday },
            set: { isExpanding in
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedDay = isExpanding ? weekday : nil
                }
            }
        )
    }

    private func rowShape(for weekday: Int) -> some Shape {
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
        CalmBackground()
        ScheduleSection(controller: PreviewSessionController.idleWithSchedule)
            .foregroundStyle(.white)
            .padding(24)
    }
    .preferredColorScheme(.dark)
}

#Preview("Disabled") {
    ZStack {
        CalmBackground()
        ScheduleSection(controller: PreviewSessionController.idle)
            .foregroundStyle(.white)
            .padding(24)
    }
    .preferredColorScheme(.dark)
}
