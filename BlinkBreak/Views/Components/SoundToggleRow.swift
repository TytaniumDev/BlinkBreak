//
//  SoundToggleRow.swift
//  BlinkBreak
//
//  Stateless toggle row for the alarm sound setting. Binds to the controller's
//  `muteAlarmSound` property via `updateAlarmSound(muted:)`. Toggle ON = sound enabled.
//
//  Flutter analogue: a stateless SwitchListTile-style widget that takes callbacks.
//

import SwiftUI
import BlinkBreakCore

struct SoundToggleRow<Controller: SessionControllerProtocol>: View {
    @ObservedObject var controller: Controller

    var body: some View {
        HStack {
            Text("Alarm Sound")
                .font(.subheadline.weight(.medium))
            Spacer()
            Toggle("Alarm Sound", isOn: Binding(
                get: { !controller.muteAlarmSound },
                set: { controller.updateAlarmSound(muted: !$0) }
            ))
            .labelsHidden()
            .tint(.green)
        }
    }
}

#Preview("Sound On") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        SoundToggleRow(controller: PreviewSessionController(state: .idle))
            .foregroundStyle(.white)
            .padding(24)
    }
}

#Preview("Sound Off") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        SoundToggleRow(controller: {
            let c = PreviewSessionController(state: .idle)
            c.muteAlarmSound = true
            return c
        }())
        .foregroundStyle(.white)
        .padding(24)
    }
}
