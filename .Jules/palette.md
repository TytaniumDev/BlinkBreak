## 2026-04-12 - VoiceOver and SwiftUI Toggles
**Learning:** In SwiftUI, `Toggle("", isOn: ...).labelsHidden()` results in VoiceOver reading 'Toggle, switch, off' with no context. Providing a label even when hidden like `Toggle("Enable Feature", isOn: ...).labelsHidden()` ensures VoiceOver reads the label while keeping the UI visually identical.
**Action:** Always provide descriptive string labels to `Toggle` views, even when combining them with `.labelsHidden()`.

## 2024-04-14 - Accessible Countdown Timers
**Learning:** Screen readers like VoiceOver poorly parse strings formatted as `MM:SS` (e.g., "14:32" reads out as "fourteen thirty-two" or "one four colon three two"). Using `DateComponentsFormatter` with `.unitsStyle = .full` converts a raw `TimeInterval` directly into semantic natural language like "14 minutes, 32 seconds".
**Action:** When displaying a custom `MM:SS` countdown timer or raw duration text visually, always provide an `accessibilityValue` or `accessibilityLabel` backed by a semantic string formatted via `DateComponentsFormatter`. Cache the formatter to prevent frequent instantiations.
