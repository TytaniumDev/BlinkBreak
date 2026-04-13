## 2026-04-12 - VoiceOver and SwiftUI Toggles
**Learning:** In SwiftUI, `Toggle("", isOn: ...).labelsHidden()` results in VoiceOver reading 'Toggle, switch, off' with no context. Providing a label even when hidden like `Toggle("Enable Feature", isOn: ...).labelsHidden()` ensures VoiceOver reads the label while keeping the UI visually identical.
**Action:** Always provide descriptive string labels to `Toggle` views, even when combining them with `.labelsHidden()`.
