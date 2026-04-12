# Weekly Schedule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a weekly schedule that automatically starts and stops break timer sessions based on per-day-of-week time windows, with background task support and a local notification fallback.

**Architecture:** `ScheduleEvaluator` (pure logic, BlinkBreakCore) answers "should a session be active right now?" — `SessionController.reconcileOnLaunch()` consults it every second and calls its own `start()`/`stop()`. `ScheduleTaskManager` (app target) wraps `BGAppRefreshTask` for background schedule checks and schedules a start-time local notification as a reliable fallback.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing, BGTaskScheduler, UNUserNotificationCenter, UserDefaults

**Spec:** `docs/superpowers/specs/2026-04-11-weekly-schedule-design.md`

---

## File Structure

### New files — BlinkBreakCore

| File | Responsibility |
|------|---------------|
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/WeeklySchedule.swift` | `WeeklySchedule` + `DaySchedule` data model types |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/ScheduleEvaluator.swift` | `ScheduleEvaluating` protocol, `ScheduleEvaluator` (pure logic), `NoopScheduleEvaluator` |
| `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/WeeklyScheduleTests.swift` | Data model Codable round-trip tests |
| `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleEvaluatorTests.swift` | Evaluator logic tests (shouldBeActive, nextTransitionDate) |
| `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleIntegrationTests.swift` | SessionController + schedule auto-start/stop tests |
| `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockScheduleEvaluator.swift` | Mock for SessionController schedule tests |

### New files — App target

| File | Responsibility |
|------|---------------|
| `BlinkBreak/ScheduleTaskManager.swift` | BGAppRefreshTask registration/handling + start-time notification scheduling |
| `BlinkBreak/Views/ScheduleSection.swift` | Schedule UI block (master toggle + day list + expanding pickers) |
| `BlinkBreak/Views/Components/DayRow.swift` | Single day row component |
| `BlinkBreak/Views/Components/ScheduleStatusLabel.swift` | Status line above Start button |

### Modified files

| File | Changes |
|------|---------|
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift` | Add `manualStopDate: Date?` field |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Persistence.swift` | Add `loadSchedule()`/`saveSchedule()` to protocol + both implementations |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift` | Add `ScheduleEvaluating` dependency, extract `reconcileState()`, add `evaluateSchedule()`, `manualStopDate` in `stop()`, published `weeklySchedule` + `updateSchedule()` |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift` | Add `weeklySchedule` property + `updateSchedule()` method |
| `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift` | Add schedule UserDefaults key, notification category, BGTask identifier |
| `BlinkBreak/BlinkBreakApp.swift` | Wire `ScheduleEvaluator`, `ScheduleTaskManager`, observe schedule changes |
| `BlinkBreak/AppDelegate.swift` | Register BGTask, register schedule notification category |
| `BlinkBreak/Views/IdleView.swift` | Integrate `ScheduleSection` + `ScheduleStatusLabel` |
| `BlinkBreak/Preview/PreviewSessionController.swift` | Add `weeklySchedule` + `updateSchedule()` stubs |
| `project.yml` | Add `BGTaskSchedulerPermittedIdentifiers` to Info.plist settings |

---

### Task 1: WeeklySchedule Data Model

**Files:**
- Create: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/WeeklySchedule.swift`
- Test: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/WeeklyScheduleTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/WeeklyScheduleTests.swift`:

```swift
//
//  WeeklyScheduleTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the WeeklySchedule and DaySchedule data model types.
//

import Testing
import Foundation
@testable import BlinkBreakCore

@Suite("WeeklySchedule — data model")
struct WeeklyScheduleTests {

    @Test("DaySchedule round-trips through JSON")
    func dayScheduleRoundTrip() throws {
        let day = DaySchedule(
            isEnabled: true,
            startTime: DateComponents(hour: 9, minute: 0),
            endTime: DateComponents(hour: 17, minute: 30)
        )
        let data = try JSONEncoder().encode(day)
        let decoded = try JSONDecoder().decode(DaySchedule.self, from: data)
        #expect(decoded == day)
    }

    @Test("WeeklySchedule round-trips through JSON")
    func weeklyScheduleRoundTrip() throws {
        let schedule = WeeklySchedule(
            isEnabled: true,
            days: [
                2: DaySchedule(isEnabled: true,
                               startTime: DateComponents(hour: 9, minute: 0),
                               endTime: DateComponents(hour: 17, minute: 0)),
                7: DaySchedule(isEnabled: false,
                               startTime: DateComponents(hour: 10, minute: 0),
                               endTime: DateComponents(hour: 14, minute: 0)),
            ]
        )
        let data = try JSONEncoder().encode(schedule)
        let decoded = try JSONDecoder().decode(WeeklySchedule.self, from: data)
        #expect(decoded == schedule)
    }

    @Test("WeeklySchedule.default has Mon-Fri 9-5 enabled, Sat-Sun disabled")
    func defaultSchedule() {
        let schedule = WeeklySchedule.default
        #expect(schedule.isEnabled == true)

        // Mon(2) through Fri(6) enabled 9:00-17:00
        for weekday in 2...6 {
            let day = schedule.days[weekday]
            #expect(day != nil)
            #expect(day?.isEnabled == true)
            #expect(day?.startTime.hour == 9)
            #expect(day?.startTime.minute == 0)
            #expect(day?.endTime.hour == 17)
            #expect(day?.endTime.minute == 0)
        }

        // Sun(1) and Sat(7) disabled
        for weekday in [1, 7] {
            let day = schedule.days[weekday]
            #expect(day != nil)
            #expect(day?.isEnabled == false)
        }
    }

    @Test("WeeklySchedule.empty has master toggle off")
    func emptySchedule() {
        let schedule = WeeklySchedule.empty
        #expect(schedule.isEnabled == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/test.sh`
Expected: Compilation error — `DaySchedule` and `WeeklySchedule` not found.

- [ ] **Step 3: Write the implementation**

Create `Packages/BlinkBreakCore/Sources/BlinkBreakCore/WeeklySchedule.swift`:

```swift
//
//  WeeklySchedule.swift
//  BlinkBreakCore
//
//  Data model for the weekly auto-start/stop schedule. Each day of the week can have
//  an independent start and end time. The master toggle enables/disables the entire
//  schedule without losing per-day configuration.
//
//  Times are stored as DateComponents with .hour and .minute only. Days are keyed by
//  Foundation weekday integers (1 = Sunday, 7 = Saturday) to match Calendar APIs.
//
//  Flutter analogue: a plain Dart data class with fromJson/toJson, stored in SharedPreferences.
//

import Foundation

/// Configuration for a single day's auto-start/stop window.
public struct DaySchedule: Codable, Equatable, Sendable {
    /// Whether this day is active in the schedule.
    public var isEnabled: Bool

    /// Start time (hour + minute). Session auto-starts at this time.
    public var startTime: DateComponents

    /// End time (hour + minute). Session auto-stops at this time.
    /// Must be after startTime within the same day (no midnight-crossing in V1).
    public var endTime: DateComponents

    public init(isEnabled: Bool, startTime: DateComponents, endTime: DateComponents) {
        self.isEnabled = isEnabled
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// The full weekly schedule configuration.
public struct WeeklySchedule: Codable, Equatable, Sendable {
    /// Master toggle. When false, the schedule is fully inactive regardless of per-day settings.
    public var isEnabled: Bool

    /// Per-day schedule, keyed by Foundation weekday (1 = Sunday ... 7 = Saturday).
    public var days: [Int: DaySchedule]

    public init(isEnabled: Bool, days: [Int: DaySchedule]) {
        self.isEnabled = isEnabled
        self.days = days
    }

    /// Sensible default: Mon–Fri 9:00 AM – 5:00 PM enabled, Sat–Sun disabled.
    public static let `default`: WeeklySchedule = {
        var days: [Int: DaySchedule] = [:]
        let workday = DaySchedule(
            isEnabled: true,
            startTime: DateComponents(hour: 9, minute: 0),
            endTime: DateComponents(hour: 17, minute: 0)
        )
        let weekend = DaySchedule(
            isEnabled: false,
            startTime: DateComponents(hour: 9, minute: 0),
            endTime: DateComponents(hour: 17, minute: 0)
        )
        for weekday in 2...6 { days[weekday] = workday }
        days[1] = weekend
        days[7] = weekend
        return WeeklySchedule(isEnabled: true, days: days)
    }()

    /// Empty schedule with master toggle off. Used when no schedule has been configured.
    public static let empty = WeeklySchedule(isEnabled: false, days: [:])
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/test.sh`
Expected: All tests pass including the new WeeklyScheduleTests.

- [ ] **Step 5: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/WeeklySchedule.swift \
       Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/WeeklyScheduleTests.swift
git commit -m "feat(schedule): add WeeklySchedule and DaySchedule data model"
```

---

### Task 2: Add manualStopDate to SessionRecord

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift`
- Test: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift` (add tests)

- [ ] **Step 1: Write the failing tests**

Add to the end of `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift`:

```swift
    @Test("SessionRecord without manualStopDate decodes cleanly (backward compat)")
    func sessionRecordManualStopBackwardCompat() throws {
        let legacyJSON = """
        {"sessionActive":true,"currentCycleId":"550E8400-E29B-41D4-A716-446655440000","cycleStartedAt":1700000000}
        """
        let data = Data(legacyJSON.utf8)
        let record = try JSONDecoder().decode(SessionRecord.self, from: data)
        #expect(record.sessionActive == true)
        #expect(record.manualStopDate == nil)
    }

    @Test("SessionRecord with manualStopDate round-trips through JSON")
    func sessionRecordManualStopDateRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var record = SessionRecord(
            sessionActive: true,
            currentCycleId: UUID(),
            cycleStartedAt: now
        )
        record.manualStopDate = now.addingTimeInterval(3600)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
        #expect(decoded.manualStopDate == record.manualStopDate)
    }

    @Test("SessionRecord.idle has nil manualStopDate")
    func sessionRecordIdleManualStopDate() {
        #expect(SessionRecord.idle.manualStopDate == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/test.sh`
Expected: Compilation error — `manualStopDate` not found on `SessionRecord`.

- [ ] **Step 3: Implement**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift`:

Add after line 38 (`public var lastUpdatedAt: Date?`):

```swift

    /// When the user last manually tapped Stop during a scheduled window.
    /// The ScheduleEvaluator checks this to suppress auto-restart for the
    /// remainder of that day's window. Optional for Codable backward compat.
    public var manualStopDate: Date?
```

Update the `init` (lines 40-52) to include the new parameter with a default:

```swift
    public init(
        sessionActive: Bool = false,
        currentCycleId: UUID? = nil,
        cycleStartedAt: Date? = nil,
        lookAwayStartedAt: Date? = nil,
        lastUpdatedAt: Date? = nil,
        manualStopDate: Date? = nil
    ) {
        self.sessionActive = sessionActive
        self.currentCycleId = currentCycleId
        self.cycleStartedAt = cycleStartedAt
        self.lookAwayStartedAt = lookAwayStartedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.manualStopDate = manualStopDate
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/test.sh`
Expected: All tests pass (existing + new).

- [ ] **Step 5: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionRecord.swift \
       Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift
git commit -m "feat(schedule): add manualStopDate to SessionRecord"
```

---

### Task 3: Schedule Persistence

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Persistence.swift`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift`
- Test: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift` (add tests)

- [ ] **Step 1: Write the failing tests**

Add to the end of `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift`:

```swift
    @Test("InMemoryPersistence loadSchedule returns nil when nothing saved")
    func loadScheduleDefaultNil() {
        let persistence = InMemoryPersistence()
        #expect(persistence.loadSchedule() == nil)
    }

    @Test("InMemoryPersistence schedule round-trips through save/load")
    func scheduleRoundTrip() {
        let persistence = InMemoryPersistence()
        let schedule = WeeklySchedule.default
        persistence.saveSchedule(schedule)
        let loaded = persistence.loadSchedule()
        #expect(loaded == schedule)
    }

    @Test("InMemoryPersistence clear does not affect schedule")
    func clearDoesNotAffectSchedule() {
        let persistence = InMemoryPersistence()
        persistence.saveSchedule(.default)
        persistence.clear()
        #expect(persistence.loadSchedule() == .default)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/test.sh`
Expected: Compilation error — `loadSchedule()` and `saveSchedule()` not found.

- [ ] **Step 3: Add schedule key to Constants**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift`, add after line 69 (`public static let sessionRecordKey`):

```swift

    /// UserDefaults key for the persisted weekly schedule. Separate from the session
    /// record so existing users upgrade cleanly (loadSchedule returns nil → no schedule).
    public static let weeklyScheduleKey = "BlinkBreak.WeeklySchedule"
```

- [ ] **Step 4: Add to PersistenceProtocol and implementations**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Persistence.swift`:

Add to `PersistenceProtocol` after line 28 (`func clear()`):

```swift

    /// Load the persisted weekly schedule. Returns nil if no schedule has been configured.
    func loadSchedule() -> WeeklySchedule?

    /// Persist the given weekly schedule.
    func saveSchedule(_ schedule: WeeklySchedule)
```

Add to `UserDefaultsPersistence` after the `clear()` method (after line 68):

```swift

    public func loadSchedule() -> WeeklySchedule? {
        guard let data = defaults.data(forKey: BlinkBreakConstants.weeklyScheduleKey) else { return nil }
        return try? JSONDecoder().decode(WeeklySchedule.self, from: data)
    }

    public func saveSchedule(_ schedule: WeeklySchedule) {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        defaults.set(data, forKey: BlinkBreakConstants.weeklyScheduleKey)
    }
```

Add to `InMemoryPersistence` — add a private property after line 79 (`private var record: SessionRecord`):

```swift
    private var schedule: WeeklySchedule?
```

Then add methods after the `clear()` method (after line 101):

```swift

    public func loadSchedule() -> WeeklySchedule? {
        lock.lock()
        defer { lock.unlock() }
        return schedule
    }

    public func saveSchedule(_ schedule: WeeklySchedule) {
        lock.lock()
        defer { lock.unlock() }
        self.schedule = schedule
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/Persistence.swift \
       Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift \
       Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/PersistenceTests.swift
git commit -m "feat(schedule): add schedule persistence to PersistenceProtocol"
```

---

### Task 4: ScheduleEvaluating Protocol + Mocks

**Files:**
- Create: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/ScheduleEvaluator.swift`
- Create: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockScheduleEvaluator.swift`

- [ ] **Step 1: Create the protocol, evaluator, and no-op default**

Create `Packages/BlinkBreakCore/Sources/BlinkBreakCore/ScheduleEvaluator.swift`:

```swift
//
//  ScheduleEvaluator.swift
//  BlinkBreakCore
//
//  Pure logic for weekly schedule evaluation. Answers two questions:
//  1. "Should a session be active right now?" (shouldBeActive)
//  2. "When is the next time the answer flips?" (nextTransitionDate)
//
//  Has zero dependencies on UIKit, notifications, or SessionController.
//  SessionController consults this during reconcileOnLaunch().
//
//  Flutter analogue: a plain Dart class with no Flutter imports, fully unit-testable.
//

import Foundation

/// Protocol for schedule evaluation. SessionController depends on this, not on the
/// concrete ScheduleEvaluator, so tests can inject a mock.
public protocol ScheduleEvaluating: Sendable {
    /// Returns true if the schedule says a session should be active at the given date.
    func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool

    /// Returns the next Date at which shouldBeActive would flip (start→stop or stop→start).
    /// Used to schedule the next BGAppRefreshTask. Returns nil if no days are enabled.
    func nextTransitionDate(from date: Date, calendar: Calendar) -> Date?
}

/// No-op evaluator that always returns false. Used as the default for SessionController
/// so existing code and tests that don't care about scheduling work without changes.
public struct NoopScheduleEvaluator: ScheduleEvaluating {
    public init() {}
    public func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool { false }
    public func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? { nil }
}

/// The real schedule evaluator. Reads the schedule from a closure (so it always gets
/// the latest persisted value) and applies pure date math.
public final class ScheduleEvaluator: ScheduleEvaluating, @unchecked Sendable {

    private let schedule: @Sendable () -> WeeklySchedule

    public init(schedule: @escaping @Sendable () -> WeeklySchedule) {
        self.schedule = schedule
    }

    public func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool {
        let sched = schedule()
        guard sched.isEnabled else { return false }

        let weekday = calendar.component(.weekday, from: date)
        guard let day = sched.days[weekday], day.isEnabled else { return false }

        guard let startHour = day.startTime.hour, let startMinute = day.startTime.minute,
              let endHour = day.endTime.hour, let endMinute = day.endTime.minute else {
            return false
        }

        let currentMinutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        guard currentMinutes >= startMinutes && currentMinutes < endMinutes else { return false }

        // Manual stop override: if the user stopped during today's window, don't auto-restart.
        if let stopDate = manualStopDate {
            let stopWeekday = calendar.component(.weekday, from: stopDate)
            if stopWeekday == weekday && calendar.isDate(stopDate, inSameDayAs: date) {
                let stopMinutes = calendar.component(.hour, from: stopDate) * 60
                    + calendar.component(.minute, from: stopDate)
                if stopMinutes >= startMinutes && stopMinutes < endMinutes {
                    return false
                }
            }
        }

        return true
    }

    public func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? {
        let sched = schedule()
        guard sched.isEnabled else { return nil }

        // Scan up to 8 days ahead (covers wrap-around to same weekday next week).
        for dayOffset in 0..<8 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: checkDate)
            guard let day = sched.days[weekday], day.isEnabled,
                  let startHour = day.startTime.hour, let startMinute = day.startTime.minute,
                  let endHour = day.endTime.hour, let endMinute = day.endTime.minute else {
                continue
            }

            // Build start and end Dates for this calendar day.
            var startComps = calendar.dateComponents([.year, .month, .day], from: checkDate)
            startComps.hour = startHour
            startComps.minute = startMinute
            startComps.second = 0
            guard let startDate = calendar.date(from: startComps) else { continue }

            var endComps = startComps
            endComps.hour = endHour
            endComps.minute = endMinute
            guard let endDate = calendar.date(from: endComps) else { continue }

            if date < startDate { return startDate }          // before window → next transition is start
            if date >= startDate && date < endDate { return endDate }  // inside window → next is end
            // past window → try next day
        }

        return nil
    }
}
```

- [ ] **Step 2: Create the mock**

Create `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockScheduleEvaluator.swift`:

```swift
//
//  MockScheduleEvaluator.swift
//  BlinkBreakCoreTests
//
//  Test mock for ScheduleEvaluating. Returns configurable stubbed values.
//

import Foundation
@testable import BlinkBreakCore

final class MockScheduleEvaluator: ScheduleEvaluating, @unchecked Sendable {

    var stubbedShouldBeActive: Bool = false
    var stubbedNextTransitionDate: Date?
    var shouldBeActiveCalls: [(date: Date, manualStopDate: Date?)] = []

    func shouldBeActive(at date: Date, manualStopDate: Date?, calendar: Calendar) -> Bool {
        shouldBeActiveCalls.append((date: date, manualStopDate: manualStopDate))
        return stubbedShouldBeActive
    }

    func nextTransitionDate(from date: Date, calendar: Calendar) -> Date? {
        stubbedNextTransitionDate
    }
}
```

- [ ] **Step 3: Verify everything compiles**

Run: `./scripts/test.sh`
Expected: All existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/ScheduleEvaluator.swift \
       Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/MockScheduleEvaluator.swift
git commit -m "feat(schedule): add ScheduleEvaluating protocol, evaluator, and mock"
```

---

### Task 5: ScheduleEvaluator shouldBeActive Tests

**Files:**
- Create: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleEvaluatorTests.swift`

- [ ] **Step 1: Write the tests**

Create `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleEvaluatorTests.swift`:

```swift
//
//  ScheduleEvaluatorTests.swift
//  BlinkBreakCoreTests
//
//  Tests for the pure schedule evaluation logic.
//

import Testing
import Foundation
@testable import BlinkBreakCore

@Suite("ScheduleEvaluator — shouldBeActive")
struct ScheduleEvaluatorShouldBeActiveTests {

    // Fixed calendar: GMT, Sunday = 1.
    let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        return cal
    }()

    /// Helper: build a Date for a given weekday, hour, minute in a known week.
    /// 2026-04-05 is Sunday (weekday 1), 2026-04-06 is Monday (weekday 2), etc.
    func date(weekday: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4
        comps.day = 5 + (weekday - 1) // Sun=5, Mon=6, ... Sat=11
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return calendar.date(from: comps)!
    }

    func evaluator(schedule: WeeklySchedule) -> ScheduleEvaluator {
        ScheduleEvaluator(schedule: { schedule })
    }

    @Test("Returns false when master toggle is off")
    func masterToggleOff() {
        var schedule = WeeklySchedule.default
        schedule.isEnabled = false
        let eval = evaluator(schedule: schedule)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 10, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == false)
    }

    @Test("Returns false for a disabled day")
    func disabledDay() {
        let eval = evaluator(schedule: .default) // Sat(7) disabled
        #expect(eval.shouldBeActive(at: date(weekday: 7, hour: 10, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == false)
    }

    @Test("Returns true within a day's window")
    func withinWindow() {
        let eval = evaluator(schedule: .default) // Mon 9:00-17:00
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 12, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == true)
    }

    @Test("Returns true at exactly the start time")
    func exactlyAtStart() {
        let eval = evaluator(schedule: .default)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 9, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == true)
    }

    @Test("Returns false at exactly the end time (exclusive)")
    func exactlyAtEnd() {
        let eval = evaluator(schedule: .default)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 17, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == false)
    }

    @Test("Returns false before the start time")
    func beforeStart() {
        let eval = evaluator(schedule: .default)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 8, minute: 59),
                                     manualStopDate: nil, calendar: calendar) == false)
    }

    @Test("Returns false after the end time")
    func afterEnd() {
        let eval = evaluator(schedule: .default)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 17, minute: 1),
                                     manualStopDate: nil, calendar: calendar) == false)
    }

    @Test("Returns false when manualStopDate is within today's window")
    func manualStopOverride() {
        let eval = evaluator(schedule: .default)
        let stopDate = date(weekday: 2, hour: 14, minute: 0)  // stopped Mon 2pm
        let checkDate = date(weekday: 2, hour: 15, minute: 0) // checking Mon 3pm
        #expect(eval.shouldBeActive(at: checkDate, manualStopDate: stopDate,
                                     calendar: calendar) == false)
    }

    @Test("manualStopDate from yesterday is ignored")
    func manualStopYesterdayIgnored() {
        let eval = evaluator(schedule: .default)
        let stopDate = date(weekday: 2, hour: 14, minute: 0) // Mon 2pm
        let checkDate = date(weekday: 3, hour: 10, minute: 0) // Tue 10am
        #expect(eval.shouldBeActive(at: checkDate, manualStopDate: stopDate,
                                     calendar: calendar) == true)
    }

    @Test("manualStopDate outside today's window is ignored")
    func manualStopOutsideWindowIgnored() {
        let eval = evaluator(schedule: .default)
        let stopDate = date(weekday: 2, hour: 7, minute: 0)  // Mon 7am (before 9am)
        let checkDate = date(weekday: 2, hour: 10, minute: 0) // Mon 10am
        #expect(eval.shouldBeActive(at: checkDate, manualStopDate: stopDate,
                                     calendar: calendar) == true)
    }

    @Test("Returns false when day has no entry in schedule")
    func missingDayEntry() {
        let schedule = WeeklySchedule(isEnabled: true, days: [:])
        let eval = evaluator(schedule: schedule)
        #expect(eval.shouldBeActive(at: date(weekday: 2, hour: 10, minute: 0),
                                     manualStopDate: nil, calendar: calendar) == false)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleEvaluatorTests.swift
git commit -m "test(schedule): add shouldBeActive evaluator tests"
```

---

### Task 6: ScheduleEvaluator nextTransitionDate Tests

**Files:**
- Modify: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleEvaluatorTests.swift`

- [ ] **Step 1: Add nextTransitionDate tests**

Append to `ScheduleEvaluatorTests.swift`:

```swift

@Suite("ScheduleEvaluator — nextTransitionDate")
struct ScheduleEvaluatorNextTransitionTests {

    let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        return cal
    }()

    /// 2026-04-05 is Sunday (weekday 1). Helper builds Dates in that week.
    func date(weekday: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4
        comps.day = 5 + (weekday - 1)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return calendar.date(from: comps)!
    }

    /// Build a Date for a specific calendar day/hour/minute.
    func absoluteDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return calendar.date(from: comps)!
    }

    func evaluator(schedule: WeeklySchedule) -> ScheduleEvaluator {
        ScheduleEvaluator(schedule: { schedule })
    }

    @Test("Finds next start when before today's window")
    func nextStartBeforeWindow() {
        let eval = evaluator(schedule: .default)
        let from = date(weekday: 2, hour: 7, minute: 0) // Mon 7am
        let next = eval.nextTransitionDate(from: from, calendar: calendar)
        #expect(next == date(weekday: 2, hour: 9, minute: 0)) // Mon 9am
    }

    @Test("Finds next end when inside today's window")
    func nextEndInsideWindow() {
        let eval = evaluator(schedule: .default)
        let from = date(weekday: 2, hour: 12, minute: 0) // Mon noon
        let next = eval.nextTransitionDate(from: from, calendar: calendar)
        #expect(next == date(weekday: 2, hour: 17, minute: 0)) // Mon 5pm
    }

    @Test("Skips disabled days to find next enabled start")
    func skipsDisabledDays() {
        let eval = evaluator(schedule: .default)
        // Fri 6pm → Sat disabled, Sun disabled → Mon 9am next week
        let from = date(weekday: 6, hour: 18, minute: 0) // Fri April 10, 6pm
        let next = eval.nextTransitionDate(from: from, calendar: calendar)
        // Next Monday is April 13
        #expect(next == absoluteDate(year: 2026, month: 4, day: 13, hour: 9, minute: 0))
    }

    @Test("Returns nil when no days are enabled")
    func noDaysEnabled() {
        let schedule = WeeklySchedule(isEnabled: true, days: [:])
        let eval = evaluator(schedule: schedule)
        #expect(eval.nextTransitionDate(from: date(weekday: 2, hour: 10, minute: 0),
                                         calendar: calendar) == nil)
    }

    @Test("Returns nil when master toggle is off")
    func masterToggleOff() {
        var schedule = WeeklySchedule.default
        schedule.isEnabled = false
        let eval = evaluator(schedule: schedule)
        #expect(eval.nextTransitionDate(from: date(weekday: 2, hour: 10, minute: 0),
                                         calendar: calendar) == nil)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleEvaluatorTests.swift
git commit -m "test(schedule): add nextTransitionDate evaluator tests"
```

---

### Task 7: SessionController Schedule Integration

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift`
- Modify: `BlinkBreak/Preview/PreviewSessionController.swift`
- Create: `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleIntegrationTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleIntegrationTests.swift`:

```swift
//
//  ScheduleIntegrationTests.swift
//  BlinkBreakCoreTests
//
//  Tests for SessionController's schedule-driven auto-start/stop behavior.
//  Uses MockScheduleEvaluator to stub the evaluator's responses.
//

import Testing
import Foundation
@testable import BlinkBreakCore

@MainActor
@Suite("SessionController — schedule integration")
struct ScheduleIntegrationTests {

    final class Fixture {
        let scheduler = MockNotificationScheduler()
        let connectivity = MockWatchConnectivity()
        let persistence = InMemoryPersistence()
        let alarm = MockSessionAlarm()
        let evaluator = MockScheduleEvaluator()
        let nowBox: NowBox
        let controller: SessionController

        init() {
            let box = NowBox(value: Date(timeIntervalSince1970: 1_700_000_000))
            self.nowBox = box
            self.controller = SessionController(
                scheduler: scheduler,
                connectivity: connectivity,
                persistence: persistence,
                alarm: alarm,
                scheduleEvaluator: evaluator,
                clock: { box.value }
            )
        }

        func advance(by seconds: TimeInterval) {
            nowBox.value = nowBox.value.addingTimeInterval(seconds)
        }
    }

    final class NowBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Date
        init(value: Date) { self.storage = value }
        var value: Date {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); defer { lock.unlock() }; storage = newValue }
        }
    }

    @Test("reconcileOnLaunch auto-starts when evaluator says active and state is idle")
    func autoStart() async {
        let f = Fixture()
        f.evaluator.stubbedShouldBeActive = true
        #expect(f.controller.state == .idle)

        await f.controller.reconcileOnLaunch()

        #expect(f.controller.state != .idle)
        #expect(f.persistence.load().sessionActive == true)
    }

    @Test("reconcileOnLaunch auto-stops when evaluator says inactive and state is running")
    func autoStop() async {
        let f = Fixture()
        f.controller.start()
        #expect(f.controller.state != .idle)

        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcileOnLaunch()

        #expect(f.controller.state == .idle)
    }

    @Test("reconcileOnLaunch does not auto-start when evaluator returns false")
    func noAutoStartWhenInactive() async {
        let f = Fixture()
        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcileOnLaunch()
        #expect(f.controller.state == .idle)
    }

    @Test("stop() sets manualStopDate when evaluator says within window")
    func stopSetsManualStopDate() {
        let f = Fixture()
        f.evaluator.stubbedShouldBeActive = true
        f.controller.start()
        f.controller.stop()
        #expect(f.persistence.load().manualStopDate != nil)
    }

    @Test("stop() does not set manualStopDate when evaluator says outside window")
    func stopNoManualStopDateOutsideWindow() {
        let f = Fixture()
        f.evaluator.stubbedShouldBeActive = false
        f.controller.start()
        f.controller.stop()
        #expect(f.persistence.load().manualStopDate == nil)
    }

    @Test("reconcileOnLaunch passes manualStopDate to evaluator")
    func passesManualStopDate() async {
        let f = Fixture()
        let stopDate = Date(timeIntervalSince1970: 1_699_999_000)
        var record = SessionRecord.idle
        record.manualStopDate = stopDate
        f.persistence.save(record)

        f.evaluator.stubbedShouldBeActive = false
        await f.controller.reconcileOnLaunch()

        #expect(f.evaluator.shouldBeActiveCalls.last?.manualStopDate == stopDate)
    }

    @Test("updateSchedule saves to persistence and updates published property")
    func updateSchedule() {
        let f = Fixture()
        let schedule = WeeklySchedule.default
        f.controller.updateSchedule(schedule)
        #expect(f.controller.weeklySchedule == schedule)
        #expect(f.persistence.loadSchedule() == schedule)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/test.sh`
Expected: Compilation errors — `scheduleEvaluator` param missing, `weeklySchedule`/`updateSchedule` missing from protocol.

- [ ] **Step 3: Modify SessionControllerProtocol**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift`, add before the closing `}` (before line 48):

```swift

    /// The current weekly schedule configuration.
    var weeklySchedule: WeeklySchedule { get }

    /// Update the weekly schedule. Saves to persistence and publishes the change.
    func updateSchedule(_ schedule: WeeklySchedule)
```

- [ ] **Step 4: Update PreviewSessionController**

In `BlinkBreak/Preview/PreviewSessionController.swift`, add a published property after the `state` property:

```swift
    @Published var weeklySchedule: WeeklySchedule = .empty
```

Add a method stub after `reconcileOnLaunch()`:

```swift
    func updateSchedule(_ schedule: WeeklySchedule) {
        weeklySchedule = schedule
    }
```

- [ ] **Step 5: Modify SessionController**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift`:

**A. Add published property** — after line 30 (`@Published public private(set) var state: SessionState = .idle`):

```swift
    @Published public private(set) var weeklySchedule: WeeklySchedule = .empty
```

**B. Add dependency** — after line 38 (`private let clock: @Sendable () -> Date`):

```swift
    private let scheduleEvaluator: ScheduleEvaluating
```

**C. Update init signature** — replace the current init (lines 53-65) with:

```swift
    public init(
        scheduler: NotificationSchedulerProtocol,
        connectivity: WatchConnectivityProtocol,
        persistence: PersistenceProtocol,
        alarm: SessionAlarmProtocol,
        scheduleEvaluator: ScheduleEvaluating = NoopScheduleEvaluator(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scheduler = scheduler
        self.connectivity = connectivity
        self.persistence = persistence
        self.alarm = alarm
        self.scheduleEvaluator = scheduleEvaluator
        self.clock = clock
        self.weeklySchedule = persistence.loadSchedule() ?? .empty
    }
```

**D. Add updateSchedule** — after the `stop()` method:

```swift
    public func updateSchedule(_ schedule: WeeklySchedule) {
        persistence.saveSchedule(schedule)
        weeklySchedule = schedule
    }
```

**E. Modify stop()** — replace the body of `stop()` (lines 101-111) with:

```swift
    public func stop() {
        let now = clock()
        if let currentCycleId = persistence.load().currentCycleId {
            alarm.disarm(cycleId: currentCycleId)
        }
        scheduler.cancelAll()
        var idleRecord = SessionRecord.idle
        idleRecord.lastUpdatedAt = now
        if scheduleEvaluator.shouldBeActive(at: now, manualStopDate: nil, calendar: .current) {
            idleRecord.manualStopDate = now
        }
        persistence.save(idleRecord)
        state = .idle
        broadcastSnapshot(for: idleRecord)
    }
```

**F. Refactor reconcileOnLaunch** — extract the existing body into `reconcileState()` and add `evaluateSchedule()`. Replace `reconcileOnLaunch` (lines 184-246) with:

```swift
    public func reconcileOnLaunch() async {
        reconcileState()
        evaluateSchedule()
    }

    /// Rebuilds the in-memory `state` from the persisted record + pending notifications +
    /// the current clock. Never trusts in-memory state.
    private func reconcileState() {
        let record = persistence.load()
        let now = clock()

        // Case 1: no active session.
        guard record.sessionActive else {
            state = .idle
            return
        }

        // Case 2: corrupt record (sessionActive but missing fields) — recover to idle.
        guard let currentCycleId = record.currentCycleId,
              let cycleStartedAt = record.cycleStartedAt else {
            persistence.save(.idle)
            state = .idle
            return
        }

        // Case 3: if we're still inside the lookAway window, show lookAway.
        if let lookAwayStartedAt = record.lookAwayStartedAt {
            let lookAwayEnd = lookAwayStartedAt.addingTimeInterval(BlinkBreakConstants.lookAwayDuration)
            if now < lookAwayEnd {
                state = .lookAway(lookAwayStartedAt: lookAwayStartedAt)
                return
            }
            var cleared = record
            cleared.lookAwayStartedAt = nil
            persistence.save(cleared)
            broadcastSnapshot(for: cleared)
        }

        // Case 4: break time hasn't arrived yet → running.
        let breakFireTime = cycleStartedAt.addingTimeInterval(BlinkBreakConstants.breakInterval)
        if now < breakFireTime {
            state = .running(cycleStartedAt: cycleStartedAt)
            alarm.arm(cycleId: currentCycleId, fireDate: breakFireTime)
            return
        }

        // Case 5: break time has arrived without a look-away start → breakActive.
        state = .breakActive(cycleStartedAt: cycleStartedAt)
        alarm.arm(cycleId: currentCycleId, fireDate: breakFireTime)
    }

    /// Checks the schedule evaluator and auto-starts or auto-stops as needed.
    private func evaluateSchedule() {
        let record = persistence.load()
        let now = clock()
        let shouldBeActive = scheduleEvaluator.shouldBeActive(
            at: now,
            manualStopDate: record.manualStopDate,
            calendar: .current
        )
        if shouldBeActive && state == .idle {
            start()
        } else if !shouldBeActive && state.isActive {
            stop()
        }
    }
```

- [ ] **Step 6: Run tests**

Run: `./scripts/test.sh`
Expected: All tests pass (existing + new schedule integration tests).

- [ ] **Step 7: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionController.swift \
       Packages/BlinkBreakCore/Sources/BlinkBreakCore/SessionControllerProtocol.swift \
       BlinkBreak/Preview/PreviewSessionController.swift \
       Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/ScheduleIntegrationTests.swift
git commit -m "feat(schedule): integrate schedule evaluator into SessionController"
```

---

### Task 8: Constants + project.yml Updates

**Files:**
- Modify: `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift`
- Modify: `project.yml`

- [ ] **Step 1: Add remaining constants**

In `Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift`, add after the `weeklyScheduleKey` constant (added in Task 3):

```swift

    // MARK: - Schedule notification/task identifiers

    /// Notification category for the schedule start-time fallback notification.
    public static let scheduleCategoryId = "BLINKBREAK_SCHEDULE_CATEGORY"

    /// Action identifier for the "Start" button on schedule notifications.
    public static let scheduleStartActionId = "SCHEDULE_START"

    /// BGTaskScheduler task identifier for schedule checks.
    public static let scheduleTaskId = "com.tytaniumdev.BlinkBreak.scheduleCheck"
```

- [ ] **Step 2: Add BGTaskSchedulerPermittedIdentifiers to project.yml**

In `project.yml`, find the `BlinkBreak` target's `info` section (under the iOS app target settings) and add `BGTaskSchedulerPermittedIdentifiers`. Locate the `settings` block for the BlinkBreak target and add to `info`:

```yaml
        BGTaskSchedulerPermittedIdentifiers:
          - com.tytaniumdev.BlinkBreak.scheduleCheck
```

The exact insertion point depends on whether an `info` key already exists under the BlinkBreak target. If there's already an `info:` section under the target, add the key there. If not, add an `info:` section.

- [ ] **Step 3: Verify build**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/BlinkBreakCore/Sources/BlinkBreakCore/Constants.swift project.yml
git commit -m "feat(schedule): add schedule constants and BGTask permitted identifier"
```

---

### Task 9: UI Components — DayRow and ScheduleStatusLabel

**Files:**
- Create: `BlinkBreak/Views/Components/DayRow.swift`
- Create: `BlinkBreak/Views/Components/ScheduleStatusLabel.swift`

- [ ] **Step 1: Create DayRow component**

Create `BlinkBreak/Views/Components/DayRow.swift`:

```swift
//
//  DayRow.swift
//  BlinkBreak
//
//  A single row in the schedule day list. Shows the day name, time range
//  (tappable to expand picker), and an enable/disable toggle.
//
//  Stateless: takes all values as parameters. Parent manages the Binding.
//
//  Flutter analogue: a ListTile-style widget with a Switch trailing widget.
//

import SwiftUI
import BlinkBreakCore

struct DayRow: View {
    let dayName: String
    @Binding var daySchedule: DaySchedule
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("", isOn: $daySchedule.isEnabled)
                    .labelsHidden()
                    .tint(.green)
                    .scaleEffect(0.8)
                    .frame(width: 40)

                Text(dayName)
                    .font(.subheadline.weight(.medium))
                    .opacity(daySchedule.isEnabled ? 1.0 : 0.4)

                Spacer()

                if daySchedule.isEnabled {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(timeRangeText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    Text("Off")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))

            if isExpanded && daySchedule.isEnabled {
                VStack(spacing: 8) {
                    DatePicker("Start", selection: startTimeBinding,
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "en_US"))
                    DatePicker("End", selection: endTimeBinding,
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "en_US"))
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.03))
            }
        }
    }

    private var timeRangeText: String {
        let start = formatTime(daySchedule.startTime)
        let end = formatTime(daySchedule.endTime)
        return "\(start) – \(end)"
    }

    private func formatTime(_ components: DateComponents) -> String {
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    /// Bridge DateComponents ↔ Date for DatePicker binding.
    private var startTimeBinding: Binding<Date> {
        Binding(
            get: { dateFromComponents(daySchedule.startTime) },
            set: { newDate in
                let cal = Calendar.current
                let h = cal.component(.hour, from: newDate)
                let rawM = cal.component(.minute, from: newDate)
                let m = (rawM / 5) * 5 // snap to 5-min increments
                daySchedule.startTime = DateComponents(hour: h, minute: m)
            }
        )
    }

    private var endTimeBinding: Binding<Date> {
        Binding(
            get: { dateFromComponents(daySchedule.endTime) },
            set: { newDate in
                let cal = Calendar.current
                let h = cal.component(.hour, from: newDate)
                let rawM = cal.component(.minute, from: newDate)
                let m = (rawM / 5) * 5
                daySchedule.endTime = DateComponents(hour: h, minute: m)
            }
        )
    }

    private func dateFromComponents(_ comps: DateComponents) -> Date {
        let cal = Calendar.current
        var dc = cal.dateComponents([.year, .month, .day], from: Date())
        dc.hour = comps.hour ?? 0
        dc.minute = comps.minute ?? 0
        return cal.date(from: dc) ?? Date()
    }
}

#Preview("Enabled") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        DayRow(
            dayName: "Monday",
            daySchedule: .constant(DaySchedule(
                isEnabled: true,
                startTime: DateComponents(hour: 9, minute: 0),
                endTime: DateComponents(hour: 17, minute: 0)
            )),
            isExpanded: .constant(false)
        )
        .foregroundStyle(.white)
    }
}

#Preview("Disabled") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        DayRow(
            dayName: "Saturday",
            daySchedule: .constant(DaySchedule(
                isEnabled: false,
                startTime: DateComponents(hour: 9, minute: 0),
                endTime: DateComponents(hour: 17, minute: 0)
            )),
            isExpanded: .constant(false)
        )
        .foregroundStyle(.white)
    }
}

#Preview("Expanded") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        DayRow(
            dayName: "Monday",
            daySchedule: .constant(DaySchedule(
                isEnabled: true,
                startTime: DateComponents(hour: 9, minute: 0),
                endTime: DateComponents(hour: 17, minute: 0)
            )),
            isExpanded: .constant(true)
        )
        .foregroundStyle(.white)
    }
}
```

- [ ] **Step 2: Create ScheduleStatusLabel component**

Create `BlinkBreak/Views/Components/ScheduleStatusLabel.swift`:

```swift
//
//  ScheduleStatusLabel.swift
//  BlinkBreak
//
//  Shows schedule context above the Start button: "Scheduled: starts at 9:00 AM",
//  "Active until 5:00 PM", or nothing when the schedule is disabled.
//
//  Stateless: takes a WeeklySchedule and the current date, computes the label.
//
//  Flutter analogue: a simple Text widget driven by a computed string.
//

import SwiftUI
import BlinkBreakCore

struct ScheduleStatusLabel: View {
    let schedule: WeeklySchedule
    let now: Date

    var body: some View {
        if let text = statusText {
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityIdentifier("label.schedule.status")
        }
    }

    private var statusText: String? {
        guard schedule.isEnabled else { return nil }

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        guard let day = schedule.days[weekday], day.isEnabled,
              let startHour = day.startTime.hour, let startMinute = day.startTime.minute,
              let endHour = day.endTime.hour, let endMinute = day.endTime.minute else {
            // Not a scheduled day — find next scheduled start
            return nextStartText(from: now, calendar: cal)
        }

        let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        if currentMinutes < startMinutes {
            return "Starts at \(formatTime(hour: startHour, minute: startMinute))"
        } else if currentMinutes < endMinutes {
            return "Active until \(formatTime(hour: endHour, minute: endMinute))"
        } else {
            return nextStartText(from: now, calendar: cal)
        }
    }

    private func nextStartText(from date: Date, calendar cal: Calendar) -> String? {
        for dayOffset in 1...7 {
            guard let future = cal.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let wd = cal.component(.weekday, from: future)
            if let d = schedule.days[wd], d.isEnabled,
               let h = d.startTime.hour, let m = d.startTime.minute {
                let dayName = cal.shortWeekdaySymbols[wd - 1]
                return "Next: \(dayName) \(formatTime(hour: h, minute: m))"
            }
        }
        return nil
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}

#Preview("Before window") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        ScheduleStatusLabel(schedule: .default, now: Date())
    }
}
```

- [ ] **Step 3: Verify build compiles**

Run: `./scripts/build.sh` (or open Xcode previews to verify visually)
Expected: Build succeeds, previews render.

- [ ] **Step 4: Commit**

```bash
git add BlinkBreak/Views/Components/DayRow.swift \
       BlinkBreak/Views/Components/ScheduleStatusLabel.swift
git commit -m "feat(schedule): add DayRow and ScheduleStatusLabel UI components"
```

---

### Task 10: ScheduleSection View

**Files:**
- Create: `BlinkBreak/Views/ScheduleSection.swift`

- [ ] **Step 1: Create the schedule section**

Create `BlinkBreak/Views/ScheduleSection.swift`:

```swift
//
//  ScheduleSection.swift
//  BlinkBreak
//
//  The schedule configuration block that lives inline on IdleView. Contains the
//  master toggle, 7 day rows, and expanding time pickers.
//
//  Flutter analogue: a Column widget with a SwitchListTile header and a ListView of
//  day rows, backed by a ChangeNotifier that persists on every change.
//

import SwiftUI
import BlinkBreakCore

struct ScheduleSection<Controller: SessionControllerProtocol>: View {

    @ObservedObject var controller: Controller
    @State private var expandedDay: Int?

    /// Foundation weekday order: Sun=1 through Sat=7.
    private static var orderedWeekdays: [Int] { [2, 3, 4, 5, 6, 7, 1] } // Mon–Sun

    private let dayNames: [Int: String] = [
        1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Master toggle
            HStack {
                Text("Schedule")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("", isOn: masterToggleBinding)
                    .labelsHidden()
                    .tint(.green)
            }
            .padding(.bottom, 10)

            if controller.weeklySchedule.isEnabled {
                VStack(spacing: 1) {
                    ForEach(Self.orderedWeekdays, id: \.self) { weekday in
                        DayRow(
                            dayName: dayNames[weekday] ?? "",
                            daySchedule: dayBinding(for: weekday),
                            isExpanded: expandedBinding(for: weekday)
                        )
                        .clipShape(rowShape(for: weekday))
                    }
                }
            }
        }
        .accessibilityIdentifier("section.schedule")
    }

    private var masterToggleBinding: Binding<Bool> {
        Binding(
            get: { controller.weeklySchedule.isEnabled },
            set: { newValue in
                var schedule = controller.weeklySchedule
                if schedule.days.isEmpty && newValue {
                    // First enable — populate with defaults
                    schedule = .default
                } else {
                    schedule.isEnabled = newValue
                }
                controller.updateSchedule(schedule)
            }
        )
    }

    private func dayBinding(for weekday: Int) -> Binding<DaySchedule> {
        Binding(
            get: {
                controller.weeklySchedule.days[weekday] ?? DaySchedule(
                    isEnabled: false,
                    startTime: DateComponents(hour: 9, minute: 0),
                    endTime: DateComponents(hour: 17, minute: 0)
                )
            },
            set: { newDay in
                var schedule = controller.weeklySchedule
                schedule.days[weekday] = newDay
                controller.updateSchedule(schedule)
            }
        )
    }

    private func expandedBinding(for weekday: Int) -> Binding<Bool> {
        Binding(
            get: { expandedDay == weekday },
            set: { isExpanding in
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedDay = isExpanding ? weekday : nil
                }
            }
        )
    }

    /// Round the first and last rows in the list.
    private func rowShape(for weekday: Int) -> some Shape {
        let isFirst = weekday == Self.orderedWeekdays.first
        let isLast = weekday == Self.orderedWeekdays.last
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? 10 : 2,
            bottomLeadingRadius: isLast ? 10 : 2,
            bottomTrailingRadius: isLast ? 10 : 2,
            topTrailingRadius: isFirst ? 10 : 2
        )
    }
}

#Preview("Enabled") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        ScheduleSection(controller: PreviewSessionController.idle)
            .foregroundStyle(.white)
            .padding(24)
    }
}

#Preview("Disabled") {
    ZStack {
        Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea()
        ScheduleSection(controller: {
            let c = PreviewSessionController.idle
            c.weeklySchedule = .empty
            return c
        }())
            .foregroundStyle(.white)
            .padding(24)
    }
}
```

- [ ] **Step 2: Verify previews render**

Open in Xcode or run `./scripts/build.sh`.
Expected: Build succeeds. Previews show the schedule section with 7 day rows.

- [ ] **Step 3: Commit**

```bash
git add BlinkBreak/Views/ScheduleSection.swift
git commit -m "feat(schedule): add ScheduleSection view with master toggle and day list"
```

---

### Task 11: IdleView Integration

**Files:**
- Modify: `BlinkBreak/Views/IdleView.swift`

- [ ] **Step 1: Integrate ScheduleSection and ScheduleStatusLabel into IdleView**

Replace the body of `BlinkBreak/Views/IdleView.swift` (lines 16-36) with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "BlinkBreak")

            Text("20-20-20 Rule")
                .font(.title2.weight(.semibold))

            Text("Every 20 minutes, look at something 20 feet away for 20 seconds. Your eyes will thank you.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)

            ScheduleSection(controller: controller)
                .padding(.top, 12)

            Spacer()

            ScheduleStatusLabel(schedule: controller.weeklySchedule, now: Date())
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            PrimaryButton(title: "Start") {
                controller.start()
            }
            .accessibilityIdentifier("button.idle.start")
        }
        .padding(24)
    }
```

Update the preview to set the schedule:

```swift
#Preview {
    ZStack {
        CalmBackground()
        IdleView(controller: {
            let c = PreviewSessionController.idle
            c.weeklySchedule = .default
            return c
        }())
            .foregroundStyle(.white)
    }
}
```

- [ ] **Step 2: Verify in Xcode previews or simulator**

Start the dev server / open Xcode previews.
Expected: IdleView shows the schedule section between the explainer text and Start button.

- [ ] **Step 3: Run unit tests to check nothing broke**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add BlinkBreak/Views/IdleView.swift
git commit -m "feat(schedule): integrate schedule controls into IdleView"
```

---

### Task 12: ScheduleTaskManager — BGTask + Notification Fallback

**Files:**
- Create: `BlinkBreak/ScheduleTaskManager.swift`

- [ ] **Step 1: Create ScheduleTaskManager**

Create `BlinkBreak/ScheduleTaskManager.swift`:

```swift
//
//  ScheduleTaskManager.swift
//  BlinkBreak
//
//  Manages background schedule checks via BGAppRefreshTask and schedules a local
//  notification at the next start time as a reliable fallback. Lives in the app
//  target (not BlinkBreakCore) because BGTaskScheduler and UNUserNotificationCenter
//  are UIKit/UserNotifications APIs.
//
//  Flutter analogue: a platform channel handler that registers WorkManager tasks
//  and schedules AlarmManager alarms.
//

import BackgroundTasks
import UserNotifications
import BlinkBreakCore

final class ScheduleTaskManager {

    private let persistence: PersistenceProtocol
    private let evaluator: ScheduleEvaluating
    private let controllerProvider: @MainActor () -> SessionController?

    /// - Parameters:
    ///   - persistence: For reading the schedule.
    ///   - evaluator: For computing the next transition date.
    ///   - controllerProvider: Closure that returns the live SessionController on the main actor.
    ///     Used by the BGTask handler to trigger reconciliation.
    init(
        persistence: PersistenceProtocol,
        evaluator: ScheduleEvaluating,
        controllerProvider: @escaping @MainActor () -> SessionController?
    ) {
        self.persistence = persistence
        self.evaluator = evaluator
        self.controllerProvider = controllerProvider
    }

    // MARK: - BGTask Registration

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BlinkBreakConstants.scheduleTaskId,
            using: nil
        ) { [weak self] task in
            guard let self, let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundTask(bgTask)
        }
    }

    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task { @MainActor in
            if let controller = controllerProvider() {
                await controller.reconcileOnLaunch()
            }
            // Schedule the next BGTask before completing this one.
            scheduleNextBackgroundTask()
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Scheduling

    /// Call when the schedule changes or after a session auto-starts/stops.
    func reschedule() {
        scheduleNextBackgroundTask()
        scheduleStartTimeNotification()
    }

    private func scheduleNextBackgroundTask() {
        let nextDate = evaluator.nextTransitionDate(from: Date(), calendar: .current)
        let request = BGAppRefreshTaskRequest(identifier: BlinkBreakConstants.scheduleTaskId)
        request.earliestBeginDate = nextDate
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskScheduler.submit can fail if called too frequently or from a
            // simulator. Not actionable — the foreground reconciliation is the reliable path.
        }
    }

    private func scheduleStartTimeNotification() {
        let center = UNUserNotificationCenter.current()

        // Remove any previously scheduled start-time notification.
        center.removePendingNotificationRequests(withIdentifiers: ["schedule.start"])

        guard let schedule = persistence.loadSchedule(), schedule.isEnabled else { return }
        guard let nextStart = evaluator.nextTransitionDate(from: Date(), calendar: .current) else { return }

        // Only schedule a notification if the next transition is a start (not an end).
        // If we're currently inside a window, nextTransition is the end time — skip.
        let isInsideWindow = evaluator.shouldBeActive(at: Date(), manualStopDate: nil, calendar: .current)
        guard !isInsideWindow else { return }

        let content = UNMutableNotificationContent()
        content.title = "BlinkBreak"
        content.body = "Time for your scheduled eye break session."
        content.categoryIdentifier = BlinkBreakConstants.scheduleCategoryId
        content.interruptionLevel = .timeSensitive

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: nextStart
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "schedule.start", content: content, trigger: trigger)

        center.add(request) { _ in }
    }

    /// Cancel all schedule-related background tasks and notifications.
    func cancelAll() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BlinkBreakConstants.scheduleTaskId)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["schedule.start"])
    }
}
```

- [ ] **Step 2: Verify build**

Run: `./scripts/build.sh`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add BlinkBreak/ScheduleTaskManager.swift
git commit -m "feat(schedule): add ScheduleTaskManager for BGTask and notification fallback"
```

---

### Task 13: App Wiring — BlinkBreakApp + AppDelegate

**Files:**
- Modify: `BlinkBreak/BlinkBreakApp.swift`
- Modify: `BlinkBreak/AppDelegate.swift`

- [ ] **Step 1: Wire ScheduleEvaluator and ScheduleTaskManager into BlinkBreakApp**

In `BlinkBreak/BlinkBreakApp.swift`, update the `@StateObject` controller initialization (lines 37-46) to include the evaluator:

Replace the controller `@StateObject` initialization:

```swift
    @StateObject private var controller: SessionController = {
        let persistence = UserDefaultsPersistence()
        let evaluator = ScheduleEvaluator(schedule: {
            persistence.loadSchedule() ?? .empty
        })
        return SessionController(
            scheduler: UNNotificationScheduler(
                categories: SessionController.notificationCategories
            ),
            connectivity: WCSessionConnectivity(),
            persistence: persistence,
            alarm: NoopSessionAlarm(),
            scheduleEvaluator: evaluator
        )
    }()
```

Add a `ScheduleTaskManager` property after the controller:

```swift
    @State private var scheduleTaskManager: ScheduleTaskManager?
```

In the `body`'s `onAppear` block, after the existing setup (after activating connectivity), add:

```swift
            // Schedule task manager
            let manager = ScheduleTaskManager(
                persistence: UserDefaultsPersistence(),
                evaluator: ScheduleEvaluator(schedule: {
                    UserDefaultsPersistence().loadSchedule() ?? .empty
                }),
                controllerProvider: { [weak controller] in controller }
            )
            manager.registerBackgroundTask()
            manager.reschedule()
            scheduleTaskManager = manager
```

Add an `.onChange` observer on `controller.weeklySchedule` to the WindowGroup (after `onAppear`):

```swift
            .onChange(of: controller.weeklySchedule) { _, _ in
                scheduleTaskManager?.reschedule()
            }
```

- [ ] **Step 2: Register schedule notification category in AppDelegate**

In `BlinkBreak/AppDelegate.swift`, in the `didFinishLaunchingWithOptions` method (around line 24-30), the existing code sets UNUserNotificationCenter.delegate. The notification categories are registered elsewhere (via `UNNotificationScheduler.registerCategories`). Add the schedule category registration.

Actually, the categories are registered on the `UNNotificationScheduler` via `SessionController.notificationCategories`. A cleaner approach: add the schedule category to the same registration. But since that's in BlinkBreakCore and the schedule category is a constant there too, it should work.

In `AppDelegate.swift`, add to the `userNotificationCenter(_:didReceive:withCompletionHandler:)` method (around line 64-89), add handling for the schedule start action:

```swift
        // Handle schedule start notification tap
        if response.notification.request.content.categoryIdentifier == BlinkBreakConstants.scheduleCategoryId {
            Task { @MainActor in
                await controller?.reconcileOnLaunch()
            }
            completionHandler()
            return
        }
```

Add this before the existing break notification handling.

- [ ] **Step 3: Register the schedule notification category**

The schedule notification needs a category registered with UNUserNotificationCenter. In `BlinkBreakApp.swift`, after requesting notification authorization in `onAppear`, add:

```swift
            // Register schedule notification category
            let scheduleAction = UNNotificationAction(
                identifier: BlinkBreakConstants.scheduleStartActionId,
                title: "Open",
                options: [.foreground]
            )
            let scheduleCategory = UNNotificationCategory(
                identifier: BlinkBreakConstants.scheduleCategoryId,
                actions: [scheduleAction],
                intentIdentifiers: []
            )
            UNUserNotificationCenter.current().getNotificationCategories { existing in
                var categories = existing
                categories.insert(scheduleCategory)
                UNUserNotificationCenter.current().setNotificationCategories(categories)
            }
```

- [ ] **Step 4: Verify build**

Run: `./scripts/build.sh`
Expected: Build succeeds.

- [ ] **Step 5: Run unit tests**

Run: `./scripts/test.sh`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add BlinkBreak/BlinkBreakApp.swift BlinkBreak/AppDelegate.swift
git commit -m "feat(schedule): wire ScheduleEvaluator and ScheduleTaskManager into app"
```

---

### Task 14: Integration Tests

**Files:**
- Modify: `BlinkBreakUITests/BlinkBreakUITestsBase.swift`
- Create: `BlinkBreakUITests/ScheduleTests.swift`

- [ ] **Step 1: Add schedule accessibility identifiers to A11y enum**

In `BlinkBreakUITests/BlinkBreakUITestsBase.swift`, add to the `A11y` enum (around line 70-85):

```swift
        enum Schedule {
            static let section = "section.schedule"
            static let statusLabel = "label.schedule.status"
        }
```

- [ ] **Step 2: Create schedule integration tests**

Create `BlinkBreakUITests/ScheduleTests.swift`:

```swift
//
//  ScheduleTests.swift
//  BlinkBreakUITests
//
//  Integration tests for the weekly schedule feature. Verifies that the schedule
//  UI appears on the idle screen and that elements are accessible.
//

import XCTest

final class ScheduleTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForIntegrationTest()
    }

    func testIdleViewShowsScheduleSection() {
        // Idle view should show the schedule section
        let section = app.otherElements[A11y.Schedule.section]
        XCTAssertTrue(section.waitForExistence(timeout: 5),
                      "Schedule section should be visible on idle screen")
    }

    func testStartButtonExistsWithSchedule() {
        // Start button should still work even with schedule section present
        let startButton = app.buttons[A11y.Idle.startButton]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5),
                      "Start button should exist alongside schedule")
        startButton.tap()

        // Should transition to running
        let stopButton = app.buttons[A11y.Running.stopButton]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5),
                      "Should transition to running after tapping Start")
    }
}
```

- [ ] **Step 3: Run integration tests**

Run: `./scripts/test-integration.sh`
Expected: All tests pass (existing + new schedule tests).

- [ ] **Step 4: Commit**

```bash
git add BlinkBreakUITests/BlinkBreakUITestsBase.swift \
       BlinkBreakUITests/ScheduleTests.swift
git commit -m "test(schedule): add integration tests for schedule UI"
```

---

## Final Verification

After all tasks are complete:

- [ ] Run `./scripts/test.sh` — all unit tests pass
- [ ] Run `./scripts/lint.sh` — no BlinkBreakCore imports of SwiftUI/UIKit/WatchKit
- [ ] Run `./scripts/build.sh` — full build succeeds
- [ ] Run `./scripts/test-integration.sh` — all integration tests pass
- [ ] Open Xcode, run on simulator, verify:
  - Schedule section appears on idle screen
  - Master toggle enables/disables day rows
  - Tapping a time range expands the picker
  - Toggling a day on/off works
  - Start button still works
  - Status label shows schedule context
