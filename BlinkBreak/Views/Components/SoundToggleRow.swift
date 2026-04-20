//
//  SoundToggleRow.swift
//  BlinkBreak
//
//  Stateless toggle row for the alarm sound setting. Toggle ON = sound enabled.
//
//  Flutter analogue: a stateless SwitchListTile-style widget that takes callbacks.
//

import SwiftUI

struct SoundToggleRow: View {
    let isMuted: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Text("Alarm Sound")
                .font(.subheadline.weight(.medium))
            Spacer()
            Toggle("Alarm Sound", isOn: Binding(
                get: { !isMuted },
                set: { onToggle(!$0) }
            ))
            .labelsHidden()
            .tint(.green)
        }
    }
}

#Preview("Sound On") {
    SoundToggleRow(isMuted: false, onToggle: { _ in })
        .foregroundStyle(.white)
        .padding(24)
        .background(Color("BackgroundCalmTop"))
}

#Preview("Sound Off") {
    SoundToggleRow(isMuted: true, onToggle: { _ in })
        .foregroundStyle(.white)
        .padding(24)
        .background(Color("BackgroundCalmTop"))
}
