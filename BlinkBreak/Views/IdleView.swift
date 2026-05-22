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
    let persistence: PersistenceProtocol

    @State private var showingFeedbackSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "BlinkBreak")

                    Text("20-20-20 Rule")
                        .font(.title2.weight(.semibold))
                }

                Spacer()

                Button {
                    showingFeedbackSheet = true
                } label: {
                    Image(systemName: "bubble.right")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(10)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .accessibilityIdentifier("button.idle.feedback")
            }

            Text("Every 20 minutes, look at something 20 feet away for 20 seconds. Your eyes will thank you.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)

            ScheduleSection(controller: controller)
                .padding(.top, 12)

            SoundToggleRow(
                isMuted: controller.muteAlarmSound,
                onToggle: { controller.updateAlarmSound(muted: $0) }
            )
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
        .sheet(isPresented: $showingFeedbackSheet) {
            FeedbackSheetView(
                persistence: persistence,
                sessionState: controller.state
            )
        }
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
            scheduleStatusText: "Starts at 9:00 AM",
            persistence: InMemoryPersistence()
        )
            .foregroundStyle(.white)
    }
}
