## 2025-04-12 - Swift JSONEncoder/Decoder Overhead
**Learning:** Instantiating `JSONEncoder` and `JSONDecoder` inline is a common performance bottleneck in Swift due to the internal setup required for their configuration strategies. In this codebase, doing so in frequently called methods like `WCSessionConnectivity.broadcast` introduces unnecessary allocation overhead.
**Action:** Cache `JSONEncoder` and `JSONDecoder` instances as private constants (`let`) in long-lived services (like `WatchConnectivityService` and `UserDefaultsPersistence`). Since they are thread-safe when not mutated, this optimization perfectly respects the `@unchecked Sendable` annotations on those classes and eliminates the allocation cost on every broadcast or read/write operation.

## 2025-04-14 - SwiftUI TimelineView and DateFormatter Overhead
**Learning:** Instantiating `DateFormatter` inline within a SwiftUI view that is updated by a `TimelineView` (e.g., ticking every second) causes severe performance degradation and memory churn. `DateFormatter` allocation is notoriously expensive in Swift, and doing it in the render loop blocks the main thread unnecessarily.
**Action:** Replace inline `DateFormatter` instantiations in frequently-rendered views with the modern `Date.formatted()` API, or cache a single instance outside the view's body/render cycle.

## 2026-04-21 - Collection .lazy modifier
**Learning:** Chained collection operations like `.filter { ... }.map { ... }` allocate intermediate arrays. When the final result is immediately consumed by a `Set` or `Dictionary` initializer, this allocation is pure memory overhead.
**Action:** Use `.lazy` (e.g., `array.lazy.filter { ... }.map { ... }`) when feeding data into new collections to avoid intermediate array allocations and reduce memory churn.

## 2025-05-08 - SwiftUI TimelineView Scoping
**Learning:** Wrapping an entire view containing static layouts (like `VStack`, `Text`, `Button`) in a `TimelineView` causes the entire view hierarchy to be re-evaluated on every tick (e.g., every second). This leads to unnecessary CPU usage, main thread blocking, and memory churn as static text interpolations and layout calculations are repeatedly executed.
**Action:** Always scope `TimelineView` closures as tightly as possible. Only the specific components that need to animate or update based on the ticking context (like a countdown ring or a changing text label) should be inside the `TimelineView`. Static UI elements should remain outside.
