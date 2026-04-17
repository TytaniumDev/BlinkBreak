## 2025-04-12 - Swift JSONEncoder/Decoder Overhead
**Learning:** Instantiating `JSONEncoder` and `JSONDecoder` inline is a common performance bottleneck in Swift due to the internal setup required for their configuration strategies. In this codebase, doing so in frequently called methods like `WCSessionConnectivity.broadcast` introduces unnecessary allocation overhead.
**Action:** Cache `JSONEncoder` and `JSONDecoder` instances as private constants (`let`) in long-lived services (like `WatchConnectivityService` and `UserDefaultsPersistence`). Since they are thread-safe when not mutated, this optimization perfectly respects the `@unchecked Sendable` annotations on those classes and eliminates the allocation cost on every broadcast or read/write operation.

## 2025-04-17 - DateFormatter Instantiation in View Render Cycles
**Learning:** `TimelineView` redraws periodically (e.g., every second). Instantiating heavy objects like `DateFormatter` inline within computed properties read during these render cycles leads to rapid memory allocation and CPU churn, potentially blocking the main thread and draining the battery.
**Action:** Use modern Swift APIs like `Date.formatted()` which cache formatters internally, or declare the `DateFormatter` as a cached constant, keeping the view's render pass lightweight and highly efficient.
