## 2026-04-12 - VoiceOver and SwiftUI Toggles
**Learning:** In SwiftUI, `Toggle("", isOn: ...).labelsHidden()` results in VoiceOver reading 'Toggle, switch, off' with no context. Providing a label even when hidden like `Toggle("Enable Feature", isOn: ...).labelsHidden()` ensures VoiceOver reads the label while keeping the UI visually identical.
**Action:** Always provide descriptive string labels to `Toggle` views, even when combining them with `.labelsHidden()`.

## 2026-04-16 - Screen Readers and Countdown Durations
**Learning:** Screen readers poorly parse raw `MM:SS` duration strings (like "14:32") and will usually read them awkwardly as hours or text without context. Adding an accessibility label to a countdown using a cached `DateComponentsFormatter` (using `.unitsStyle = .full`) provides an accessible natural language string format for these durations.
**Action:** Always provide an `accessibilityValue` or `accessibilityLabel` backed by a semantic, natural language string to any duration or countdown text components (e.g. `14 minutes, 32 seconds`).
