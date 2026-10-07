//
//  RunningView.swift
//  BlinkBreak
//
//  The running-state view. Shows the countdown ring to the next break, the
//  sound toggle, "Take break now", Stop, and — inside a schedule window —
//  Pause. TimelineView ticks the display every second.
//
//  No business logic here — every value shown is derived from `breakAt` and
//  the current wall-clock time. `canPause` is read inside a timeline, so the
//  Pause button appears / disappears as schedule windows open and close.
//

import BlinkBreakCore
import SwiftUI

struct RunningView<Controller: SessionControllerProtocol>: View {

    let controller: Controller
    /// When the break alarm fires.
    let breakAt: Date

    var body: some View {
        AdaptiveScreen {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                EyebrowLabel(text: "Next break in")

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdown(at: context.date)
                }

                Text("Fires at \(breakAt.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))

                SoundToggleRow(
                    isMuted: controller.muteAlarmSound,
                    onToggle: { controller.updateAlarmSound(muted: $0) }
                )
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
        } actions: {
            VStack(spacing: 12) {
                Button("Take break now") {
                    Task { await controller.takeBreakNow() }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityIdentifier("button.running.takeBreakNow")

                TimelineView(.everyMinute) { _ in
                    HStack(spacing: 12) {
                        if controller.canPause {
                            Button {
                                Task { await controller.pause() }
                            } label: {
                                Text("Pause")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .tint(.white)
                            .accessibilityIdentifier("button.running.pause")
                        }

                        StopButton(identifier: "button.running.stop") {
                            await controller.stop()
                        }
                    }
                }
            }
        }
    }

    private func countdown(at date: Date) -> some View {
        let interval = BlinkBreakConstants.breakInterval
        let remaining = max(0, breakAt.timeIntervalSince(date))
        let shown = Duration.seconds(remaining.rounded(.up))
        return CountdownRing(
            progress: (interval - remaining) / interval,
            label: shown.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(shown.formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
        .accessibilityIdentifier("label.running.countdown")
    }
}

#Preview("Manual") {
    ZStack {
        CalmBackground()
        RunningView(
            controller: PreviewSessionController.running,
            breakAt: Date().addingTimeInterval(6 * 60)
        )
        .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}

#Preview("In schedule (pausable)") {
    ZStack {
        CalmBackground()
        RunningView(
            controller: PreviewSessionController.runningInSchedule,
            breakAt: Date().addingTimeInterval(6 * 60)
        )
        .foregroundStyle(.white)
    }
    .preferredColorScheme(.dark)
}
