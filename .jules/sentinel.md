## 2026-04-26 - [Prevent concurrent feedback submissions]
**Vulnerability:** A submit button that starts an async network call can be tapped repeatedly while the call is in flight, sending duplicate reports.
**Learning:** Client-side debouncing protects the backend from duplicate work.
**Prevention:** Guard submission with a local `isSubmitting` flag that both disables the button and early-returns inside the action (see `FeedbackSheetView.submit()`). Bound free-text input (the feedback sheet caps messages at 1000 characters).
