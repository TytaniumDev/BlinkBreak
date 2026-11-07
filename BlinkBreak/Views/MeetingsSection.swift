//
//  MeetingsSection.swift
//  BlinkBreak
//
//  The "Skip Breaks in Meetings" block on IdleView: an on/off toggle, a link
//  to choose which calendars count, a hint when calendar access is denied,
//  and a row to connect a Google account (for calendars that can't be added
//  to the iPhone, like a work calendar shared as free/busy only).
//  Turning it on is what triggers the calendar permission prompt (inside
//  `updateMeetingSettings`).
//
//  Flutter analogue: a SwitchListTile with a subtitle that changes with state,
//  plus a showModalBottomSheet for the calendar list.
//

import BlinkBreakCore
import SwiftUI

struct MeetingsSection<Controller: SessionControllerProtocol>: View {

    let controller: Controller
    @State private var showingCalendars = false
    @State private var isGoogleWorking = false
    @State private var googleError: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.googleAccount) private var googleAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Skip Breaks in Meetings")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("Skip Breaks in Meetings", isOn: toggleBinding)
                    .labelsHidden()
                    .tint(.green)
                    .accessibilityIdentifier("toggle.meetings")
            }

            if controller.calendarAccessDenied {
                Button("Allow calendar access in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityIdentifier("button.meetings.openSettings")
            } else if controller.meetingSettings.isEnabled {
                Button("Choose calendars") {
                    showingCalendars = true
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityIdentifier("button.meetings.chooseCalendars")
            }

            if let googleAccount {
                GoogleCalendarRow(
                    email: googleAccount.email,
                    isWorking: isGoogleWorking,
                    onConnect: { runGoogle { try await googleAccount.connect() } },
                    onDisconnect: { runGoogle { await googleAccount.disconnect() } }
                )
                .padding(.top, 6)
            }

            if let googleError {
                Text(googleError)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
        .sheet(isPresented: $showingCalendars) {
            CalendarPickerView(controller: controller)
        }
    }

    private func runGoogle(_ action: @escaping @MainActor () async throws -> Void) {
        isGoogleWorking = true
        googleError = nil
        Task {
            do {
                try await action()
            } catch {
                googleError = error.localizedDescription
            }
            isGoogleWorking = false
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { controller.meetingSettings.isEnabled },
            set: { isEnabled in
                var settings = controller.meetingSettings
                settings.isEnabled = isEnabled
                Task { await controller.updateMeetingSettings(settings) }
            }
        )
    }
}

#Preview("Off") {
    ZStack {
        CalmBackground()
        MeetingsSection(controller: PreviewSessionController.idle)
            .foregroundStyle(.white)
            .padding(24)
    }
    .preferredColorScheme(.dark)
}

#Preview("On") {
    ZStack {
        CalmBackground()
        MeetingsSection(controller: PreviewSessionController.meetingsOn)
            .foregroundStyle(.white)
            .padding(24)
    }
    .environment(\.googleAccount, PreviewGoogleAccount())
    .preferredColorScheme(.dark)
}

#Preview("On, Google connected") {
    ZStack {
        CalmBackground()
        MeetingsSection(controller: PreviewSessionController.meetingsOn)
            .foregroundStyle(.white)
            .padding(24)
    }
    .environment(\.googleAccount, PreviewGoogleAccount(email: "name@gmail.com"))
    .preferredColorScheme(.dark)
}

#Preview("Access denied") {
    ZStack {
        CalmBackground()
        MeetingsSection(controller: PreviewSessionController.calendarDenied)
            .foregroundStyle(.white)
            .padding(24)
    }
    .preferredColorScheme(.dark)
}
