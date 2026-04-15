## 2025-04-12 - Swift JSONEncoder/Decoder Overhead
**Learning:** Instantiating `JSONEncoder` and `JSONDecoder` inline is a common performance bottleneck in Swift due to the internal setup required for their configuration strategies. In this codebase, doing so in frequently called methods like `WCSessionConnectivity.broadcast` introduces unnecessary allocation overhead.
**Action:** Cache `JSONEncoder` and `JSONDecoder` instances as private constants (`let`) in long-lived services (like `WatchConnectivityService` and `UserDefaultsPersistence`). Since they are thread-safe when not mutated, this optimization perfectly respects the `@unchecked Sendable` annotations on those classes and eliminates the allocation cost on every broadcast or read/write operation.

## 2025-04-15 - Swift DateFormatter Overhead in Render Loops
**Learning:** Instantiating `DateFormatter` inline within frequently-rendered SwiftUI views (like those using `TimelineView`) causes significant allocation overhead, memory churn, and main thread blocking.
**Action:** Avoid inline `DateFormatter` instantiations in render loops. Instead, use the modern, internally-cached `Date.formatted()` API introduced in iOS 15 (e.g., `date.formatted(date: .omitted, time: .shortened)`) or cache a traditional `DateFormatter` instance outside the render loop.
