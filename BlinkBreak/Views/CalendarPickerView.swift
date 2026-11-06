//
//  CalendarPickerView.swift
//  BlinkBreak
//
//  Sheet listing the user's calendars, grouped by account, each with a toggle
//  for whether its events count as meetings. Opened from MeetingsSection.
//
//  Flutter analogue: a modal bottom sheet with a grouped ListView of
//  SwitchListTiles, loading its items in initState.
//

import BlinkBreakCore
import SwiftUI

struct CalendarPickerView<Controller: SessionControllerProtocol>: View {

    let controller: Controller
    @Environment(\.dismiss) private var dismiss
    @State private var calendars: [CalendarInfo] = []

    /// Calendars grouped by account, in the order the controller returned them.
    private var accounts: [(title: String, calendars: [CalendarInfo])] {
        var order: [String] = []
        var grouped: [String: [CalendarInfo]] = [:]
        for calendar in calendars {
            if grouped[calendar.accountTitle] == nil { order.append(calendar.accountTitle) }
            grouped[calendar.accountTitle, default: []].append(calendar)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Breaks that land during an event on these calendars are skipped. "
                            + "All-day events, events marked Free, and declined invitations never count."
                    )
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .listRowBackground(Color.clear)
                }
                ForEach(accounts, id: \.title) { account in
                    Section(account.title) {
                        ForEach(account.calendars) { calendar in
                            Toggle(calendar.title, isOn: binding(for: calendar.id))
                                .tint(.green)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CalmBackground())
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationSizing(.form)
        .task {
            calendars = await controller.availableCalendars()
        }
    }

    private func binding(for calendarId: String) -> Binding<Bool> {
        Binding(
            get: { !controller.meetingSettings.excludedCalendarIds.contains(calendarId) },
            set: { isIncluded in
                var settings = controller.meetingSettings
                if isIncluded {
                    settings.excludedCalendarIds.remove(calendarId)
                } else {
                    settings.excludedCalendarIds.insert(calendarId)
                }
                Task { await controller.updateMeetingSettings(settings) }
            }
        )
    }
}

#Preview {
    CalendarPickerView(controller: PreviewSessionController.meetingsOn)
        .preferredColorScheme(.dark)
}
