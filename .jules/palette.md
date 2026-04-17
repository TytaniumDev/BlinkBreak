## 2024-05-18 - Improve accessibility of raw MM:SS countdown
**Learning:** Screen readers poorly parse raw `MM:SS` duration strings (like "14:32") and interpret them poorly. A natural language string is better for VoiceOver to read out.
**Action:** When displaying countdown timers that update dynamically, generate a readable duration string using `DateComponentsFormatter` (with `.unitsStyle = .full`) and pass it to VoiceOver with `.accessibilityValue`. Apply `.accessibilityElement(children: .ignore)` to hide the unreadable label.
