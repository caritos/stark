# Stark Native Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the MVP of a native Swift/SwiftUI rewrite of Stark: a blended Events+Reminders agenda app backed by `.ics` files, replacing the Expo app on the same App Store listing.

**Architecture:** Two layers, mirroring `~/src/spool`: a pure-logic SwiftPM package (`StarkKit`) — models, `.ics` encode/decode, recurrence expansion, file storage — fully unit-tested with `swift test`, no simulator needed; and a thin SwiftUI app target (`Stark`) that wires `StarkKit` into an `ObservableObject` store and renders the agenda, month grid, add/edit forms.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Testing (`import Testing`), Swift Package Manager, `Foundation`/`FileManager` (no third-party dependencies).

**Spec:** `docs/superpowers/specs/2026-09-17-stark-native-rewrite-design.md`

## Global Constraints

- Bundle identifier: `com.caritos.todo-txt` (existing app — do not change; this ships as an update)
- No third-party dependencies anywhere in `ios/`
- `StarkKit` targets `.iOS(.v17)` and `.macOS(.v14)` so its tests run headlessly via `swift test`. The `Stark` app target's deployment target is iOS 17.0.
- Test framework is Swift Testing (`import Testing`, `@Test`, `#expect`) — never XCTest.
- The reminder/todo model type is named `Reminder`, never `Task` — `Task` collides with Swift's own concurrency type.
- Storage is two kinds of `.ics` file, both plain UTF-8 text in the app's local Documents directory (no iCloud APIs in this sub-project): `recurring.ics` holds every `Event`/`Reminder` that has a `RecurrenceRule` (always loaded in full); `YYYY-MM.ics` (e.g. `2026-09.ics`) holds non-recurring items for that month plus logged completion records. Never SQLite, never one file per item.
- Recurrence uses a `RRULE` subset (`FREQ`, `INTERVAL`, `BYDAY`, `BYMONTHDAY`, `COUNT`, `UNTIL`) plus `EXDATE`. No `RECURRENCE-ID` single-instance overrides.
- `Reminder.priority` is `Int?` on iCal's 1–9 scale.
- Completing one occurrence of a recurring `Reminder` adds that date to `exceptionDates` on the master (in `recurring.ics`) and appends a separate non-recurring completed `Reminder` to the relevant month file.
- SwiftUI views and other thin adapters over system frameworks are verified manually in the simulator, not unit-tested — matches `spool`'s established pattern.

---

## Part A — `StarkKit` package (fully TDD, headless via `swift test`)

### Task 1: Swift Package skeleton

**Files:**
- Create: `ios/Package.swift`
- Create: `ios/Sources/StarkKit/StarkKit.swift`
- Create: `ios/Tests/StarkKitTests/StarkKitTests.swift`

**Interfaces:**
- Produces: an empty `StarkKit` library target later tasks add files to, and a test target linked to `Testing` + `@testable import StarkKit`.

This is scaffolding — no TDD cycle, just enough to prove the toolchain works.

- [ ] **Step 1: Create the package manifest**

```swift
// ios/Package.swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StarkKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StarkKit", targets: ["StarkKit"])
    ],
    targets: [
        .target(name: "StarkKit"),
        .testTarget(name: "StarkKitTests", dependencies: ["StarkKit"])
    ]
)
```

- [ ] **Step 2: Create placeholder source and test files**

```swift
// ios/Sources/StarkKit/StarkKit.swift
// Root namespace file — implementation lands in DateMath.swift, Models/, ICS/, Planner/.
```

```swift
// ios/Tests/StarkKitTests/StarkKitTests.swift
import Testing

@Test("package builds and the test harness runs")
func packageLoads() {
    #expect(true)
}
```

- [ ] **Step 3: Verify the package builds and the sanity test passes**

Run: `cd ios && swift test`
Expected: 1 test passes (`packageLoads`).

- [ ] **Step 4: Commit**

```bash
cd ios && git add Package.swift Sources Tests
git commit -m "chore: scaffold StarkKit swift package"
```

---

### Task 2: `DateMath` and `YearMonth`

**Files:**
- Create: `ios/Sources/StarkKit/DateMath.swift`
- Test: `ios/Tests/StarkKitTests/DateMathTests.swift`

**Interfaces:**
- Produces: `DateMath.components(_:)`, `DateMath.isoDate(year:month0:day:)`, `DateMath.date(from:)`, `DateMath.isoDate(from:)`, `DateMath.addDays(_:_:)`, `DateMath.daysInMonth(year:month0:)`, `DateMath.weekday(year:month0:day:)`; `YearMonth` struct with `year: Int`, `month0: Int` (0-based, January = 0), `init(date: Date)`, `fileName: String` (e.g. `"2026-09.ics"`), `Comparable`.

- [ ] **Step 1: Write the failing tests**

```swift
// ios/Tests/StarkKitTests/DateMathTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("DateMath")
struct DateMathTests {
    @Test("addDays crosses a month boundary")
    func addDaysCrossesMonth() {
        #expect(DateMath.addDays("2026-01-30", 3) == "2026-02-02")
    }

    @Test("daysInMonth accounts for leap years")
    func daysInMonthLeapYear() {
        #expect(DateMath.daysInMonth(year: 2024, month0: 1) == 29)
        #expect(DateMath.daysInMonth(year: 2026, month0: 1) == 28)
    }

    @Test("weekday matches a known date")
    func weekdayKnownDate() {
        // 2026-09-17 is a Thursday (4 = Thu, 0 = Sun)
        #expect(DateMath.weekday(year: 2026, month0: 8, day: 17) == 4)
    }

    @Test("isoDate round-trips through date(from:)")
    func isoDateRoundTrip() {
        let date = DateMath.date(from: "2026-09-17")
        #expect(DateMath.isoDate(from: date) == "2026-09-17")
    }
}

@Suite("YearMonth")
struct YearMonthTests {
    @Test("fileName formats as YYYY-MM.ics")
    func fileNameFormat() {
        #expect(YearMonth(year: 2026, month0: 8).fileName == "2026-09.ics")
    }

    @Test("orders chronologically across a year boundary")
    func ordersAcrossYearBoundary() {
        #expect(YearMonth(year: 2025, month0: 11) < YearMonth(year: 2026, month0: 0))
    }

    @Test("normalizes an out-of-range month0 across a year boundary")
    func normalizesOutOfRangeMonth0() {
        // PlannerStore.start() computes center.month0 ± 1, which can land on -1 or 12.
        #expect(YearMonth(year: 2026, month0: -1) == YearMonth(year: 2025, month0: 11))
        #expect(YearMonth(year: 2026, month0: 12) == YearMonth(year: 2027, month0: 0))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && swift test --filter DateMathTests`
Expected: FAIL — `DateMath`/`YearMonth` do not exist.

- [ ] **Step 3: Write the implementation**

```swift
// ios/Sources/StarkKit/DateMath.swift
import Foundation

/// Dates as "YYYY-MM-DD" strings; month0 is 0-based (January == 0).
public enum DateMath {
    private static func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    public static func components(_ iso: String) -> (year: Int, month0: Int, day: Int) {
        let parts = iso.split(separator: "-")
        return (Int(parts[0])!, Int(parts[1])! - 1, Int(parts[2])!)
    }

    public static func isoDate(year: Int, month0: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month0 + 1, day)
    }

    public static func date(from iso: String) -> Date {
        let c = components(iso)
        return calendar().date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: 12))!
    }

    public static func isoDate(from date: Date) -> String {
        let c = calendar().dateComponents([.year, .month, .day], from: date)
        return isoDate(year: c.year!, month0: c.month! - 1, day: c.day!)
    }

    public static func addDays(_ iso: String, _ n: Int) -> String {
        let next = calendar().date(byAdding: .day, value: n, to: date(from: iso))!
        return isoDate(from: next)
    }

    public static func daysInMonth(year: Int, month0: Int) -> Int {
        let d = calendar().date(from: DateComponents(year: year, month: month0 + 1, day: 1))!
        return calendar().range(of: .day, in: .month, for: d)!.count
    }

    /// 0 = Sunday ... 6 = Saturday.
    public static func weekday(year: Int, month0: Int, day: Int) -> Int {
        let d = calendar().date(from: DateComponents(year: year, month: month0 + 1, day: day, hour: 12))!
        return calendar().component(.weekday, from: d) - 1
    }
}

public struct YearMonth: Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month0: Int

    public init(year: Int, month0: Int) {
        // Normalize an out-of-range month0 (e.g. -1 or 12, from a ±1 offset) into a real month/year.
        let normalized = ((month0 % 12) + 12) % 12
        let yearOffset = (month0 - normalized) / 12
        self.year = year + yearOffset
        self.month0 = normalized
    }

    public init(date: Date) {
        let c = DateMath.components(DateMath.isoDate(from: date))
        self.year = c.year
        self.month0 = c.month0
    }

    public var fileName: String {
        String(format: "%04d-%02d.ics", year, month0 + 1)
    }

    public var description: String { fileName }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month0) < (rhs.year, rhs.month0)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios && swift test --filter DateMathTests`
Expected: PASS, all 7 tests green (4 in `DateMathTests`, 3 in `YearMonthTests`).

- [ ] **Step 5: Commit**

```bash
cd ios && git add Sources/StarkKit/DateMath.swift Tests/StarkKitTests/DateMathTests.swift
git commit -m "feat: add DateMath and YearMonth utilities"
```

---

### Task 3: Data models

**Files:**
- Create: `ios/Sources/StarkKit/Models/Weekday.swift`
- Create: `ios/Sources/StarkKit/Models/RecurrenceRule.swift`
- Create: `ios/Sources/StarkKit/Models/Event.swift`
- Create: `ios/Sources/StarkKit/Models/Reminder.swift`
- Test: `ios/Tests/StarkKitTests/ModelsTests.swift`

**Interfaces:**
- Produces: `Weekday` (`Int` raw value, `.sunday...saturday`, 0-based matching `DateMath.weekday`); `RecurrenceRule` (`frequency: Frequency`, `interval: Int`, `byDay: [Weekday]?`, `byMonthDay: Int?`, `count: Int?`, `until: Date?`); `Event` (`id, title, notes, start, end, isAllDay, location, recurrence, exceptionDates`); `Reminder` (`id, title, notes, dueDate, isCompleted, completedDate, priority, recurrence, exceptionDates`). All `Equatable`, `Codable`, `Identifiable`.

These are plain data structs — no TDD cycle needed for their own sake. `ModelsTests` just locks in default-initializer values so later tasks can rely on them; the first real behavior tests arrive in Task 4.

- [ ] **Step 1: Write the models**

```swift
// ios/Sources/StarkKit/Models/Weekday.swift
public enum Weekday: Int, Codable, Equatable, CaseIterable, Sendable {
    case sunday = 0, monday, tuesday, wednesday, thursday, friday, saturday
}
```

```swift
// ios/Sources/StarkKit/Models/RecurrenceRule.swift
import Foundation

public struct RecurrenceRule: Equatable, Codable, Sendable {
    public enum Frequency: String, Codable, Equatable, Sendable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    public var interval: Int
    public var byDay: [Weekday]?
    public var byMonthDay: Int?
    public var count: Int?
    public var until: Date?

    public init(
        frequency: Frequency,
        interval: Int = 1,
        byDay: [Weekday]? = nil,
        byMonthDay: Int? = nil,
        count: Int? = nil,
        until: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.byDay = byDay
        self.byMonthDay = byMonthDay
        self.count = count
        self.until = until
    }
}
```

```swift
// ios/Sources/StarkKit/Models/Event.swift
import Foundation

public struct Event: Equatable, Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var notes: String?
    public var start: Date
    public var end: Date?
    public var isAllDay: Bool
    public var location: String?
    public var recurrence: RecurrenceRule?
    public var exceptionDates: [Date]

    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        start: Date,
        end: Date? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        recurrence: RecurrenceRule? = nil,
        exceptionDates: [Date] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.recurrence = recurrence
        self.exceptionDates = exceptionDates
    }
}
```

```swift
// ios/Sources/StarkKit/Models/Reminder.swift
import Foundation

// Named `Reminder`, not `Task` — `Task` is Swift's own concurrency type.
public struct Reminder: Equatable, Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var isCompleted: Bool
    public var completedDate: Date?
    public var priority: Int?
    public var recurrence: RecurrenceRule?
    public var exceptionDates: [Date]

    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completedDate: Date? = nil,
        priority: Int? = nil,
        recurrence: RecurrenceRule? = nil,
        exceptionDates: [Date] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.priority = priority
        self.recurrence = recurrence
        self.exceptionDates = exceptionDates
    }
}
```

- [ ] **Step 2: Write and run the lock-in test**

```swift
// ios/Tests/StarkKitTests/ModelsTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("Models")
struct ModelsTests {
    @Test("Event defaults to no recurrence, no exceptions, not all-day")
    func eventDefaults() {
        let event = Event(title: "Standup", start: Date())
        #expect(event.recurrence == nil)
        #expect(event.exceptionDates.isEmpty)
        #expect(event.isAllDay == false)
    }

    @Test("Reminder defaults to incomplete with no priority")
    func reminderDefaults() {
        let reminder = Reminder(title: "Call dentist")
        #expect(reminder.isCompleted == false)
        #expect(reminder.completedDate == nil)
        #expect(reminder.priority == nil)
    }
}
```

Run: `cd ios && swift test --filter ModelsTests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
cd ios && git add Sources/StarkKit/Models Tests/StarkKitTests/ModelsTests.swift
git commit -m "feat: add Event, Reminder, RecurrenceRule, Weekday models"
```

---

### Task 4: `OccurrenceExpander`

**Files:**
- Create: `ios/Sources/StarkKit/Planner/OccurrenceExpander.swift`
- Test: `ios/Tests/StarkKitTests/OccurrenceExpanderTests.swift`

**Interfaces:**
- Consumes: `RecurrenceRule`, `Event`, `Reminder`, `Weekday`
- Produces: `OccurrenceExpander.occurrences(anchor:rule:exceptionDates:in:) -> [Date]`; `OccurrenceExpander.expand(event:in:) -> [Date]`; `OccurrenceExpander.expand(reminder:in:) -> [Date]`

**Design note:** walks day-by-day from the anchor date, testing each day against the rule, rather than jumping by computed intervals. Simple and easy to verify correct; the multi-month windows this app displays make the extra iteration cost irrelevant.

- [ ] **Step 1: Write the failing tests**

```swift
// ios/Tests/StarkKitTests/OccurrenceExpanderTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("OccurrenceExpander")
struct OccurrenceExpanderTests {
    private let cal = Calendar(identifier: .gregorian)

    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }
    private func range(_ from: String, _ to: String) -> ClosedRange<Date> { d(from)...d(to) }

    @Test("non-recurring anchor appears only if inside the range")
    func nonRecurring() {
        let inRange = OccurrenceExpander.occurrences(anchor: d("2026-09-10"), rule: nil, exceptionDates: [], in: range("2026-09-01", "2026-09-30"))
        #expect(inRange == [d("2026-09-10")])

        let outOfRange = OccurrenceExpander.occurrences(anchor: d("2026-08-10"), rule: nil, exceptionDates: [], in: range("2026-09-01", "2026-09-30"))
        #expect(outOfRange.isEmpty)
    }

    @Test("daily every N days")
    func dailyInterval() {
        let rule = RecurrenceRule(frequency: .daily, interval: 2)
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-07"))
        #expect(dates == [d("2026-09-01"), d("2026-09-03"), d("2026-09-05"), d("2026-09-07")])
    }

    @Test("weekly on specific weekdays")
    func weeklyByDay() {
        // 2026-09-01 is a Tuesday; recur Mon/Wed/Fri.
        let rule = RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday, .friday])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-11"))
        #expect(dates == [d("2026-09-02"), d("2026-09-04"), d("2026-09-07"), d("2026-09-09"), d("2026-09-11")])
    }

    @Test("monthly clamps day-of-month to the shorter month")
    func monthlyClamped() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: 31)
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-01-31"), rule: rule, exceptionDates: [], in: range("2026-01-31", "2026-04-30"))
        #expect(dates == [d("2026-01-31"), d("2026-02-28"), d("2026-03-31"), d("2026-04-30")])
    }

    @Test("yearly clamps Feb 29 to Feb 28 in a non-leap year")
    func yearlyLeapClamp() {
        let rule = RecurrenceRule(frequency: .yearly)
        let dates = OccurrenceExpander.occurrences(anchor: d("2024-02-29"), rule: rule, exceptionDates: [], in: range("2025-01-01", "2026-12-31"))
        #expect(dates == [d("2025-02-28"), d("2026-02-28")])
    }

    @Test("until excludes occurrences after the cutoff")
    func untilCutoff() {
        let rule = RecurrenceRule(frequency: .daily, until: d("2026-09-03"))
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-10"))
        #expect(dates == [d("2026-09-01"), d("2026-09-02"), d("2026-09-03")])
    }

    @Test("count limits the total number of occurrences")
    func countLimit() {
        let rule = RecurrenceRule(frequency: .daily, count: 2)
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-10"))
        #expect(dates == [d("2026-09-01"), d("2026-09-02")])
    }

    @Test("exceptionDates skips a specific occurrence")
    func exceptionDatesSkip() {
        let rule = RecurrenceRule(frequency: .daily)
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [d("2026-09-02")], in: range("2026-09-01", "2026-09-03"))
        #expect(dates == [d("2026-09-01"), d("2026-09-03")])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && swift test --filter OccurrenceExpanderTests`
Expected: FAIL — `OccurrenceExpander` does not exist.

- [ ] **Step 3: Write the implementation**

```swift
// ios/Sources/StarkKit/Planner/OccurrenceExpander.swift
import Foundation

public enum OccurrenceExpander {
    public static func occurrences(
        anchor: Date,
        rule: RecurrenceRule?,
        exceptionDates: [Date],
        in range: ClosedRange<Date>
    ) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)

        guard let rule else {
            return range.contains(anchor) ? [anchor] : []
        }

        var results: [Date] = []
        var candidate = anchor
        var matchCount = 0

        while candidate <= range.upperBound {
            if let until = rule.until, candidate > until { break }

            if matches(candidate, anchor: anchor, rule: rule, calendar: calendar) {
                matchCount += 1
                if let count = rule.count, matchCount > count { break }
                if candidate >= range.lowerBound,
                   !exceptionDates.contains(where: { calendar.isDate($0, inSameDayAs: candidate) }) {
                    results.append(candidate)
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
            candidate = next
        }

        return results
    }

    public static func expand(event: Event, in range: ClosedRange<Date>) -> [Date] {
        occurrences(anchor: event.start, rule: event.recurrence, exceptionDates: event.exceptionDates, in: range)
    }

    public static func expand(reminder: Reminder, in range: ClosedRange<Date>) -> [Date] {
        guard let due = reminder.dueDate else { return [] }
        return occurrences(anchor: due, rule: reminder.recurrence, exceptionDates: reminder.exceptionDates, in: range)
    }

    private static func matches(_ date: Date, anchor: Date, rule: RecurrenceRule, calendar: Calendar) -> Bool {
        switch rule.frequency {
        case .daily:
            let days = calendar.dateComponents([.day], from: anchor, to: date).day ?? 0
            return days >= 0 && days % rule.interval == 0

        case .weekly:
            let weekday = Weekday(rawValue: calendar.component(.weekday, from: date) - 1)!
            let activeDays = rule.byDay ?? [Weekday(rawValue: calendar.component(.weekday, from: anchor) - 1)!]
            guard activeDays.contains(weekday) else { return false }
            let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
            let dateWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            let weeks = calendar.dateComponents([.weekOfYear], from: anchorWeekStart, to: dateWeekStart).weekOfYear ?? 0
            return weeks >= 0 && weeks % rule.interval == 0

        case .monthly:
            let anchorDay = rule.byMonthDay ?? calendar.component(.day, from: anchor)
            let expectedDay = min(anchorDay, calendar.range(of: .day, in: .month, for: date)!.count)
            guard calendar.component(.day, from: date) == expectedDay else { return false }
            let months = calendar.dateComponents([.month], from: anchor, to: date).month ?? 0
            return months >= 0 && months % rule.interval == 0

        case .yearly:
            let anchorParts = calendar.dateComponents([.month, .day], from: anchor)
            let expectedDay = min(anchorParts.day!, calendar.range(of: .day, in: .month, for: date)!.count)
            guard calendar.component(.month, from: date) == anchorParts.month,
                  calendar.component(.day, from: date) == expectedDay else { return false }
            let years = calendar.dateComponents([.year], from: anchor, to: date).year ?? 0
            return years >= 0 && years % rule.interval == 0
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios && swift test --filter OccurrenceExpanderTests`
Expected: PASS, all 8 tests green.

- [ ] **Step 5: Commit**

```bash
cd ios && git add Sources/StarkKit/Planner/OccurrenceExpander.swift Tests/StarkKitTests/OccurrenceExpanderTests.swift
git commit -m "feat: add OccurrenceExpander with daily/weekly/monthly/yearly recurrence"
```

---

### Task 5: `ICSSerializer`

**Files:**
- Create: `ios/Sources/StarkKit/ICS/ICSDateFormat.swift`
- Create: `ios/Sources/StarkKit/ICS/RRuleCodec.swift`
- Create: `ios/Sources/StarkKit/ICS/ICSSerializer.swift`
- Test: `ios/Tests/StarkKitTests/ICSSerializerTests.swift`

**Interfaces:**
- Produces: `ICSDateFormat.format(_:allDay:) -> String`, `ICSDateFormat.parse(_:) -> (date: Date, allDay: Bool)?`; `RRuleCodec.encode(_:) -> String`, `RRuleCodec.decode(_:) -> RecurrenceRule?`; `ICSSerializer.serialize(event:) -> String`, `ICSSerializer.serialize(reminder:) -> String`, `ICSSerializer.serialize(events:reminders:) -> String` (a full `VCALENDAR` document).

- [ ] **Step 1: Write the failing tests**

```swift
// ios/Tests/StarkKitTests/ICSSerializerTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("ICSSerializer")
struct ICSSerializerTests {
    @Test("serializes a timed event with RRULE")
    func serializesEventWithRecurrence() {
        let event = Event(
            id: "evt-1",
            title: "Standup",
            start: DateMath.date(from: "2026-09-17"),
            recurrence: RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday, .friday])
        )

        let text = ICSSerializer.serialize(event: event)

        #expect(text.contains("BEGIN:VEVENT"))
        #expect(text.contains("UID:evt-1"))
        #expect(text.contains("SUMMARY:Standup"))
        #expect(text.contains("RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"))
        #expect(text.contains("END:VEVENT"))
    }

    @Test("serializes a completed reminder with priority")
    func serializesCompletedReminder() {
        let reminder = Reminder(
            id: "rem-1",
            title: "Call dentist",
            dueDate: DateMath.date(from: "2026-09-20"),
            isCompleted: true,
            completedDate: DateMath.date(from: "2026-09-19"),
            priority: 1
        )

        let text = ICSSerializer.serialize(reminder: reminder)

        #expect(text.contains("BEGIN:VTODO"))
        #expect(text.contains("PRIORITY:1"))
        #expect(text.contains("STATUS:COMPLETED"))
        #expect(text.contains("END:VTODO"))
    }

    @Test("escapes commas, semicolons, and newlines in free text")
    func escapesSpecialCharacters() {
        let event = Event(title: "Lunch; drinks, then home\nlate", start: Date())
        let text = ICSSerializer.serialize(event: event)
        #expect(text.contains("SUMMARY:Lunch\\; drinks\\, then home\\nlate"))
    }

    @Test("wraps multiple items in one VCALENDAR document")
    func wholeFileWrapsMultipleItems() {
        let event = Event(title: "Standup", start: Date())
        let reminder = Reminder(title: "Call dentist")
        let text = ICSSerializer.serialize(events: [event], reminders: [reminder])
        #expect(text.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
        #expect(text.contains("BEGIN:VEVENT"))
        #expect(text.contains("BEGIN:VTODO"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && swift test --filter ICSSerializerTests`
Expected: FAIL — `ICSSerializer` does not exist.

- [ ] **Step 3: Write the implementation**

```swift
// ios/Sources/StarkKit/ICS/ICSDateFormat.swift
import Foundation

public enum ICSDateFormat {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = pattern
        return formatter
    }

    public static func format(_ date: Date, allDay: Bool) -> String {
        formatter(allDay ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss").string(from: date)
    }

    public static func parse(_ value: String) -> (date: Date, allDay: Bool)? {
        let cleaned = value.replacingOccurrences(of: "Z", with: "")
        if cleaned.count == 8 {
            guard let date = formatter("yyyyMMdd").date(from: cleaned) else { return nil }
            return (date, true)
        }
        guard let date = formatter("yyyyMMdd'T'HHmmss").date(from: cleaned) else { return nil }
        return (date, false)
    }
}
```

```swift
// ios/Sources/StarkKit/ICS/RRuleCodec.swift
import Foundation

public enum RRuleCodec {
    private static let dayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

    public static func encode(_ rule: RecurrenceRule) -> String {
        var parts = ["FREQ=\(rule.frequency.rawValue.uppercased())"]
        if rule.interval != 1 { parts.append("INTERVAL=\(rule.interval)") }
        if let byDay = rule.byDay, !byDay.isEmpty {
            parts.append("BYDAY=" + byDay.map { dayCodes[$0.rawValue] }.joined(separator: ","))
        }
        if let byMonthDay = rule.byMonthDay { parts.append("BYMONTHDAY=\(byMonthDay)") }
        if let count = rule.count { parts.append("COUNT=\(count)") }
        if let until = rule.until { parts.append("UNTIL=\(ICSDateFormat.format(until, allDay: true))") }
        return parts.joined(separator: ";")
    }

    public static func decode(_ value: String) -> RecurrenceRule? {
        var frequency: RecurrenceRule.Frequency?
        var interval = 1
        var byDay: [Weekday]?
        var byMonthDay: Int?
        var count: Int?
        var until: Date?

        for pair in value.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "FREQ": frequency = RecurrenceRule.Frequency(rawValue: kv[1].lowercased())
            case "INTERVAL": interval = Int(kv[1]) ?? 1
            case "BYDAY": byDay = kv[1].split(separator: ",").compactMap { code in
                dayCodes.firstIndex(of: String(code)).flatMap { Weekday(rawValue: $0) }
            }
            case "BYMONTHDAY": byMonthDay = Int(kv[1])
            case "COUNT": count = Int(kv[1])
            case "UNTIL": until = ICSDateFormat.parse(String(kv[1]))?.date
            default: break
            }
        }
        guard let frequency else { return nil }
        return RecurrenceRule(frequency: frequency, interval: interval, byDay: byDay, byMonthDay: byMonthDay, count: count, until: until)
    }
}
```

```swift
// ios/Sources/StarkKit/ICS/ICSSerializer.swift
import Foundation

public enum ICSSerializer {
    public static func serialize(event: Event) -> String {
        var lines = ["BEGIN:VEVENT", "UID:\(event.id)", "SUMMARY:\(escape(event.title))"]
        lines.append("DTSTART\(dateParam(event.isAllDay)):\(ICSDateFormat.format(event.start, allDay: event.isAllDay))")
        if let end = event.end {
            lines.append("DTEND\(dateParam(event.isAllDay)):\(ICSDateFormat.format(end, allDay: event.isAllDay))")
        }
        if let notes = event.notes { lines.append("DESCRIPTION:\(escape(notes))") }
        if let location = event.location { lines.append("LOCATION:\(escape(location))") }
        if let recurrence = event.recurrence { lines.append("RRULE:\(RRuleCodec.encode(recurrence))") }
        for exdate in event.exceptionDates {
            lines.append("EXDATE\(dateParam(event.isAllDay)):\(ICSDateFormat.format(exdate, allDay: event.isAllDay))")
        }
        lines.append("END:VEVENT")
        return lines.joined(separator: "\r\n")
    }

    public static func serialize(reminder: Reminder) -> String {
        var lines = ["BEGIN:VTODO", "UID:\(reminder.id)", "SUMMARY:\(escape(reminder.title))"]
        if let due = reminder.dueDate { lines.append("DUE:\(ICSDateFormat.format(due, allDay: false))") }
        if let notes = reminder.notes { lines.append("DESCRIPTION:\(escape(notes))") }
        if let priority = reminder.priority { lines.append("PRIORITY:\(priority)") }
        lines.append("STATUS:\(reminder.isCompleted ? "COMPLETED" : "NEEDS-ACTION")")
        if let completed = reminder.completedDate { lines.append("COMPLETED:\(ICSDateFormat.format(completed, allDay: false))") }
        if let recurrence = reminder.recurrence { lines.append("RRULE:\(RRuleCodec.encode(recurrence))") }
        for exdate in reminder.exceptionDates {
            lines.append("EXDATE:\(ICSDateFormat.format(exdate, allDay: false))")
        }
        lines.append("END:VTODO")
        return lines.joined(separator: "\r\n")
    }

    public static func serialize(events: [Event], reminders: [Reminder]) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Stark//EN"]
        lines.append(contentsOf: events.map(serialize(event:)))
        lines.append(contentsOf: reminders.map(serialize(reminder:)))
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func dateParam(_ allDay: Bool) -> String { allDay ? ";VALUE=DATE" : "" }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios && swift test --filter ICSSerializerTests`
Expected: PASS, all 4 tests green.

- [ ] **Step 5: Commit**

```bash
cd ios && git add Sources/StarkKit/ICS/ICSDateFormat.swift Sources/StarkKit/ICS/RRuleCodec.swift Sources/StarkKit/ICS/ICSSerializer.swift Tests/StarkKitTests/ICSSerializerTests.swift
git commit -m "feat: add ICSSerializer, RRuleCodec, ICSDateFormat"
```

---

### Task 6: `ICSParser`

**Files:**
- Create: `ios/Sources/StarkKit/ICS/ICSParser.swift`
- Test: `ios/Tests/StarkKitTests/ICSParserTests.swift`

**Interfaces:**
- Consumes: `ICSDateFormat.parse(_:)`, `RRuleCodec.decode(_:)`, `Event`, `Reminder`
- Produces: `ICSParseResult` (`events: [Event]`, `reminders: [Reminder]`, `warnings: [String]`); `ICSParser.parse(_:) -> ICSParseResult`

- [ ] **Step 1: Write the failing tests**

```swift
// ios/Tests/StarkKitTests/ICSParserTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("ICSParser")
struct ICSParserTests {
    @Test("round-trips an event with recurrence through serialize/parse")
    func roundTripsEvent() {
        let original = Event(
            id: "evt-1",
            title: "Standup",
            start: DateMath.date(from: "2026-09-17"),
            recurrence: RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday, .friday]),
            exceptionDates: [DateMath.date(from: "2026-09-23")]
        )

        let text = ICSSerializer.serialize(events: [original], reminders: [])
        let result = ICSParser.parse(text)

        #expect(result.events.count == 1)
        #expect(result.events[0].id == "evt-1")
        #expect(result.events[0].title == "Standup")
        #expect(result.events[0].recurrence == original.recurrence)
        #expect(result.events[0].exceptionDates.count == 1)
        #expect(result.warnings.isEmpty)
    }

    @Test("round-trips a completed reminder with priority")
    func roundTripsReminder() {
        let original = Reminder(
            id: "rem-1",
            title: "Call dentist",
            dueDate: DateMath.date(from: "2026-09-20"),
            isCompleted: true,
            completedDate: DateMath.date(from: "2026-09-19"),
            priority: 1
        )

        let text = ICSSerializer.serialize(events: [], reminders: [original])
        let result = ICSParser.parse(text)

        #expect(result.reminders.count == 1)
        #expect(result.reminders[0].isCompleted == true)
        #expect(result.reminders[0].priority == 1)
    }

    @Test("skips a malformed block and still parses its valid siblings")
    func skipsMalformedBlock() {
        let text = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VTODO
        UID:bad-1
        END:VTODO
        BEGIN:VTODO
        UID:good-1
        SUMMARY:Buy milk
        STATUS:NEEDS-ACTION
        END:VTODO
        END:VCALENDAR
        """

        let result = ICSParser.parse(text)

        #expect(result.reminders.count == 1)
        #expect(result.reminders[0].id == "good-1")
        #expect(result.warnings.count == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && swift test --filter ICSParserTests`
Expected: FAIL — `ICSParser`/`ICSParseResult` do not exist.

- [ ] **Step 3: Write the implementation**

```swift
// ios/Sources/StarkKit/ICS/ICSParser.swift
import Foundation

public struct ICSParseResult {
    public let events: [Event]
    public let reminders: [Reminder]
    public let warnings: [String]
}

public enum ICSParser {
    public static func parse(_ content: String) -> ICSParseResult {
        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        var events: [Event] = []
        var reminders: [Reminder] = []
        var warnings: [String] = []
        var currentBlock: [String]?
        var currentKind: String?

        for line in lines {
            if line == "BEGIN:VEVENT" || line == "BEGIN:VTODO" {
                currentBlock = []
                currentKind = line == "BEGIN:VEVENT" ? "VEVENT" : "VTODO"
                continue
            }
            if line == "END:VEVENT" || line == "END:VTODO" {
                defer { currentBlock = nil; currentKind = nil }
                guard let block = currentBlock, let kind = currentKind else { continue }
                if kind == "VEVENT" {
                    if let event = parseEvent(block) {
                        events.append(event)
                    } else {
                        warnings.append("skipped malformed VEVENT block: missing UID/SUMMARY/DTSTART")
                    }
                } else {
                    if let reminder = parseReminder(block) {
                        reminders.append(reminder)
                    } else {
                        warnings.append("skipped malformed VTODO block: missing UID/SUMMARY")
                    }
                }
                continue
            }
            currentBlock?.append(line)
        }

        return ICSParseResult(events: events, reminders: reminders, warnings: warnings)
    }

    private static func properties(_ block: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in block {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].split(separator: ";").first.map(String.init) ?? ""
            result[key] = String(line[line.index(after: colon)...])
        }
        return result
    }

    private static func exceptionDates(_ block: [String]) -> [Date] {
        block.filter { $0.hasPrefix("EXDATE") }.compactMap { line -> Date? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return ICSDateFormat.parse(String(line[line.index(after: colon)...]))?.date
        }
    }

    private static func parseEvent(_ block: [String]) -> Event? {
        let props = properties(block)
        guard let id = props["UID"], let title = props["SUMMARY"],
              let dtstartRaw = props["DTSTART"],
              let (start, allDay) = ICSDateFormat.parse(dtstartRaw) else { return nil }

        return Event(
            id: id,
            title: unescape(title),
            notes: props["DESCRIPTION"].map(unescape),
            start: start,
            end: props["DTEND"].flatMap { ICSDateFormat.parse($0)?.date },
            isAllDay: allDay,
            location: props["LOCATION"].map(unescape),
            recurrence: props["RRULE"].flatMap(RRuleCodec.decode),
            exceptionDates: exceptionDates(block)
        )
    }

    private static func parseReminder(_ block: [String]) -> Reminder? {
        let props = properties(block)
        guard let id = props["UID"], let title = props["SUMMARY"] else { return nil }

        return Reminder(
            id: id,
            title: unescape(title),
            notes: props["DESCRIPTION"].map(unescape),
            dueDate: props["DUE"].flatMap { ICSDateFormat.parse($0)?.date },
            isCompleted: props["STATUS"] == "COMPLETED",
            completedDate: props["COMPLETED"].flatMap { ICSDateFormat.parse($0)?.date },
            priority: props["PRIORITY"].flatMap(Int.init),
            recurrence: props["RRULE"].flatMap(RRuleCodec.decode),
            exceptionDates: exceptionDates(block)
        )
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios && swift test --filter ICSParserTests`
Expected: PASS, all 3 tests green.

- [ ] **Step 5: Commit**

```bash
cd ios && git add Sources/StarkKit/ICS/ICSParser.swift Tests/StarkKitTests/ICSParserTests.swift
git commit -m "feat: add ICSParser with skip-malformed-block behavior"
```

---

### Task 7: `PlannerFile` (storage layer)

**Files:**
- Create: `ios/Sources/StarkKit/Planner/PlannerFile.swift`
- Test: `ios/Tests/StarkKitTests/PlannerFileTests.swift`

**Interfaces:**
- Consumes: `ICSParser.parse(_:)`, `ICSSerializer.serialize(events:reminders:)`, `YearMonth`
- Produces: `PlannerFile { init(directory: URL, pendingDirectory: URL, fileManager: FileManager = .default); func loadRecurring() -> ICSParseResult; func loadMonth(_ month: YearMonth) -> ICSParseResult; func saveRecurring(events: [Event], reminders: [Reminder]) throws; func saveMonth(_ month: YearMonth, events: [Event], reminders: [Reminder]) throws; func retryPendingWrites(); var pendingWriteCount: Int { get } }`

- [ ] **Step 1: Write the failing tests**

```swift
// ios/Tests/StarkKitTests/PlannerFileTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("PlannerFile")
struct PlannerFileTests {
    private func makeTempDirs() -> (directory: URL, pending: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (root.appendingPathComponent("docs"), root.appendingPathComponent("pending"))
    }

    @Test("loading a missing month returns an empty result, not an error")
    func missingMonthIsEmpty() {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)

        let result = file.loadMonth(YearMonth(year: 2026, month0: 8))

        #expect(result.events.isEmpty)
        #expect(result.reminders.isEmpty)
    }

    @Test("saveMonth then loadMonth round-trips items")
    func saveThenLoadRoundTrips() throws {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)
        let event = Event(title: "Standup", start: DateMath.date(from: "2026-09-17"))

        try file.saveMonth(YearMonth(year: 2026, month0: 8), events: [event], reminders: [])
        let result = file.loadMonth(YearMonth(year: 2026, month0: 8))

        #expect(result.events.map(\.title) == ["Standup"])
    }

    @Test("a save failure queues a pending write, retried later")
    func saveFailureQueuesPendingWrite() throws {
        let (directory, pending) = makeTempDirs()
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Create a plain FILE where the target directory should be, forcing every save to fail.
        try Data().write(to: directory)
        let file = PlannerFile(directory: directory, pendingDirectory: pending)
        let event = Event(title: "Standup", start: DateMath.date(from: "2026-09-17"))

        #expect(throws: (any Error).self) {
            try file.saveMonth(YearMonth(year: 2026, month0: 8), events: [event], reminders: [])
        }
        #expect(file.pendingWriteCount == 1)

        // Fix the directory, then retry.
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file.retryPendingWrites()

        #expect(file.pendingWriteCount == 0)
        #expect(file.loadMonth(YearMonth(year: 2026, month0: 8)).events.map(\.title) == ["Standup"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && swift test --filter PlannerFileTests`
Expected: FAIL — `PlannerFile` does not exist.

- [ ] **Step 3: Write the implementation**

```swift
// ios/Sources/StarkKit/Planner/PlannerFile.swift
import Foundation

public final class PlannerFile {
    private let directory: URL
    private let pendingDirectory: URL
    private let fileManager: FileManager

    public init(directory: URL, pendingDirectory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.pendingDirectory = pendingDirectory
        self.fileManager = fileManager
    }

    public func loadRecurring() -> ICSParseResult {
        load(fileName: "recurring.ics")
    }

    public func loadMonth(_ month: YearMonth) -> ICSParseResult {
        load(fileName: month.fileName)
    }

    private func load(fileName: String) -> ICSParseResult {
        let url = directory.appendingPathComponent(fileName)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ICSParseResult(events: [], reminders: [], warnings: [])
        }
        return ICSParser.parse(content)
    }

    public func saveRecurring(events: [Event], reminders: [Reminder]) throws {
        try save(fileName: "recurring.ics", events: events, reminders: reminders)
    }

    public func saveMonth(_ month: YearMonth, events: [Event], reminders: [Reminder]) throws {
        try save(fileName: month.fileName, events: events, reminders: reminders)
    }

    private func save(fileName: String, events: [Event], reminders: [Reminder]) throws {
        let content = ICSSerializer.serialize(events: events, reminders: reminders)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            clearPendingWrite(fileName: fileName)
        } catch {
            try fileManager.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
            try content.write(to: pendingDirectory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            throw error
        }
    }

    private func clearPendingWrite(fileName: String) {
        try? fileManager.removeItem(at: pendingDirectory.appendingPathComponent(fileName))
    }

    public func retryPendingWrites() {
        guard let files = try? fileManager.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in files {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            if (try? content.write(to: destination, atomically: true, encoding: .utf8)) != nil {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    public var pendingWriteCount: Int {
        (try? fileManager.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil).count) ?? 0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios && swift test --filter PlannerFileTests`
Expected: PASS, all 3 tests green.

- [ ] **Step 5: Commit**

```bash
cd ios && git add Sources/StarkKit/Planner/PlannerFile.swift Tests/StarkKitTests/PlannerFileTests.swift
git commit -m "feat: add PlannerFile with pending-write queue"
```

---

### Task 8: `PlannerStore`

**Files:**
- Create: `ios/Sources/StarkKit/Planner/PlannerStore.swift`
- Test: `ios/Tests/StarkKitTests/PlannerStoreTests.swift`

**Interfaces:**
- Consumes: `PlannerFile`, `Event`, `Reminder`, `YearMonth`
- Produces: `PlannerStore` (`@MainActor`, `ObservableObject`) with `@Published events: [Event]`, `@Published reminders: [Reminder]`, `@Published error: String?`; `func start(around: Date)`; `func loadMonth(_ month: YearMonth)`; `func addEvent(_:)`; `func addReminder(_:)`; `func deleteEvent(id:)`; `func deleteReminder(id:)`; `func completeReminder(id: String, on: Date)`

- [ ] **Step 1: Write the failing tests**

```swift
// ios/Tests/StarkKitTests/PlannerStoreTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("PlannerStore")
struct PlannerStoreTests {
    private func makeStore() -> (PlannerStore, PlannerFile, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = PlannerFile(directory: root.appendingPathComponent("docs"), pendingDirectory: root.appendingPathComponent("pending"))
        return (PlannerStore(file: file), file, root)
    }

    @Test("a non-recurring event is written to its own month's file")
    @MainActor
    func nonRecurringEventGoesToMonthFile() {
        let (store, file, _) = makeStore()
        store.start(around: DateMath.date(from: "2026-09-01"))

        store.addEvent(Event(title: "Standup", start: DateMath.date(from: "2026-09-17")))

        let onDisk = file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(onDisk.events.map(\.title) == ["Standup"])
        #expect(store.events.map(\.title) == ["Standup"])
    }

    @Test("a recurring reminder is written to recurring.ics, not a month file")
    @MainActor
    func recurringReminderGoesToRecurringFile() {
        let (store, file, _) = makeStore()
        store.start(around: DateMath.date(from: "2026-09-01"))

        store.addReminder(Reminder(
            title: "Take out trash",
            dueDate: DateMath.date(from: "2026-09-17"),
            recurrence: RecurrenceRule(frequency: .weekly)
        ))

        let recurring = file.loadRecurring()
        #expect(recurring.reminders.map(\.title) == ["Take out trash"])
        let month = file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(month.reminders.isEmpty)
    }

    @Test("completing one occurrence of a recurring reminder exdates the master and logs a completion")
    @MainActor
    func completingRecurringReminderExdatesAndLogs() {
        let (store, file, _) = makeStore()
        store.start(around: DateMath.date(from: "2026-09-01"))
        store.addReminder(Reminder(
            id: "rem-1",
            title: "Take out trash",
            dueDate: DateMath.date(from: "2026-09-17"),
            recurrence: RecurrenceRule(frequency: .weekly)
        ))

        store.completeReminder(id: "rem-1", on: DateMath.date(from: "2026-09-17"))

        let recurring = file.loadRecurring()
        #expect(recurring.reminders.first?.exceptionDates.count == 1)
        let month = file.loadMonth(YearMonth(year: 2026, month0: 8))
        #expect(month.reminders.contains { $0.isCompleted && $0.title == "Take out trash" })
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && swift test --filter PlannerStoreTests`
Expected: FAIL — `PlannerStore` does not exist.

- [ ] **Step 3: Write the implementation**

```swift
// ios/Sources/StarkKit/Planner/PlannerStore.swift
import Foundation
import Combine

@MainActor
public final class PlannerStore: ObservableObject {
    @Published public private(set) var events: [Event] = []
    @Published public private(set) var reminders: [Reminder] = []
    @Published public var error: String?

    private let file: PlannerFile
    private var loadedMonths: Set<YearMonth> = []
    private var recurringEvents: [Event] = []
    private var recurringReminders: [Reminder] = []
    private var monthEvents: [YearMonth: [Event]] = [:]
    private var monthReminders: [YearMonth: [Reminder]] = [:]

    public init(file: PlannerFile) {
        self.file = file
    }

    public func start(around date: Date) {
        let recurring = file.loadRecurring()
        recurringEvents = recurring.events
        recurringReminders = recurring.reminders

        let center = YearMonth(date: date)
        for offset in -1...1 {
            loadMonth(YearMonth(year: center.year, month0: center.month0 + offset))
        }
        rebuild()
    }

    public func loadMonth(_ month: YearMonth) {
        guard !loadedMonths.contains(month) else { return }
        let result = file.loadMonth(month)
        monthEvents[month] = result.events
        monthReminders[month] = result.reminders
        loadedMonths.insert(month)
        rebuild()
    }

    public func addEvent(_ event: Event) {
        if event.recurrence != nil {
            recurringEvents.append(event)
            persistRecurring()
        } else {
            let month = YearMonth(date: event.start)
            loadMonth(month)
            monthEvents[month, default: []].append(event)
            persistMonth(month)
        }
        rebuild()
    }

    public func addReminder(_ reminder: Reminder) {
        if reminder.recurrence != nil {
            recurringReminders.append(reminder)
            persistRecurring()
        } else {
            let month = YearMonth(date: reminder.dueDate ?? Date())
            loadMonth(month)
            monthReminders[month, default: []].append(reminder)
            persistMonth(month)
        }
        rebuild()
    }

    public func deleteEvent(id: String) {
        recurringEvents.removeAll { $0.id == id }
        for month in loadedMonths { monthEvents[month]?.removeAll { $0.id == id } }
        persistRecurring()
        for month in loadedMonths { persistMonth(month) }
        rebuild()
    }

    public func deleteReminder(id: String) {
        recurringReminders.removeAll { $0.id == id }
        for month in loadedMonths { monthReminders[month]?.removeAll { $0.id == id } }
        persistRecurring()
        for month in loadedMonths { persistMonth(month) }
        rebuild()
    }

    public func completeReminder(id: String, on date: Date) {
        if let index = recurringReminders.firstIndex(where: { $0.id == id }) {
            recurringReminders[index].exceptionDates.append(date)
            var completedCopy = recurringReminders[index]
            completedCopy.id = UUID().uuidString
            completedCopy.recurrence = nil
            completedCopy.exceptionDates = []
            completedCopy.isCompleted = true
            completedCopy.completedDate = date
            completedCopy.dueDate = date

            let month = YearMonth(date: date)
            loadMonth(month)
            monthReminders[month, default: []].append(completedCopy)
            persistRecurring()
            persistMonth(month)
        } else {
            for month in loadedMonths {
                guard let idx = monthReminders[month]?.firstIndex(where: { $0.id == id }) else { continue }
                monthReminders[month]?[idx].isCompleted = true
                monthReminders[month]?[idx].completedDate = date
                persistMonth(month)
                break
            }
        }
        rebuild()
    }

    private func rebuild() {
        events = recurringEvents + monthEvents.values.flatMap { $0 }
        reminders = recurringReminders + monthReminders.values.flatMap { $0 }
    }

    private func persistRecurring() {
        do {
            try file.saveRecurring(events: recurringEvents, reminders: recurringReminders)
        } catch {
            self.error = "Couldn't save changes: \(error.localizedDescription)"
        }
    }

    private func persistMonth(_ month: YearMonth) {
        do {
            try file.saveMonth(month, events: monthEvents[month] ?? [], reminders: monthReminders[month] ?? [])
        } catch {
            self.error = "Couldn't save changes: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios && swift test --filter PlannerStoreTests`
Expected: PASS, all 3 tests green.

- [ ] **Step 5: Run the full StarkKit suite**

Run: `cd ios && swift test`
Expected: every test in the package passes (Tasks 1–8 combined).

- [ ] **Step 6: Commit**

```bash
cd ios && git add Sources/StarkKit/Planner/PlannerStore.swift Tests/StarkKitTests/PlannerStoreTests.swift
git commit -m "feat: add PlannerStore with recurring/month routing and completion logic"
```

---

## Part B — `Stark` app target (iOS-only, manual verification)

### Task 9: Xcode app project and local package dependency

**⚠️ This task requires Xcode's GUI (creating a new project target) and must be done by hand, not dispatched to a subagent — no CLI tool creates a new Xcode App project with a SwiftUI lifecycle target. If running this plan subagent-driven, stop before this task and complete it yourself, then resume with a subagent for Task 10 onward.**

**Files:**
- Create (via Xcode "New Project" — App, SwiftUI interface, iOS 17 minimum, product name `Stark`, location `ios/App/`)

**Interfaces:**
- Produces: an Xcode project at `ios/App/Stark/Stark.xcodeproj` with `StarkKit` added as a local Swift package dependency.

- [ ] **Step 1: Create the Xcode project**

In Xcode: File → New → Project → iOS → App. Product Name: `Stark`. Interface: SwiftUI. Language: Swift. Minimum Deployment: iOS 17.0. Save at `ios/App/Stark/`.

- [ ] **Step 2: Set the bundle identifier to match the existing App Store listing**

Project → target "Stark" → Signing & Capabilities → Bundle Identifier: `com.caritos.todo-txt` (must match exactly — this is what makes `ship.sh` upload as an update to the existing App Store listing rather than create a new app).

- [ ] **Step 3: Add the local package dependency**

Project navigator → select the project → target "Stark" → General → "Frameworks, Libraries, and Embedded Content" → "+" → "Add Other" → "Add Package Dependency" → "Add Local..." → select the `ios/` directory (the one containing `Package.swift`). Add `StarkKit` to the `Stark` target.

- [ ] **Step 4: Verify the package resolves and the empty app builds**

Build the app in Xcode (⌘B). Expected: builds with no errors, `import StarkKit` available in `ContentView.swift`.

- [ ] **Step 5: Commit**

```bash
cd ios && git add App
git commit -m "chore: scaffold Stark Xcode app target with StarkKit dependency"
```

---

### Task 10: `Theme.swift` design tokens

**Files:**
- Create: `ios/App/Stark/Stark/Theme.swift`

**Interfaces:**
- Produces: `enum Colors { static let background, accent, text, textSecondary, separator, checkboxBorder: Color }`; `enum Spacing { static let xs, sm, md, lg: CGFloat }`

No StarkKit dependency, no tests — a plain constants file, verified by using it in Task 11's views.

- [ ] **Step 1: Write the file**

```swift
// ios/App/Stark/Stark/Theme.swift
import SwiftUI

// Braun/Bauhaus: hard edges, no rounded corners, one accent color, flat geometry.
// Values match mobile/src/theme.ts exactly, so Stark's native app looks identical
// to the Expo app it replaces.
enum Colors {
    static let background = Color(hex: 0x1A1A1A)
    static let accent = Color(hex: 0xE8461A)
    static let text = Color(hex: 0xF0F0F0)
    static let textSecondary = Color(hex: 0x888888)
    static let separator = Color(hex: 0x333333)
    static let checkboxBorder = Color(hex: 0x555555)
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
```

- [ ] **Step 2: Verify it compiles**

Build the app in Xcode (⌘B), or `cd ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -destination "generic/platform=iOS Simulator" build`.
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
cd ios && git add App/Stark/Stark/Theme.swift
git commit -m "feat: add Braun/Bauhaus design tokens as Theme.swift"
```

**Note on fonts:** the Expo app uses JetBrains Mono (`@expo-google-fonts/jetbrains-mono`). Porting the actual `.ttf` files and registering them via `UIAppFonts` in Info.plist is deferred to a follow-on polish task — Task 11's views use `.font(.system(...))` for now so the MVP isn't blocked on font-asset plumbing.

---

### Task 11: Core views — `AgendaView`, `MonthGridView`, `AddItemView`, `EditItemView`

**Files:**
- Create: `ios/App/Stark/Stark/AgendaRow.swift`
- Create: `ios/App/Stark/Stark/AgendaView.swift`
- Create: `ios/App/Stark/Stark/MonthGridView.swift`
- Create: `ios/App/Stark/Stark/AddItemView.swift`
- Create: `ios/App/Stark/Stark/EditItemView.swift`
- Modify: `ios/App/Stark/Stark/ContentView.swift`
- Modify: `ios/App/Stark/Stark/StarkApp.swift` (Xcode-generated file)

**Interfaces:**
- Consumes: everything `StarkKit` produces (`PlannerStore`, `Event`, `Reminder`, `RecurrenceRule`, `OccurrenceExpander`, `YearMonth`, `DateMath`), and `Theme.swift`'s `Colors`/`Spacing`.

Not unit-tested — verified manually per Step 6.

- [ ] **Step 1: Define the agenda row model and view**

```swift
// ios/App/Stark/Stark/AgendaRow.swift
import Foundation
import StarkKit

enum AgendaItem: Identifiable {
    case event(Event, occurrence: Date)
    case reminder(Reminder, occurrence: Date)

    var id: String {
        switch self {
        case .event(let e, let occurrence): return "\(e.id)-\(occurrence.timeIntervalSince1970)"
        case .reminder(let r, let occurrence): return "\(r.id)-\(occurrence.timeIntervalSince1970)"
        }
    }

    var occurrence: Date {
        switch self {
        case .event(_, let occurrence), .reminder(_, let occurrence): return occurrence
        }
    }

    var title: String {
        switch self {
        case .event(let e, _): return e.title
        case .reminder(let r, _): return r.title
        }
    }
}

/// Expands every event/reminder into concrete dated occurrences within `range`,
/// then sorts by date. The single source of truth `AgendaView` and `MonthGridView`
/// both build on — never duplicate this expansion logic in a view.
func buildAgendaItems(events: [Event], reminders: [Reminder], in range: ClosedRange<Date>) -> [AgendaItem] {
    var items: [AgendaItem] = []
    for event in events {
        for occurrence in OccurrenceExpander.expand(event: event, in: range) {
            items.append(.event(event, occurrence: occurrence))
        }
    }
    for reminder in reminders {
        for occurrence in OccurrenceExpander.expand(reminder: reminder, in: range) {
            items.append(.reminder(reminder, occurrence: occurrence))
        }
    }
    return items.sorted { $0.occurrence < $1.occurrence }
}
```

```swift
// ios/App/Stark/Stark/AgendaView.swift
import SwiftUI
import StarkKit

struct AgendaView: View {
    @EnvironmentObject private var store: PlannerStore
    let onSelect: (AgendaItem) -> Void

    var body: some View {
        let range = DateMath.date(from: DateMath.addDays(DateMath.isoDate(from: Date()), -14))
            ...DateMath.date(from: DateMath.addDays(DateMath.isoDate(from: Date()), 60))
        let items = buildAgendaItems(events: store.events, reminders: store.reminders, in: range)

        List(items) { item in
            Button {
                onSelect(item)
            } label: {
                HStack {
                    Text(item.title)
                        .foregroundStyle(Colors.text)
                    Spacer()
                    Text(item.occurrence.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(Colors.textSecondary)
                }
            }
            .listRowBackground(Colors.background)
        }
        .scrollContentBackground(.hidden)
        .background(Colors.background)
        .navigationTitle("Agenda")
    }
}
```

- [ ] **Step 2: Write `MonthGridView`**

```swift
// ios/App/Stark/Stark/MonthGridView.swift
import SwiftUI
import StarkKit

struct MonthGridView: View {
    @EnvironmentObject private var store: PlannerStore
    @State private var visibleMonth = YearMonth(date: Date())
    let onSelectDate: (Date) -> Void

    var body: some View {
        let daysInMonth = DateMath.daysInMonth(year: visibleMonth.year, month0: visibleMonth.month0)
        let firstWeekday = DateMath.weekday(year: visibleMonth.year, month0: visibleMonth.month0, day: 1)

        VStack {
            HStack {
                Button("‹") { changeMonth(by: -1) }
                Spacer()
                Text(String(format: "%04d-%02d", visibleMonth.year, visibleMonth.month0 + 1))
                    .foregroundStyle(Colors.text)
                Spacer()
                Button("›") { changeMonth(by: 1) }
            }
            .padding(Spacing.md)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                ForEach(0..<firstWeekday, id: \.self) { _ in Color.clear }
                ForEach(1...daysInMonth, id: \.self) { day in
                    let date = DateMath.date(from: DateMath.isoDate(year: visibleMonth.year, month0: visibleMonth.month0, day: day))
                    Button("\(day)") { onSelectDate(date) }
                        .foregroundStyle(Colors.text)
                }
            }
        }
        .background(Colors.background)
        .task { store.loadMonth(visibleMonth) }
    }

    private func changeMonth(by offset: Int) {
        visibleMonth = YearMonth(year: visibleMonth.year, month0: visibleMonth.month0 + offset)
        store.loadMonth(visibleMonth)
    }
}
```

- [ ] **Step 3: Write `AddItemView`**

```swift
// ios/App/Stark/Stark/AddItemView.swift
import SwiftUI
import StarkKit

struct AddItemView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: Kind = .event
    @State private var title = ""
    @State private var date = Date()

    enum Kind: String, CaseIterable { case event = "Event", reminder = "Reminder" }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                TextField("Title", text: $title)
                DatePicker(kind == .event ? "Start" : "Due", selection: $date)
            }
            .navigationTitle("Add \(kind.rawValue)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func add() {
        switch kind {
        case .event:
            store.addEvent(Event(title: title, start: date))
        case .reminder:
            store.addReminder(Reminder(title: title, dueDate: date))
        }
        dismiss()
    }
}
```

- [ ] **Step 4: Write `EditItemView`**

```swift
// ios/App/Stark/Stark/EditItemView.swift
import SwiftUI
import StarkKit

struct EditItemView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    let item: AgendaItem
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            Text(item.title).foregroundStyle(Colors.text)

            if case .reminder(let reminder, let occurrence) = item, !reminder.isCompleted {
                Button("Done") {
                    store.completeReminder(id: reminder.id, on: occurrence)
                    dismiss()
                }
            }

            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .confirmationDialog(deleteMessage, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                switch item {
                case .event(let event, _): store.deleteEvent(id: event.id)
                case .reminder(let reminder, _): store.deleteReminder(id: reminder.id)
                }
                dismiss()
            }
        }
    }

    private var isRecurring: Bool {
        switch item {
        case .event(let e, _): return e.recurrence != nil
        case .reminder(let r, _): return r.recurrence != nil
        }
    }

    private var deleteMessage: String {
        isRecurring
            ? "This deletes all future occurrences."
            : "This cannot be undone."
    }
}
```

- [ ] **Step 5: Wire it together in `ContentView` and `StarkApp`**

```swift
// ios/App/Stark/Stark/ContentView.swift
import SwiftUI
import StarkKit

struct ContentView: View {
    @EnvironmentObject private var store: PlannerStore
    @State private var showAdd = false
    @State private var selectedItem: AgendaItem?

    var body: some View {
        NavigationStack {
            AgendaView(onSelect: { selectedItem = $0 })
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add", systemImage: "plus") { showAdd = true }
                    }
                }
                .sheet(isPresented: $showAdd) { AddItemView() }
                .sheet(item: $selectedItem) { item in EditItemView(item: item) }
                .task { store.start(around: Date()) }
        }
    }
}
```

```swift
// ios/App/Stark/Stark/StarkApp.swift
import SwiftUI
import StarkKit

@main
struct StarkApp: App {
    @StateObject private var store = makeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }

    private static func makeStore() -> PlannerStore {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = PlannerFile(
            directory: documents,
            pendingDirectory: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PendingWrites")
        )
        return PlannerStore(file: file)
    }
}
```

- [ ] **Step 6: Manual verification in the simulator**

Run the app in Xcode (⌘R) on an iOS 17+ simulator. Verify manually:
1. Tap Add, create an Event with today's date — it appears in the Agenda list.
2. Tap Add, create a Reminder due today — it appears in the Agenda list.
3. Tap the Reminder, tap Done — it disappears from the incomplete list (re-open the app to confirm the completion persisted to disk).
4. Tap an Event, Delete, confirm — it's removed from the Agenda.
5. In `MonthGridView`, tap a date and confirm `onSelectDate` fires (wire a temporary print or breakpoint if not yet connected to Agenda's scroll position — full month-grid-to-agenda-jump wiring is a follow-on polish task, not required for this MVP task's verification).

- [ ] **Step 7: Commit**

```bash
cd ios && git add App
git commit -m "feat: add AgendaView, MonthGridView, AddItemView, EditItemView wired to PlannerStore"
```

---

### Task 12: `deploy.sh` and `ship.sh`

**Files:**
- Create: `ios/App/deploy.sh`
- Create: `ios/App/ship.sh`
- Create: `ios/App/ExportOptions.plist`

**Interfaces:**
- Consumes: nothing from StarkKit — pure build tooling.

- [ ] **Step 1: Write `deploy.sh`, adapted from `~/src/spool/ios/App/deploy.sh`**

```bash
#!/bin/bash
# Builds Stark and installs + launches it on a connected physical
# iPhone, entirely via CLI (xcodebuild + xcrun devicectl) - no Xcode GUI needed.
#
# Usage: ./deploy.sh [device name substring]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/Stark" && pwd)"
DEFAULT_DEVICE_NAME="Eladios-iPhone-16-Plus"
DEVICE_NAME="${1:-$DEFAULT_DEVICE_NAME}"

cd "$PROJECT_DIR"

echo "==> Finding device matching '$DEVICE_NAME'..."
DEVICE_ID=$( (xcrun devicectl list devices 2>/dev/null \
  | grep -v unavailable \
  | grep -F "$DEVICE_NAME" \
  | awk -v host="$DEVICE_NAME" '{for(i=1;i<=NF;i++) if(index($i, host) > 0) {print $(i+1); exit}}' \
  | head -1) || true)

if [ -z "$DEVICE_ID" ]; then
  echo "error: no connected device found matching '$DEVICE_NAME'" >&2
  echo "Connected devices:" >&2
  xcrun devicectl list devices >&2
  exit 1
fi
echo "    -> device id: $DEVICE_ID"

echo "==> Building (xcodebuild)..."
xcodebuild -project Stark.xcodeproj \
  -scheme Stark \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  build

APP_PATH=$(xcodebuild -project Stark.xcodeproj \
  -scheme Stark \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{bpd=$2} / FULL_PRODUCT_NAME =/{fpn=$2} END{print bpd"/"fpn}')

echo "==> Installing on device..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

BUNDLE_ID=$(defaults read "$APP_PATH/Info" CFBundleIdentifier)

echo "==> Launching..."
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"

echo "==> Done. $BUNDLE_ID is running on $DEVICE_NAME."
```

- [ ] **Step 2: Write `ExportOptions.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

- [ ] **Step 3: Write `ship.sh`, adapted from `~/src/spool/ios/App/ship.sh`**

```bash
#!/bin/bash
# Archives, exports, and uploads Stark to App Store Connect (TestFlight) - entirely via
# CLI (xcodebuild + an App Store Connect API key), no Xcode GUI or Apple ID login needed.
#
# One-time setup: generate an App Store Connect API key at
# appstoreconnect.apple.com -> Users and Access -> Integrations -> App Store Connect API
# (role App Manager or Admin), download its .p8 ONCE, and save it as
# ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8.
#
# Deliberately does NOT submit the uploaded build for App Store review - it only lands
# in TestFlight.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/Stark"
BUILD_DIR="/tmp/stark-ship-build"

API_KEY_ID="${API_KEY_ID:?set API_KEY_ID to your App Store Connect API key ID}"
API_ISSUER_ID="${API_ISSUER_ID:?set API_ISSUER_ID to your App Store Connect issuer ID}"
API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8"

if [ ! -f "$API_KEY_PATH" ]; then
  echo "error: App Store Connect API key not found at $API_KEY_PATH" >&2
  exit 1
fi

cd "$PROJECT_DIR"
PBXPROJ="Stark.xcodeproj/project.pbxproj"

MARKETING_VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$PBXPROJ" | head -1)
CURRENT_BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/p' "$PBXPROJ" | head -1)
NEXT_BUILD=$((CURRENT_BUILD + 1))

echo "==> Bumping build number: $CURRENT_BUILD -> $NEXT_BUILD (version $MARKETING_VERSION)"
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEXT_BUILD;/g" "$PBXPROJ"

ARCHIVE_PATH="$BUILD_DIR/Stark.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

export PATH="/usr/bin:$PATH"

echo "==> Archiving version $MARKETING_VERSION (build $NEXT_BUILD)..."
xcodebuild archive \
  -project Stark.xcodeproj \
  -scheme Stark \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID"

echo "==> Exporting and uploading to App Store Connect..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID"

echo ""
echo "Done. Shipped v$MARKETING_VERSION (build $NEXT_BUILD) to App Store Connect."
echo "Check TestFlight processing status at appstoreconnect.apple.com."
```

- [ ] **Step 4: Make both scripts executable**

Run: `chmod +x ios/App/deploy.sh ios/App/ship.sh`

- [ ] **Step 5: Verify `deploy.sh` end-to-end on a connected device**

Run: `./ios/App/deploy.sh` (with a physical iPhone connected via USB, or pass a device name substring as `$1`).
Expected: builds, installs, and launches Stark on the device.

- [ ] **Step 6: Commit**

```bash
cd ios && git add App/deploy.sh App/ship.sh App/ExportOptions.plist
git commit -m "feat: add deploy.sh and ship.sh CLI build/ship tooling"
```
