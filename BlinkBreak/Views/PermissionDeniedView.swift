//
//  PermissionDeniedView.swift
//  BlinkBreak
//
//  Shown in place of IdleView when the user has denied notification permission.
//  The app does not work without notifications, so instead of trying to degrade
//  gracefully we tell the user how to fix it.
//

import SwiftUI

struct PermissionDeniedView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "BlinkBreak")

            Text("Notifications are off")
                .font(.title2.weight(.semibold))

            Text(
                "BlinkBreak can't remind you to take breaks without permission to send notifications. "
                + "Open Settings and enable notifications for BlinkBreak to continue."
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.top, 4)

            Spacer()

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }
}

#Preview {
    ZStack {
        CalmBackground()
        PermissionDeniedView()
            .foregroundStyle(.white)
    }
}
