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

import SwiftUI
import BlinkBreakCore

struct ScheduleSection<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    @State private var expandedDay: Int?

    private static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first + $0 - 1) % 7 + 1 }
    }

    private let dayNames: [Int: String] = [
        1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Schedule")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("Enable Schedule", isOn: masterToggleBinding)
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

    private var masterToggleBinding: Binding<Bool> {
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

    private func dayBinding(for weekday: Int) -> Binding<DaySchedule> {
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
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
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
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        ScheduleSection(controller: PreviewSessionController(state: .idle))
            .foregroundStyle(.white)
            .padding(24)
    }
}
