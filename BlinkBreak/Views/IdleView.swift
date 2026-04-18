//
//  IdleView.swift
//  BlinkBreak
//
//  The idle-state view. Shows the app name, a short explainer, and a Start button.
//  No icon per design feedback — explainer text carries the meaning instead.
//

import SwiftUI
import BlinkBreakCore

struct IdleView<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    let scheduleStatusText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "BlinkBreak")

            Text("20-20-20 Rule")
                .font(.title2.weight(.semibold))

            Text("Every 20 minutes, look at something 20 feet away for 20 seconds. Your eyes will thank you.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)

            ScheduleSection(controller: controller)
                .padding(.top, 12)

            SoundToggleRow(controller: controller)
                .padding(.top, 8)

            Spacer()

            ScheduleStatusLabel(text: scheduleStatusText)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            Button {
                controller.start()
            } label: {
                Text("Start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("button.idle.start")
        }
        .padding(24)
    }
}

#Preview {
    ZStack {
        CalmBackground()
        IdleView(
            controller: {
                let c = PreviewSessionController(state: .idle)
                c.weeklySchedule = .default
                return c
            }(),
            scheduleStatusText: "Starts at 9:00 AM"
        )
            .foregroundStyle(.white)
    }
}
