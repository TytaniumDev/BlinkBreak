//
//  GoogleCalendarRow.swift
//  BlinkBreak
//
//  Stateless row showing whether a Google account is connected for meeting
//  skipping, with a Connect / Disconnect button.
//
//  Flutter analogue: a stateless ListTile with a trailing TextButton and callbacks.
//

import SwiftUI

struct GoogleCalendarRow: View {
    /// The connected account, or nil when not connected.
    let email: String?
    /// True while a connect / disconnect is in progress.
    let isWorking: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Google Calendar")
                    .font(.subheadline)
                Text(email ?? "Not connected")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
            if isWorking {
                ProgressView()
            } else if email == nil {
                Button("Connect", action: onConnect)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("button.meetings.connectGoogle")
            } else {
                Button("Disconnect", action: onDisconnect)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityIdentifier("button.meetings.disconnectGoogle")
            }
        }
    }
}

#Preview("Not connected") {
    GoogleCalendarRow(email: nil, isWorking: false, onConnect: {}, onDisconnect: {})
        .foregroundStyle(.white)
        .padding(24)
        .background(Color.calmTop)
}

#Preview("Connected") {
    GoogleCalendarRow(email: "name@gmail.com", isWorking: false, onConnect: {}, onDisconnect: {})
        .foregroundStyle(.white)
        .padding(24)
        .background(Color.calmTop)
}

#Preview("Working") {
    GoogleCalendarRow(email: nil, isWorking: true, onConnect: {}, onDisconnect: {})
        .foregroundStyle(.white)
        .padding(24)
        .background(Color.calmTop)
}
