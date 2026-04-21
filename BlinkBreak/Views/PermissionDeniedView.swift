//
//  PermissionDeniedView.swift
//  BlinkBreak
//
//  Shown in place of IdleView when the user has denied AlarmKit permission.
//  Without authorization we can't schedule alarms, so the app is non-functional;
//  surface a clear path back to Settings instead of failing silently.
//

import SwiftUI

struct PermissionDeniedView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "BlinkBreak")

            Text("Alarms are off")
                .font(.title2.weight(.semibold))

            Text(
                "BlinkBreak needs permission to schedule alarms for break reminders. "
                + "Open Settings and enable alarms for BlinkBreak to continue."
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.top, 4)

            Spacer()

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("button.permissionDenied.openSettings")
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
