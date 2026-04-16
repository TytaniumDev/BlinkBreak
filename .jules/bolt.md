## 2025-04-12 - Swift JSONEncoder/Decoder Overhead
**Learning:** Instantiating `JSONEncoder` and `JSONDecoder` inline is a common performance bottleneck in Swift due to the internal setup required for their configuration strategies. In this codebase, doing so in frequently called methods like `WCSessionConnectivity.broadcast` introduces unnecessary allocation overhead.
**Action:** Cache `JSONEncoder` and `JSONDecoder` instances as private constants (`let`) in long-lived services (like `WatchConnectivityService` and `UserDefaultsPersistence`). Since they are thread-safe when not mutated, this optimization perfectly respects the `@unchecked Sendable` annotations on those classes and eliminates the allocation cost on every broadcast or read/write operation.

## 2025-04-16 - DateFormatter inside TimelineView
**Learning:** Instantiating a `DateFormatter` is notoriously expensive in Swift. Doing it inside a computed property like `breakFireTimeFormatted` in a view that is constantly updated by a `TimelineView` (once every second) creates significant CPU overhead and memory churn.
**Action:** Always prefer the modern iOS 15+ API `Date.formatted()` for lightweight and performant date formatting inline, or cache standard formatters as static properties when supporting older versions.
