## 2025-04-14 - SwiftUI TimelineView and formatter overhead
**Learning:** Instantiating `DateFormatter` / `DateComponentsFormatter` inside a view that a `TimelineView` re-renders every second causes needless allocation on the main thread.
**Action:** Use the `Date.formatted()` API, or cache a single formatter outside the view body (see `RunningView.swift`).

## 2026-04-21 - Collection .lazy modifier
**Learning:** Chained `.filter { }.map { }` allocates an intermediate array. When the result is immediately consumed by a `Set` or `Dictionary` initializer, that allocation is pure overhead.
**Action:** Use `.lazy` when feeding a chain straight into a new collection — but only in code that runs often; for small, rare collections prefer the clearer form.
