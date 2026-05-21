## 2025-04-12 - Swift JSONEncoder/Decoder Overhead
**Learning:** Instantiating `JSONEncoder` and `JSONDecoder` inline is a common performance bottleneck in Swift due to the internal setup required for their configuration strategies. In this codebase, doing so in frequently called methods like `WCSessionConnectivity.broadcast` introduces unnecessary allocation overhead.
**Action:** Cache `JSONEncoder` and `JSONDecoder` instances as private constants (`let`) in long-lived services (like `WatchConnectivityService` and `UserDefaultsPersistence`). Since they are thread-safe when not mutated, this optimization perfectly respects the `@unchecked Sendable` annotations on those classes and eliminates the allocation cost on every broadcast or read/write operation.

## 2025-04-14 - SwiftUI TimelineView and DateFormatter Overhead
**Learning:** Instantiating `DateFormatter` inline within a SwiftUI view that is updated by a `TimelineView` (e.g., ticking every second) causes severe performance degradation and memory churn. `DateFormatter` allocation is notoriously expensive in Swift, and doing it in the render loop blocks the main thread unnecessarily.
**Action:** Replace inline `DateFormatter` instantiations in frequently-rendered views with the modern `Date.formatted()` API, or cache a single instance outside the view's body/render cycle.

## 2026-04-21 - Collection .lazy modifier
**Learning:** Chained collection operations like `.filter { ... }.map { ... }` allocate intermediate arrays. When the final result is immediately consumed by a `Set` or `Dictionary` initializer, this allocation is pure memory overhead.
**Action:** Use `.lazy` (e.g., `array.lazy.filter { ... }.map { ... }`) when feeding data into new collections to avoid intermediate array allocations and reduce memory churn.
## 2024-05-21 - Scope TimelineView tightly in SwiftUI
**Learning:** Wrapping an entire View like a VStack inside a TimelineView closure causes unnecessary re-evaluation of static layouts and text interpolations every tick. Specifically, expensive operations get called on every frame if inside the TimelineView closure.
**Action:** Scope TimelineView closures as tightly as possible around only the elements that need to animate or tick (like a CountdownRing).
