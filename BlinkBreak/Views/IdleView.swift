//
//  IdleView.swift
//  BlinkBreak
//
//  The idle-state view: app name, a short explainer, schedule and sound
//  settings, and a Start button. No icon per design feedback — the explainer
//  text carries the meaning instead.
//

import BlinkBreakCore
import SwiftUI

struct IdleView<Controller: SessionControllerProtocol>: View {

    let controller: Controller

    @State private var showingFeedbackSheet = false

    var body: some View {
        AdaptiveScreen {
            VStack(alignment: .leading, spacing: 12) {
                header

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

                Spacer(minLength: 24)

                // Re-evaluated every minute so "Starts at…" flips to "Active until…" on time.
                TimelineView(.everyMinute) { context in
                    ScheduleStatusLabel(text: controller.scheduleStatus(at: context.date))
                }
                .frame(maxWidth: .infinity)
            }
        } actions: {
            Button {
                Task { await controller.start() }
            } label: {
                Text("Start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("button.idle.start")
        }
        .sheet(isPresented: $showingFeedbackSheet) {
            FeedbackSheetView()
        }
    }

    private var header: some View {
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
            .accessibilityLabel("Send feedback")
            .accessibilityIdentifier("button.idle.feedback")
        }
    }
}

#Preview("Schedule on") {
    ZStack {
        CalmBackground()
        IdleView(controller: PreviewSessionController.idleWithSchedule)
            .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}

#Preview("Schedule off") {
    ZStack {
        CalmBackground()
        IdleView(controller: PreviewSessionController.idle)
            .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}
