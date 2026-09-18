# Recurrence Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `AddItemView` a Fantastical-style recurrence picker, extending `RecurrenceRule` to support multi-day monthly, multi-month yearly, and positional ("2nd Tuesday", "last weekday") recurrence, and wiring a full picker UI on top of it.

**Architecture:** Extends the existing `StarkKit` package (models, `OccurrenceExpander`, `RRuleCodec`) with the new recurrence vocabulary, fully TDD via Swift Testing — then adds four new SwiftUI view files plus an `AddItemView` change, verified manually per the app's established pattern.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Testing, no third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-18-recurrence-picker-design.md`

## Global Constraints

- No third-party dependencies.
- Test framework is Swift Testing (`import Testing`, `@Test`, `#expect`) — never XCTest.
- Every new enum used as a `Picker` selection value or inside a `Set` needs explicit `Hashable` conformance (SwiftUI `Picker` and `Set` both require it; Swift does not synthesize it unless declared). This includes `Month`, `Position`, `DayTypeOrWeekday` (all new) and `Weekday` (existing — needs `Hashable` added to its conformance list).
- `byMonthDay` and `byPositionalDay` are mutually exclusive on `RecurrenceRule`. If a rule somehow has both set, `OccurrenceExpander` gives `byPositionalDay` precedence.
- `byMonth` only applies to `.yearly` frequency; `nil` means "the anchor date's own month," same as today.
- RRULE encoding stays standard wherever possible: `BYMONTHDAY`/`BYMONTH` as native lists, ordinal-prefixed `BYDAY` for specific-weekday positional rules (e.g. `BYDAY=2TU`), `BYSETPOS` for generic-day-type positional rules (e.g. `BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1` for "last weekday"). No custom `X-` properties.
- A `byPositionalDay` list may contain multiple specific-weekday entries together (e.g. "1st Monday and last Friday" → `BYDAY=1MO,-1FR`), but a generic day-type entry (`anyDay`/`weekdayOnly`/`weekendDay`) must be the *only* entry in the list — the picker UI enforces this.
- New Swift files added under `ios/App/Stark/Stark/` are automatically included in the build (the Xcode project uses a file-system-synchronized group) — unlike the original MVP plan's Task 9, **no manual Xcode step is needed anywhere in this plan.**
- This plan does not touch `PlannerStore`, `PlannerFile`, or `EditItemView` — only `AddItemView` gains the new Repeat row.

---

## Part A — `StarkKit` model and logic changes (fully TDD)

### Task 1: New model types — `Month`, `Position`, `DayTypeOrWeekday`, `PositionalDay`

**Files:**
- Create: `ios/Sources/StarkKit/Models/Month.swift`
- Create: `ios/Sources/StarkKit/Models/PositionalDay.swift`
- Modify: `ios/Sources/StarkKit/Models/Weekday.swift` (add `Hashable`)
- Test: `ios/Tests/StarkKitTests/PositionalDayTests.swift`

**Interfaces:**
- Produces: `Month` (`Int` raw value, `.january...december` = 1...12, `Hashable`); `Position` (`Int` raw value, `.first...fourth` = 1...4, `.last` = -1, `Hashable`); `DayTypeOrWeekday` (`.weekday(Weekday)`, `.anyDay`, `.weekdayOnly`, `.weekendDay`, `Hashable`); `PositionalDay` (`position: Position`, `dayType: DayTypeOrWeekday`, `Hashable`).

- [ ] **Step 1: Add `Hashable` to `Weekday`**

```swift
// ios/Sources/StarkKit/Models/Weekday.swift
public enum Weekday: Int, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case sunday = 0, monday, tuesday, wednesday, thursday, friday, saturday
}
```

- [ ] **Step 2: Write `Month.swift`**

```swift
// ios/Sources/StarkKit/Models/Month.swift
public enum Month: Int, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case january = 1, february, march, april, may, june, july, august,
         september, october, november, december
}
```

- [ ] **Step 3: Write `PositionalDay.swift`**

```swift
// ios/Sources/StarkKit/Models/PositionalDay.swift
public enum Position: Int, Codable, Equatable, Hashable, Sendable {
    case first = 1, second, third, fourth
    case last = -1
}

public enum DayTypeOrWeekday: Codable, Equatable, Hashable, Sendable {
    case weekday(Weekday)
    case anyDay
    case weekdayOnly
    case weekendDay
}

public struct PositionalDay: Equatable, Codable, Hashable, Sendable {
    public var position: Position
    public var dayType: DayTypeOrWeekday

    public init(position: Position, dayType: DayTypeOrWeekday) {
        self.position = position
        self.dayType = dayType
    }
}
```

- [ ] **Step 4: Write and run the lock-in test**

```swift
// ios/Tests/StarkKitTests/PositionalDayTests.swift
import Testing
@testable import StarkKit

@Suite("PositionalDay")
struct PositionalDayTests {
    @Test("equality holds for identical position and day type")
    func equality() {
        let a = PositionalDay(position: .second, dayType: .weekday(.tuesday))
        let b = PositionalDay(position: .second, dayType: .weekday(.tuesday))
        #expect(a == b)
    }

    @Test("Month raw values run January...December as 1...12")
    func monthRawValues() {
        #expect(Month.january.rawValue == 1)
        #expect(Month.december.rawValue == 12)
    }

    @Test("Position raw values match RRULE BYMONTHDAY/ordinal-BYDAY encoding directly")
    func positionRawValues() {
        #expect(Position.first.rawValue == 1)
        #expect(Position.fourth.rawValue == 4)
        #expect(Position.last.rawValue == -1)
    }
}
```

Run: `cd ios && swift test --filter PositionalDayTests`
Expected: PASS, all 3 tests green.

- [ ] **Step 5: Run the full suite to confirm nothing broke**

Run: `cd ios && swift test`
Expected: all existing tests still pass (adding `Hashable` to `Weekday` is additive).

- [ ] **Step 6: Commit**

```bash
cd ios && git add Sources/StarkKit/Models/Month.swift Sources/StarkKit/Models/PositionalDay.swift Sources/StarkKit/Models/Weekday.swift Tests/StarkKitTests/PositionalDayTests.swift
git commit -m "feat: add Month, Position, DayTypeOrWeekday, PositionalDay models"
```

---

### Task 2: `RecurrenceRule` grows list-based fields; `OccurrenceExpander` monthly matching updated

**Files:**
- Modify: `ios/Sources/StarkKit/Models/RecurrenceRule.swift`
- Modify: `ios/Sources/StarkKit/Planner/OccurrenceExpander.swift`
- Modify: `ios/Tests/StarkKitTests/OccurrenceExpanderTests.swift` (fix the existing `monthlyClamped` test, which used a single `Int`)
- Test: same file, new cases appended

**Interfaces:**
- Consumes: nothing new
- Produces: `RecurrenceRule` with `byMonthDay: [Int]?` (was `Int?`), plus new (not yet consumed by `OccurrenceExpander`) `byPositionalDay: [PositionalDay]?` and `byMonth: [Month]?` fields, so the struct only needs one migration for this whole plan.

- [ ] **Step 1: Update the existing `monthlyClamped` test for the new `[Int]` shape, and add a multi-day-of-month test**

```swift
// ios/Tests/StarkKitTests/OccurrenceExpanderTests.swift
// Replace the existing "monthly clamps day-of-month to the shorter month" test with:

    @Test("monthly clamps day-of-month to the shorter month")
    func monthlyClamped() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [31])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-01-31"), rule: rule, exceptionDates: [], in: range("2026-01-31", "2026-04-30"))
        #expect(dates == [d("2026-01-31"), d("2026-02-28"), d("2026-03-31"), d("2026-04-30")])
    }

    @Test("monthly matches any of several days-of-month")
    func monthlyMultipleDays() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [1, 15])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-10-31"))
        #expect(dates == [d("2026-09-01"), d("2026-09-15"), d("2026-10-01"), d("2026-10-15")])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && swift test --filter OccurrenceExpanderTests`
Expected: FAIL — compile error, `byMonthDay:` no longer accepts a bare `Int`.

- [ ] **Step 3: Update `RecurrenceRule`**

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
    public var byMonthDay: [Int]?
    public var byPositionalDay: [PositionalDay]?
    public var byMonth: [Month]?
    public var count: Int?
    public var until: Date?

    public init(
        frequency: Frequency,
        interval: Int = 1,
        byDay: [Weekday]? = nil,
        byMonthDay: [Int]? = nil,
        byPositionalDay: [PositionalDay]? = nil,
        byMonth: [Month]? = nil,
        count: Int? = nil,
        until: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.byDay = byDay
        self.byMonthDay = byMonthDay
        self.byPositionalDay = byPositionalDay
        self.byMonth = byMonth
        self.count = count
        self.until = until
    }
}
```

- [ ] **Step 4: Update `OccurrenceExpander`'s monthly branch to match against the list**

Replace the `.monthly` case inside `matches(_:anchor:rule:calendar:)`:

```swift
        case .monthly:
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)!.count
            let candidateDay = calendar.component(.day, from: date)
            let dayMatches: Bool
            if let byMonthDay = rule.byMonthDay, !byMonthDay.isEmpty {
                dayMatches = byMonthDay.contains { min($0, daysInMonth) == candidateDay }
            } else {
                let anchorDay = calendar.component(.day, from: anchor)
                dayMatches = candidateDay == min(anchorDay, daysInMonth)
            }
            guard dayMatches else { return false }
            let months = calendar.dateComponents([.month], from: anchor, to: date).month ?? 0
            return months >= 0 && months % rule.interval == 0
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd ios && swift test --filter OccurrenceExpanderTests`
Expected: PASS, including the new `monthlyMultipleDays` test.

- [ ] **Step 6: Run the full suite**

Run: `cd ios && swift test`
Expected: all tests pass — this confirms nothing else in the package referenced `byMonthDay` as a bare `Int` (only `OccurrenceExpander` and its tests did).

- [ ] **Step 7: Commit**

```bash
cd ios && git add Sources/StarkKit/Models/RecurrenceRule.swift Sources/StarkKit/Planner/OccurrenceExpander.swift Tests/StarkKitTests/OccurrenceExpanderTests.swift
git commit -m "feat: RecurrenceRule.byMonthDay becomes a list; add byPositionalDay/byMonth fields"
```

---

### Task 3: `OccurrenceExpander` yearly matching gains `byMonth` gating

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/OccurrenceExpander.swift`
- Modify: `ios/Tests/StarkKitTests/OccurrenceExpanderTests.swift`

**Interfaces:**
- Consumes: `RecurrenceRule.byMonth`
- Produces: no new public API — internal matching behavior only

- [ ] **Step 1: Write the failing test**

```swift
// ios/Tests/StarkKitTests/OccurrenceExpanderTests.swift
    @Test("yearly matches any of several months")
    func yearlyMultipleMonths() {
        let rule = RecurrenceRule(frequency: .yearly, byMonth: [.march, .september])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-03-15"), rule: rule, exceptionDates: [], in: range("2026-01-01", "2026-12-31"))
        #expect(dates == [d("2026-03-15"), d("2026-09-15")])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && swift test --filter OccurrenceExpanderTests`
Expected: FAIL — `byMonth` is never consulted yet, so September 15 is missing from the result.

- [ ] **Step 3: Update the `.yearly` case to gate on `byMonth`**

Replace the `.yearly` case inside `matches(_:anchor:rule:calendar:)`:

```swift
        case .yearly:
            let candidateMonth = calendar.component(.month, from: date)
            let monthMatches: Bool
            if let byMonth = rule.byMonth, !byMonth.isEmpty {
                monthMatches = byMonth.contains { $0.rawValue == candidateMonth }
            } else {
                monthMatches = candidateMonth == calendar.component(.month, from: anchor)
            }
            guard monthMatches else { return false }

            let daysInMonth = calendar.range(of: .day, in: .month, for: date)!.count
            let candidateDay = calendar.component(.day, from: date)
            let dayMatches: Bool
            if let byMonthDay = rule.byMonthDay, !byMonthDay.isEmpty {
                dayMatches = byMonthDay.contains { min($0, daysInMonth) == candidateDay }
            } else {
                let anchorDay = calendar.component(.day, from: anchor)
                dayMatches = candidateDay == min(anchorDay, daysInMonth)
            }
            guard dayMatches else { return false }

            let years = calendar.dateComponents([.year], from: anchor, to: date).year ?? 0
            return years >= 0 && years % rule.interval == 0
```

Note: this duplicates the day-matching logic from `.monthly`. That duplication is deliberately left as-is here — Task 4 factors both branches' day-matching into one shared helper when it adds `byPositionalDay` support, so fixing it now would just be rewritten again immediately.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios && swift test --filter OccurrenceExpanderTests`
Expected: PASS, all tests green including `yearlyMultipleMonths`.

- [ ] **Step 5: Commit**

```bash
cd ios && git add Sources/StarkKit/Planner/OccurrenceExpander.swift Tests/StarkKitTests/OccurrenceExpanderTests.swift
git commit -m "feat: OccurrenceExpander yearly matching gains byMonth gating"
```

---

### Task 4: `OccurrenceExpander` gains positional-day resolution (`byPositionalDay`)

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/OccurrenceExpander.swift`
- Modify: `ios/Tests/StarkKitTests/OccurrenceExpanderTests.swift`

**Interfaces:**
- Consumes: `RecurrenceRule.byPositionalDay`, `PositionalDay`, `Position`, `DayTypeOrWeekday`, `DateMath.daysInMonth`, `DateMath.weekday`
- Produces: a private `resolvePositionalDay(_:year:month0:) -> Int?` helper and a private `dayMatches(...)` helper shared by the `.monthly` and `.yearly` branches (replacing their duplicated inline day-matching logic from Tasks 2/3)

- [ ] **Step 1: Write the failing tests**

```swift
// ios/Tests/StarkKitTests/OccurrenceExpanderTests.swift
    @Test("monthly positional: 2nd Tuesday of the month")
    func monthlyPositionalSpecificWeekday() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .second, dayType: .weekday(.tuesday))])
        // 2026-09-01 is a Tuesday; the 2nd Tuesday of September 2026 is the 8th.
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-11-30"))
        #expect(dates == [d("2026-09-08"), d("2026-10-13"), d("2026-11-10")])
    }

    @Test("monthly positional: last weekday of the month (generic day-type + BYSETPOS-style resolution)")
    func monthlyPositionalGenericWeekday() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .weekdayOnly)])
        // September 2026's last day (30th) is a Wednesday, so the last weekday IS the 30th.
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-30"))
        #expect(dates == [d("2026-09-30")])
    }

    @Test("yearly positional combined with byMonth: 4th Thursday of November (Thanksgiving)")
    func yearlyPositionalWithMonth() {
        let rule = RecurrenceRule(frequency: .yearly, byPositionalDay: [PositionalDay(position: .fourth, dayType: .weekday(.thursday))], byMonth: [.november])
        // 2026-11-26 is the 4th Thursday of November 2026.
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-01-01"), rule: rule, exceptionDates: [], in: range("2026-01-01", "2027-12-31"))
        #expect(dates == [d("2026-11-26"), d("2027-11-25")])
    }

    @Test("4th position resolves correctly at the minimum-occurrence boundary (28-day February)")
    func positionalFourthAtMinimumBoundary() {
        // Every weekday occurs at least 4 times in every possible month length (28-31 days) -
        // a 28-day month is the tightest case, where every weekday occurs exactly 4 times.
        // This is the boundary `resolvePositionalDay`'s .fourth case must get exactly right;
        // there is no realistic month/weekday combination where .fourth fails to resolve at all
        // (that would require 5 supported positions, which this model doesn't have).
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .fourth, dayType: .weekday(.monday))])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-02-01"), rule: rule, exceptionDates: [], in: range("2026-02-01", "2026-02-28"))
        // February 2026 Mondays: 2, 9, 16, 23 — exactly 4, so the 4th Monday (23rd) is the last one.
        #expect(dates == [d("2026-02-23")])
    }

    @Test("byPositionalDay takes precedence over byMonthDay when both are set")
    func positionalTakesPrecedenceOverMonthDay() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [1], byPositionalDay: [PositionalDay(position: .second, dayType: .weekday(.tuesday))])
        let dates = OccurrenceExpander.occurrences(anchor: d("2026-09-01"), rule: rule, exceptionDates: [], in: range("2026-09-01", "2026-09-30"))
        // Should resolve via byPositionalDay (Sept 8), not byMonthDay (Sept 1).
        #expect(dates == [d("2026-09-08")])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && swift test --filter OccurrenceExpanderTests`
Expected: FAIL — `byPositionalDay` is never consulted yet.

- [ ] **Step 3: Add the resolution helpers and wire them into both branches**

Add these two private functions to `OccurrenceExpander`:

```swift
    private static func matchesDayType(_ dayType: DayTypeOrWeekday, weekday: Weekday) -> Bool {
        switch dayType {
        case .weekday(let w): return weekday == w
        case .anyDay: return true
        case .weekdayOnly: return weekday != .sunday && weekday != .saturday
        case .weekendDay: return weekday == .sunday || weekday == .saturday
        }
    }

    private static func resolvePositionalDay(_ positional: PositionalDay, year: Int, month0: Int) -> Int? {
        let daysInMonth = DateMath.daysInMonth(year: year, month0: month0)
        var matchingDays: [Int] = []
        for day in 1...daysInMonth {
            let weekdayIndex = DateMath.weekday(year: year, month0: month0, day: day)
            let weekday = Weekday(rawValue: weekdayIndex)!
            if matchesDayType(positional.dayType, weekday: weekday) {
                matchingDays.append(day)
            }
        }
        switch positional.position {
        case .first: return matchingDays.first
        case .second: return matchingDays.count >= 2 ? matchingDays[1] : nil
        case .third: return matchingDays.count >= 3 ? matchingDays[2] : nil
        case .fourth: return matchingDays.count >= 4 ? matchingDays[3] : nil
        case .last: return matchingDays.last
        }
    }

    private static func dayMatches(candidateDay: Int, daysInMonth: Int, year: Int, month0: Int, rule: RecurrenceRule, anchor: Date, calendar: Calendar) -> Bool {
        if let positionalDays = rule.byPositionalDay, !positionalDays.isEmpty {
            return positionalDays.contains { resolvePositionalDay($0, year: year, month0: month0) == candidateDay }
        }
        if let byMonthDay = rule.byMonthDay, !byMonthDay.isEmpty {
            return byMonthDay.contains { min($0, daysInMonth) == candidateDay }
        }
        let anchorDay = calendar.component(.day, from: anchor)
        return candidateDay == min(anchorDay, daysInMonth)
    }
```

Then replace the `.monthly` and `.yearly` cases inside `matches(_:anchor:rule:calendar:)` to use the shared helper:

```swift
        case .monthly:
            let year = calendar.component(.year, from: date)
            let month0 = calendar.component(.month, from: date) - 1
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)!.count
            let candidateDay = calendar.component(.day, from: date)
            guard dayMatches(candidateDay: candidateDay, daysInMonth: daysInMonth, year: year, month0: month0, rule: rule, anchor: anchor, calendar: calendar) else { return false }
            let months = calendar.dateComponents([.month], from: anchor, to: date).month ?? 0
            return months >= 0 && months % rule.interval == 0

        case .yearly:
            let candidateMonth = calendar.component(.month, from: date)
            let monthMatches: Bool
            if let byMonth = rule.byMonth, !byMonth.isEmpty {
                monthMatches = byMonth.contains { $0.rawValue == candidateMonth }
            } else {
                monthMatches = candidateMonth == calendar.component(.month, from: anchor)
            }
            guard monthMatches else { return false }

            let year = calendar.component(.year, from: date)
            let month0 = candidateMonth - 1
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)!.count
            let candidateDay = calendar.component(.day, from: date)
            guard dayMatches(candidateDay: candidateDay, daysInMonth: daysInMonth, year: year, month0: month0, rule: rule, anchor: anchor, calendar: calendar) else { return false }

            let years = calendar.dateComponents([.year], from: anchor, to: date).year ?? 0
            return years >= 0 && years % rule.interval == 0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios && swift test --filter OccurrenceExpanderTests`
Expected: PASS, all tests green including the 5 new positional tests.

- [ ] **Step 5: Run the full suite**

Run: `cd ios && swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd ios && git add Sources/StarkKit/Planner/OccurrenceExpander.swift Tests/StarkKitTests/OccurrenceExpanderTests.swift
git commit -m "feat: OccurrenceExpander resolves positional day-of-month rules"
```

---

### Task 5: `RRuleCodec` encodes/decodes the new fields

**Files:**
- Modify: `ios/Sources/StarkKit/ICS/RRuleCodec.swift`
- Modify: `ios/Tests/StarkKitTests/ICSSerializerTests.swift` (or a new test file — see Step 1)

**Interfaces:**
- Consumes: `RecurrenceRule.byMonthDay: [Int]?`, `.byMonth: [Month]?`, `.byPositionalDay: [PositionalDay]?`
- Produces: no new public API — `RRuleCodec.encode`/`decode` handle the expanded `RecurrenceRule` shape

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/StarkKitTests/RRuleCodecTests.swift` (this logic previously had no dedicated test file — its coverage lived inside `ICSSerializerTests`/`ICSParserTests` round-trips. A dedicated file is clearer now that the encoding logic has grown):

```swift
// ios/Tests/StarkKitTests/RRuleCodecTests.swift
import Testing
@testable import StarkKit

@Suite("RRuleCodec")
struct RRuleCodecTests {
    @Test("encodes and decodes multiple days-of-month")
    func multipleMonthDays() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [1, 15])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYMONTHDAY=1,15")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes multiple months")
    func multipleMonths() {
        let rule = RecurrenceRule(frequency: .yearly, byMonth: [.march, .september])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=YEARLY;BYMONTH=3,9")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes a specific-weekday positional day as ordinal BYDAY")
    func positionalSpecificWeekday() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .second, dayType: .weekday(.tuesday))])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYDAY=2TU")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes multiple specific-weekday positional days together")
    func positionalMultipleSpecificWeekdays() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [
            PositionalDay(position: .first, dayType: .weekday(.monday)),
            PositionalDay(position: .last, dayType: .weekday(.friday))
        ])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYDAY=1MO,-1FR")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes a generic weekday-only positional day via BYSETPOS")
    func positionalWeekdayOnly() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .weekdayOnly)])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes a generic weekend-day positional day via BYSETPOS")
    func positionalWeekendDay() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .first, dayType: .weekendDay)])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYDAY=SA,SU;BYSETPOS=1")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes an anyDay positional day as BYMONTHDAY")
    func positionalAnyDay() {
        // .anyDay is only ever paired with .last (see OnWeekPickerView in Task 9) - any other
        // position would encode as a plain positive BYMONTHDAY, indistinguishable on decode from
        // a non-positional byMonthDay rule. .last's negative encoding is what makes it unambiguous.
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .anyDay)])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYMONTHDAY=-1")
        #expect(RRuleCodec.decode(encoded) == rule)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && swift test --filter RRuleCodecTests`
Expected: FAIL — `encode`/`decode` don't yet handle lists, `BYSETPOS`, ordinal `BYDAY`, or negative `BYMONTHDAY`.

- [ ] **Step 3: Rewrite `RRuleCodec`**

```swift
// ios/Sources/StarkKit/ICS/RRuleCodec.swift
import Foundation

public enum RRuleCodec {
    private static let dayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    private static let weekdayOnlyCodes = ["MO", "TU", "WE", "TH", "FR"]
    private static let weekendDayCodes = ["SA", "SU"]

    public static func encode(_ rule: RecurrenceRule) -> String {
        var parts = ["FREQ=\(rule.frequency.rawValue.uppercased())"]
        if rule.interval != 1 { parts.append("INTERVAL=\(rule.interval)") }

        // Plain weekly BYDAY (unchanged from before this plan) is independent of the
        // monthly/yearly positional-vs-plain-day-of-month branch below - a rule only ever
        // has one of byDay (weekly) or byPositionalDay/byMonthDay (monthly/yearly) set.
        if let byDay = rule.byDay, !byDay.isEmpty {
            parts.append("BYDAY=" + byDay.map { dayCodes[$0.rawValue] }.joined(separator: ","))
        }

        if let positionalDays = rule.byPositionalDay, !positionalDays.isEmpty {
            encodePositionalDays(positionalDays, into: &parts)
        } else if let byMonthDay = rule.byMonthDay, !byMonthDay.isEmpty {
            parts.append("BYMONTHDAY=" + byMonthDay.map(String.init).joined(separator: ","))
        }

        if let byMonth = rule.byMonth, !byMonth.isEmpty {
            parts.append("BYMONTH=" + byMonth.map { String($0.rawValue) }.joined(separator: ","))
        }
        if let count = rule.count { parts.append("COUNT=\(count)") }
        if let until = rule.until { parts.append("UNTIL=\(ICSDateFormat.format(until, allDay: true))") }
        return parts.joined(separator: ";")
    }

    private static func encodePositionalDays(_ positionalDays: [PositionalDay], into parts: inout [String]) {
        // A generic day-type (anyDay/weekdayOnly/weekendDay) is always the sole entry
        // in the list (enforced by the picker UI) - no mixing with specific weekdays.
        guard let first = positionalDays.first else { return }
        switch first.dayType {
        case .anyDay:
            // Only .last is ever paired with .anyDay (enforced by OnWeekPickerView) - any other
            // position would produce a positive BYMONTHDAY indistinguishable from a plain
            // byMonthDay rule on decode. .last's negative encoding is what makes it unambiguous.
            parts.append("BYMONTHDAY=\(first.position.rawValue)")
        case .weekdayOnly:
            parts.append("BYDAY=" + weekdayOnlyCodes.joined(separator: ","))
            parts.append("BYSETPOS=\(first.position.rawValue)")
        case .weekendDay:
            parts.append("BYDAY=" + weekendDayCodes.joined(separator: ","))
            parts.append("BYSETPOS=\(first.position.rawValue)")
        case .weekday:
            let entries = positionalDays.compactMap { entry -> String? in
                guard case .weekday(let w) = entry.dayType else { return nil }
                return "\(entry.position.rawValue)\(dayCodes[w.rawValue])"
            }
            parts.append("BYDAY=" + entries.joined(separator: ","))
        }
    }

    public static func decode(_ value: String) -> RecurrenceRule? {
        var frequency: RecurrenceRule.Frequency?
        var interval = 1
        var byMonthDayRaw: [Int]?
        var byMonth: [Month]?
        var byDayRaw: [String]?
        var bySetPos: Int?
        var count: Int?
        var until: Date?

        for pair in value.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "FREQ": frequency = RecurrenceRule.Frequency(rawValue: kv[1].lowercased())
            case "INTERVAL": interval = Int(kv[1]) ?? 1
            case "BYDAY": byDayRaw = kv[1].split(separator: ",").map(String.init)
            case "BYMONTHDAY": byMonthDayRaw = kv[1].split(separator: ",").compactMap { Int($0) }
            case "BYMONTH": byMonth = kv[1].split(separator: ",").compactMap { Int($0).flatMap(Month.init) }
            case "BYSETPOS": bySetPos = Int(kv[1])
            case "COUNT": count = Int(kv[1])
            case "UNTIL": until = ICSDateFormat.parse(String(kv[1]))?.date
            default: break
            }
        }
        guard let frequency else { return nil }

        let (byPositionalDay, byMonthDay) = decodeDaySpecifier(byDayRaw: byDayRaw, byMonthDayRaw: byMonthDayRaw, bySetPos: bySetPos)

        return RecurrenceRule(
            frequency: frequency, interval: interval,
            byDay: frequency == .weekly ? byDayRaw?.compactMap { dayCodes.firstIndex(of: $0).flatMap(Weekday.init) } : nil,
            byMonthDay: byMonthDay, byPositionalDay: byPositionalDay, byMonth: byMonth,
            count: count, until: until
        )
    }

    private static func decodeDaySpecifier(byDayRaw: [String]?, byMonthDayRaw: [Int]?, bySetPos: Int?) -> (positional: [PositionalDay]?, monthDay: [Int]?) {
        // Ordinal BYDAY (e.g. "2TU", "-1FR") with no BYSETPOS: specific-weekday positional entries.
        if let byDayRaw, bySetPos == nil, byDayRaw.allSatisfy({ $0.count > 2 }) {
            let entries = byDayRaw.compactMap { token -> PositionalDay? in
                let code = String(token.suffix(2))
                let ordinalString = String(token.dropLast(2))
                guard let weekdayIndex = dayCodes.firstIndex(of: code),
                      let ordinal = Int(ordinalString),
                      let position = Position(rawValue: ordinal) else { return nil }
                return PositionalDay(position: position, dayType: .weekday(Weekday(rawValue: weekdayIndex)!))
            }
            return (entries, nil)
        }
        // BYDAY + BYSETPOS: a generic day-type positional entry.
        if let byDayRaw, let bySetPos, let position = Position(rawValue: bySetPos) {
            let dayType: DayTypeOrWeekday
            if Set(byDayRaw) == Set(weekdayOnlyCodes) { dayType = .weekdayOnly }
            else if Set(byDayRaw) == Set(weekendDayCodes) { dayType = .weekendDay }
            else { return (nil, byMonthDayRaw) }
            return ([PositionalDay(position: position, dayType: dayType)], nil)
        }
        // A single negative BYMONTHDAY with no BYDAY: an anyDay positional entry.
        if let byMonthDayRaw, byMonthDayRaw.count == 1, let position = Position(rawValue: byMonthDayRaw[0]), position == .last || byMonthDayRaw[0] < 0 {
            return ([PositionalDay(position: position, dayType: .anyDay)], nil)
        }
        return (nil, byMonthDayRaw)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios && swift test --filter RRuleCodecTests`
Expected: PASS, all 7 tests green.

- [ ] **Step 5: Run the full suite**

Run: `cd ios && swift test`
Expected: all tests pass, including the existing `ICSSerializerTests`/`ICSParserTests` round-trips (which exercise the simpler, non-positional paths through this same code).

- [ ] **Step 6: Commit**

```bash
cd ios && git add Sources/StarkKit/ICS/RRuleCodec.swift Tests/StarkKitTests/RRuleCodecTests.swift
git commit -m "feat: RRuleCodec encodes/decodes multi-value and positional recurrence"
```

---

## Part B — SwiftUI picker views (manually verified, matching the app's established pattern)

### Task 6: `RepeatPickerView` — presets

**Files:**
- Create: `ios/App/Stark/Stark/RepeatPickerView.swift`

**Interfaces:**
- Consumes: `RecurrenceRule` (from `StarkKit`)
- Produces: `RepeatPickerView(recurrence: Binding<RecurrenceRule?>)` — a `View`

- [ ] **Step 1: Write the view**

```swift
// ios/App/Stark/Stark/RepeatPickerView.swift
import SwiftUI
import StarkKit

enum RepeatPreset: String, CaseIterable, Identifiable {
    case never = "Never"
    case everyDay = "Every Day"
    case everyWeek = "Every Week"
    case every2Weeks = "Every 2 Weeks"
    case everyMonth = "Every Month"
    case everyYear = "Every Year"
    case custom = "Custom"

    var id: String { rawValue }

    var rule: RecurrenceRule? {
        switch self {
        case .never: return nil
        case .everyDay: return RecurrenceRule(frequency: .daily)
        case .everyWeek: return RecurrenceRule(frequency: .weekly)
        case .every2Weeks: return RecurrenceRule(frequency: .weekly, interval: 2)
        case .everyMonth: return RecurrenceRule(frequency: .monthly)
        case .everyYear: return RecurrenceRule(frequency: .yearly)
        case .custom: return nil
        }
    }
}

struct RepeatPickerView: View {
    @Binding var recurrence: RecurrenceRule?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(RepeatPreset.allCases) { preset in
                if preset == .custom {
                    NavigationLink(preset.rawValue) {
                        CustomRepeatView(recurrence: $recurrence)
                    }
                    .foregroundStyle(Colors.text)
                } else {
                    Button {
                        recurrence = preset.rule
                        dismiss()
                    } label: {
                        HStack {
                            Text(preset.rawValue).foregroundStyle(Colors.text)
                            Spacer()
                            if preset.rule == recurrence {
                                Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Repeat")
    }
}
```

- [ ] **Step 2: Verify it compiles**

This view references `CustomRepeatView`, created in Task 7 — the package will not build until then. Skip the build check for this task; it runs at the end of Task 7 instead. Commit now regardless (a later task can still amend/build on top of an uncompiled intermediate state, since the whole plan lands as a sequence of commits reviewed individually).

- [ ] **Step 3: Commit**

```bash
cd ios && git add App/Stark/Stark/RepeatPickerView.swift
git commit -m "feat: add RepeatPickerView with recurrence presets"
```

---

### Task 7: `CustomRepeatView` — interval wheel, contextual sections, Ends

**Files:**
- Create: `ios/App/Stark/Stark/CustomRepeatView.swift`

**Interfaces:**
- Consumes: `RecurrenceRule`, `Weekday`, `Month` (from `StarkKit`); `OnDaysPickerView`, `OnWeekPickerView` (Tasks 8-9 — this view will not build until those exist; same non-blocking-commit note as Task 6 applies)
- Produces: `CustomRepeatView(recurrence: Binding<RecurrenceRule?>)` — a `View`

- [ ] **Step 1: Write the view**

```swift
// ios/App/Stark/Stark/CustomRepeatView.swift
import SwiftUI
import StarkKit

struct CustomRepeatView: View {
    @Binding var recurrence: RecurrenceRule?

    @State private var interval: Int
    @State private var unit: RecurrenceRule.Frequency
    @State private var byDay: Set<Weekday>
    @State private var byMonth: Set<Month>
    @State private var byMonthDay: [Int]?
    @State private var byPositionalDay: [PositionalDay]?
    @State private var endMode: EndMode
    @State private var untilDate: Date
    @State private var occurrenceCount: Int

    enum EndMode: String, CaseIterable, Identifiable {
        case never = "Never", onDate = "On Date", afterCount = "After"
        var id: String { rawValue }
    }

    init(recurrence: Binding<RecurrenceRule?>) {
        _recurrence = recurrence
        let existing = recurrence.wrappedValue
        _interval = State(initialValue: existing?.interval ?? 1)
        _unit = State(initialValue: existing?.frequency ?? .daily)
        _byDay = State(initialValue: Set(existing?.byDay ?? []))
        _byMonth = State(initialValue: Set(existing?.byMonth ?? []))
        _byMonthDay = State(initialValue: existing?.byMonthDay)
        _byPositionalDay = State(initialValue: existing?.byPositionalDay)
        _untilDate = State(initialValue: existing?.until ?? Date())
        _occurrenceCount = State(initialValue: existing?.count ?? 1)
        if existing?.until != nil {
            _endMode = State(initialValue: .onDate)
        } else if existing?.count != nil {
            _endMode = State(initialValue: .afterCount)
        } else {
            _endMode = State(initialValue: .never)
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Repeat").foregroundStyle(Colors.text)
                    Spacer()
                    Text(summary).foregroundStyle(Colors.textSecondary)
                }
            }

            Section {
                HStack {
                    Picker("Interval", selection: $interval) {
                        ForEach(1..<100, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()

                    Picker("Unit", selection: $unit) {
                        Text("day").tag(RecurrenceRule.Frequency.daily)
                        Text("week").tag(RecurrenceRule.Frequency.weekly)
                        Text("month").tag(RecurrenceRule.Frequency.monthly)
                        Text("year").tag(RecurrenceRule.Frequency.yearly)
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }
                .frame(height: 216)
            }

            if unit == .weekly {
                Section("On Days") {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Button {
                            toggle(day)
                        } label: {
                            HStack {
                                Text(dayName(day)).foregroundStyle(Colors.text)
                                Spacer()
                                if byDay.contains(day) {
                                    Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                                }
                            }
                        }
                    }
                }
            }

            if unit == .monthly || unit == .yearly {
                if unit == .yearly {
                    Section("On Months") {
                        ForEach(Month.allCases, id: \.self) { month in
                            Button {
                                toggleMonth(month)
                            } label: {
                                HStack {
                                    Text(monthName(month)).foregroundStyle(Colors.text)
                                    Spacer()
                                    if byMonth.contains(month) {
                                        Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        OnDaysPickerView(selectedDays: Binding(
                            get: { Set(byMonthDay ?? []) },
                            set: { newValue in
                                byMonthDay = newValue.isEmpty ? nil : Array(newValue).sorted()
                                if byMonthDay != nil { byPositionalDay = nil }
                            }
                        ))
                    } label: {
                        HStack {
                            Text("On Days").foregroundStyle(Colors.text)
                            Spacer()
                            Text(onDaysSummary).foregroundStyle(Colors.textSecondary)
                        }
                    }

                    NavigationLink {
                        OnWeekPickerView(entries: Binding(
                            get: { byPositionalDay ?? [] },
                            set: { newValue in
                                byPositionalDay = newValue.isEmpty ? nil : newValue
                                if byPositionalDay != nil { byMonthDay = nil }
                            }
                        ))
                    } label: {
                        HStack {
                            Text("On Week").foregroundStyle(Colors.text)
                            Spacer()
                            Text(onWeekSummary).foregroundStyle(Colors.textSecondary)
                        }
                    }
                }
            }

            Section("Ends") {
                Picker("Ends", selection: $endMode) {
                    ForEach(EndMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if endMode == .onDate {
                    DatePicker("Date", selection: $untilDate, displayedComponents: .date)
                } else if endMode == .afterCount {
                    Stepper("After \(occurrenceCount) times", value: $occurrenceCount, in: 1...999)
                }
            }
        }
        .navigationTitle("Custom")
        .onChange(of: interval) { _, _ in commit() }
        .onChange(of: unit) { _, _ in commit() }
        .onChange(of: byDay) { _, _ in commit() }
        .onChange(of: byMonth) { _, _ in commit() }
        .onChange(of: byMonthDay) { _, _ in commit() }
        .onChange(of: byPositionalDay) { _, _ in commit() }
        .onChange(of: endMode) { _, _ in commit() }
        .onChange(of: untilDate) { _, _ in commit() }
        .onChange(of: occurrenceCount) { _, _ in commit() }
        .onAppear { commit() }
    }

    private func toggle(_ day: Weekday) {
        if byDay.contains(day) { byDay.remove(day) } else { byDay.insert(day) }
    }

    private func toggleMonth(_ month: Month) {
        if byMonth.contains(month) { byMonth.remove(month) } else { byMonth.insert(month) }
    }

    private func commit() {
        recurrence = RecurrenceRule(
            frequency: unit,
            interval: interval,
            byDay: unit == .weekly && !byDay.isEmpty ? Array(byDay).sorted { $0.rawValue < $1.rawValue } : nil,
            byMonthDay: byMonthDay,
            byPositionalDay: byPositionalDay,
            byMonth: unit == .yearly && !byMonth.isEmpty ? Array(byMonth).sorted { $0.rawValue < $1.rawValue } : nil,
            count: endMode == .afterCount ? occurrenceCount : nil,
            until: endMode == .onDate ? untilDate : nil
        )
    }

    private var summary: String {
        "Every \(interval == 1 ? "" : "\(interval) ")\(unitLabel)\(interval == 1 ? "" : "s")"
    }

    private var unitLabel: String {
        switch unit {
        case .daily: return "day"
        case .weekly: return "week"
        case .monthly: return "month"
        case .yearly: return "year"
        }
    }

    private var onDaysSummary: String {
        guard let byMonthDay, !byMonthDay.isEmpty else { return "None" }
        return byMonthDay.map(String.init).joined(separator: ", ")
    }

    private var onWeekSummary: String {
        guard let byPositionalDay, !byPositionalDay.isEmpty else { return "None" }
        return "\(byPositionalDay.count) rule\(byPositionalDay.count == 1 ? "" : "s")"
    }

    private func dayName(_ day: Weekday) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day.rawValue]
    }

    private func monthName(_ month: Month) -> String {
        ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"][month.rawValue - 1]
    }
}
```

Note: `.onAppear { commit() }` ensures navigating into this screen immediately reflects a valid `RecurrenceRule` in the binding (matching whatever the initial wheel/section state resolves to), rather than leaving the caller's `recurrence` at its prior value until the user changes something.

- [ ] **Step 2: Commit**

(Build verification happens at the end of Task 9, once `OnDaysPickerView`/`OnWeekPickerView` exist.)

```bash
cd ios && git add App/Stark/Stark/CustomRepeatView.swift
git commit -m "feat: add CustomRepeatView with interval wheel and contextual sections"
```

---

### Task 8: `OnDaysPickerView` — day-of-month multi-select

**Files:**
- Create: `ios/App/Stark/Stark/OnDaysPickerView.swift`

**Interfaces:**
- Produces: `OnDaysPickerView(selectedDays: Binding<Set<Int>>)` — a `View`

- [ ] **Step 1: Write the view**

```swift
// ios/App/Stark/Stark/OnDaysPickerView.swift
import SwiftUI

struct OnDaysPickerView: View {
    @Binding var selectedDays: Set<Int>

    var body: some View {
        List {
            ForEach(1...31, id: \.self) { day in
                Button {
                    toggle(day)
                } label: {
                    HStack {
                        Text("\(day)").foregroundStyle(Colors.text)
                        Spacer()
                        if selectedDays.contains(day) {
                            Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle("On Days")
    }

    private func toggle(_ day: Int) {
        if selectedDays.contains(day) { selectedDays.remove(day) } else { selectedDays.insert(day) }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd ios && git add App/Stark/Stark/OnDaysPickerView.swift
git commit -m "feat: add OnDaysPickerView for multi-day-of-month selection"
```

---

### Task 9: `OnWeekPickerView` — positional-day rule management

**Files:**
- Create: `ios/App/Stark/Stark/OnWeekPickerView.swift`

**Interfaces:**
- Consumes: `PositionalDay`, `Position`, `DayTypeOrWeekday`, `Weekday` (from `StarkKit`)
- Produces: `OnWeekPickerView(entries: Binding<[PositionalDay]>)` — a `View`

- [ ] **Step 1: Write the view**

```swift
// ios/App/Stark/Stark/OnWeekPickerView.swift
import SwiftUI
import StarkKit

struct OnWeekPickerView: View {
    @Binding var entries: [PositionalDay]

    private var hasGenericEntry: Bool {
        entries.contains { if case .weekday = $0.dayType { return false } else { return true } }
    }

    private func isAnyDay(_ dayType: DayTypeOrWeekday) -> Bool {
        if case .anyDay = dayType { return true }
        return false
    }

    var body: some View {
        Form {
            ForEach(entries.indices, id: \.self) { index in
                Section {
                    Picker("Position", selection: Binding(
                        get: { entries[index].position },
                        set: { entries[index].position = $0 }
                    )) {
                        Text("First").tag(Position.first)
                        Text("Second").tag(Position.second)
                        Text("Third").tag(Position.third)
                        Text("Fourth").tag(Position.fourth)
                        Text("Last").tag(Position.last)
                    }
                    // "Day" only ever pairs with "Last" - any other position would encode as a
                    // plain BYMONTHDAY indistinguishable from a non-positional day-of-month rule
                    // on decode (see RRuleCodec's encoding notes), and is redundant with "On Days"
                    // anyway ("the 2nd day of the month" is just byMonthDay: [2]).
                    .disabled(isAnyDay(entries[index].dayType))

                    Picker("Day", selection: Binding(
                        get: { entries[index].dayType },
                        set: { newValue in
                            entries[index].dayType = newValue
                            switch newValue {
                            case .anyDay:
                                // The only unambiguous pairing - force position to .last.
                                entries[index].position = .last
                                entries = [entries[index]]
                            case .weekdayOnly, .weekendDay:
                                // Also must be the sole entry (see RRULE encoding constraint in the spec).
                                entries = [entries[index]]
                            case .weekday:
                                break
                            }
                        }
                    )) {
                        Text("Sunday").tag(DayTypeOrWeekday.weekday(.sunday))
                        Text("Monday").tag(DayTypeOrWeekday.weekday(.monday))
                        Text("Tuesday").tag(DayTypeOrWeekday.weekday(.tuesday))
                        Text("Wednesday").tag(DayTypeOrWeekday.weekday(.wednesday))
                        Text("Thursday").tag(DayTypeOrWeekday.weekday(.thursday))
                        Text("Friday").tag(DayTypeOrWeekday.weekday(.friday))
                        Text("Saturday").tag(DayTypeOrWeekday.weekday(.saturday))
                        Text("Day").tag(DayTypeOrWeekday.anyDay)
                        Text("Weekday").tag(DayTypeOrWeekday.weekdayOnly)
                        Text("Weekend Day").tag(DayTypeOrWeekday.weekendDay)
                    }

                    Button("Remove", role: .destructive) {
                        entries.remove(at: index)
                    }
                }
            }

            if !hasGenericEntry {
                Button("Add Rule") {
                    entries.append(PositionalDay(position: .first, dayType: .weekday(.sunday)))
                }
            }
        }
        .navigationTitle("On Week")
    }
}
```

- [ ] **Step 2: Build the app**

Run: `cd ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -destination "generic/platform=iOS Simulator" build`
Expected: `BUILD SUCCEEDED`. This is the first build check since Task 6 — if it fails, work through the compile errors across `RepeatPickerView`/`CustomRepeatView`/`OnDaysPickerView`/`OnWeekPickerView` together (they're interdependent). A likely gotcha: `Picker` selection values (`Position`, `DayTypeOrWeekday`, `RecurrenceRule.Frequency`) must be `Hashable` — confirm `RecurrenceRule.Frequency` already has it (it does, via `Equatable` + enum synthesis is NOT automatic for `Hashable` either — if the build complains about `Frequency` specifically, add `Hashable` to its declaration in `RecurrenceRule.swift` the same way Task 1 added it to `Weekday`).

- [ ] **Step 3: Commit**

```bash
cd ios && git add App/Stark/Stark/OnWeekPickerView.swift
git commit -m "feat: add OnWeekPickerView for positional recurrence rule management"
```

---

### Task 10: Wire the picker into `AddItemView`

**Files:**
- Modify: `ios/App/Stark/Stark/AddItemView.swift`

**Interfaces:**
- Consumes: `RepeatPickerView`, `RecurrenceRule` (from `StarkKit`)

- [ ] **Step 1: Add the Repeat row and recurrence state**

Add a `@State private var recurrence: RecurrenceRule?` property, and a `NavigationLink` row into the existing `Form` (placed after the date field, before the toolbar):

```swift
NavigationLink {
    RepeatPickerView(recurrence: $recurrence)
} label: {
    HStack {
        Text("Repeat")
        Spacer()
        Text(recurrenceSummary).foregroundStyle(Colors.textSecondary)
    }
}
```

Add a computed property for the row's summary label:

```swift
private var recurrenceSummary: String {
    guard let recurrence else { return "Never" }
    switch (recurrence.frequency, recurrence.interval) {
    case (.daily, 1): return "Every Day"
    case (.weekly, 1): return "Every Week"
    case (.weekly, 2): return "Every 2 Weeks"
    case (.monthly, 1): return "Every Month"
    case (.yearly, 1): return "Every Year"
    default: return "Custom"
    }
}
```

Update `add()` to pass `recurrence` through to both branches:

```swift
private func add() {
    switch kind {
    case .event:
        store.addEvent(Event(title: title, start: date, recurrence: recurrence))
    case .reminder:
        store.addReminder(Reminder(title: title, dueDate: date, recurrence: recurrence))
    }
    dismiss()
}
```

- [ ] **Step 2: Build the app**

Run: `cd ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -destination "generic/platform=iOS Simulator" build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual verification in the simulator**

Run the app in Xcode (⌘R) or via a simulator install. Verify:
1. Add an Event, tap Repeat → Every Week — the row now shows "Every Week"; save it; confirm (via a second app launch, or by checking the `.ics` file directly) that `recurring.ics` now contains a `VEVENT` with `RRULE:FREQ=WEEKLY`.
2. Tap Repeat → Custom → set 2nd Tuesday of every month (unit=month, On Week → Second/Tuesday) — confirm the resulting rule persists and that the item appears in the agenda on the correct dates across at least two different months.
3. Tap Repeat → Never after having set a custom rule — confirm the row reverts to "Never" and the saved item has no recurrence.

- [ ] **Step 4: Commit**

```bash
cd ios && git add App/Stark/Stark/AddItemView.swift
git commit -m "feat: wire RepeatPickerView into AddItemView"
```
