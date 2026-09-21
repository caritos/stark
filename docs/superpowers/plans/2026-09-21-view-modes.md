# Week / Month / Year View Modes with a Drag Bar (issue #95) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Like Fantastical, a small drag bar between the month grid and the agenda switches the calendar between three modes: **week** (the grid collapses to one week row), **month** (today's grid + agenda) and **year** (twelve mini-months with busy days tinted; tapping a day jumps to it).

**Architecture:** The decisions live in small pure StarkKit pieces (`CalendarMode` and its drag rule, `MonthGrid.weekRow`/`weekStepped`, `YearGrid.range`, `yearDensity`, `DayDensity.level`). `ContentView` owns the mode; `MonthGridView` renders month or week; a new `ModeHandle` is the drag bar; a new `YearView` is the year mode.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM package `StarkKit` tested with Swift Testing (`import Testing`, `@Test`, `#expect`; never XCTest).

**Issue:** https://github.com/caritos/todo-txt/issues/95 (Fantastical screenshots: a year view of twelve months with busy days tinted yellow and a chevron at the bottom to return; the month grid with a small grey drag bar under it; and the collapsed state).

**Design (approved in conversation 2026-09-21):**
- **Modes**, ordered smallest to largest: `week` < `month` < `year`. The default is `month` (today's screen). Not persisted across launches.
- **Drag bar**: a thin flat bar (hard edges, no rounded pill) in a full-width strip between the grid and the agenda. Dragging **up** collapses (year -> month -> week); dragging **down** expands (week -> month -> year). The switch happens **on release**: travel of at least 30 points, or a predicted travel of at least 100 points for a short fling; the mode change is animated (`withAnimation`), the grid does not follow the finger live. A drag past an end mode does nothing. Tapping the bar in year mode returns to month. VoiceOver: the bar is one adjustable element ("Calendar view", value "Week"/"Month"/"Year"; swipe up/down changes mode).
- **Week mode**: `MonthGridView` shows only the week row containing the selected day (Sunday-first, same day cell as month mode, with its density markers); the agenda takes the freed space. The header title shows the selected day's month; the chevrons step by a week (`MonthGrid.weekStepped`) via `onSelectDate`, which scrolls the agenda. Tapping a day works as in month mode. Neighbouring-month days in the row are dimmed.
- **Month <-> week sync**: `visibleMonth` follows the selected day's month when entering week mode, while in week mode as the selected day changes, and when returning to month mode.
- **Year mode** replaces grid and agenda: a year title (`2026`) with ‹ › chevrons (previous/next year), then a scrolling two-column grid of twelve mini-months (month name, S M T W T F S row, 6 week rows of `MonthGrid.days(for:)`). Days with items are tinted with `Colors.accent` at three strengths by `DayDensity.level` (1 = light, 2 = medium, 3 = strong; opacities 0.15 / 0.30 / 0.50); neighbouring-month days are dimmed and never tinted; today has the filled accent square. Tapping a day sets the selection, returns to month mode and scrolls the agenda to it (`ContentView.selectDate`). The drag bar sits at the bottom of the year view. Which year is shown starts as the selected day's year.
- **Level rule**: total = tasks + events; 0 -> 0, 1 -> 1, 2...3 -> 2, 4 or more -> 3.
- Counting rules are the grid's: built on `buildAgendaItems`; an overdue reminder counts on today's day only when today is inside the range.
- **Out of scope:** the strip of only-event-days from Fantastical's collapsed screenshot, live finger tracking, pinch to zoom, weather, persisting the mode, week numbers, changing marker style.

## Global Constraints

- **Working directory:** `/Users/eladio/src/todo-txt/.claude/worktrees/view-modes` (a git worktree, branch `worktree-view-modes`). Use absolute paths; run Swift tests from its `ios/` directory (`swift test`).
- **Shell:** compound commands and heredocs may be rejected. Use plain single commands, the Write/Edit tools for files, `git -C <worktree>` and multiple `-m` flags for commits.
- **Commits:** stage specific paths only (never `git add -A`, `.` or `commit -a`). End every commit message with a separate `-m` paragraph: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Never push.
- **Logic goes in StarkKit, views are thin.** If it can be tested, it lives in `ios/Sources/StarkKit` with a Swift Testing test.
- **Tests first** for StarkKit work: write the failing test, run it and see it fail for the stated reason, then implement.
- **Baseline:** `swift test` currently passes 284 tests (three env-gated parity tests are skipped by design). It must stay green after every task.
- **Dates:** never build inclusive day-range bounds from `DateMath.date(from:)` (it is local noon); use `Calendar.startOfDay` and step with the calendar (`MonthGrid.range`, `AgendaWindow` do). Cell dates come from `DateMath` (time zone = `TimeZone.current`); an injected calendar must share it.
- **Theme:** only `Colors.*`, `Spacing.*`, `Fonts.mono` from `Theme.swift`; no hardcoded hex, no new colours (opacity variants of `Colors.accent` are allowed for the year tint), no rounded corners (hard edges).
- **Do not touch the author's phone** (no `xcrun devicectl`, no `deploy.sh`); the controller does the on-device check.
- **App build check** (Tasks 3 and 4): `cd /Users/eladio/src/todo-txt/.claude/worktrees/view-modes/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` must end in `** BUILD SUCCEEDED **`.
- **Existing behaviour to preserve:** in month mode the grid must behave exactly as after issue #96 (neighbouring-month days, tap scrolls the agenda without paging, chevrons page months); the store must have loaded every month a visible grid touches (`store.loadMonths(covering:)`), or its markers silently vanish.

---

### Task 1: `CalendarMode` and the week row (StarkKit)

**Files:**
- Create: `ios/Sources/StarkKit/Planner/CalendarMode.swift`
- Modify: `ios/Sources/StarkKit/Planner/MonthGrid.swift` (add `weekRow(containing:)` and `weekStepped(_:by:)` to `MonthGrid`)
- Create tests: `ios/Tests/StarkKitTests/CalendarModeTests.swift`, `ios/Tests/StarkKitTests/WeekRowTests.swift`

**Interfaces:**
- Produces (used by Tasks 3-4):
  - `public enum CalendarMode: Equatable, Sendable { case week, month, year }` with `expanded: CalendarMode?`, `collapsed: CalendarMode?`, `title: String`, `static let dragThreshold: Double = 30`, `static let flingThreshold: Double = 100`, `func afterDrag(translation: Double, predictedEnd: Double) -> CalendarMode`.
  - `MonthGrid.weekRow(containing date: Date) -> [GridDay]` (7 cells, Sunday-first; `isInMonth` is relative to the month of `date`), `MonthGrid.weekStepped(_ date: Date, by weeks: Int) -> Date` (local noon of the day `7 * weeks` days away).

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/StarkKitTests/CalendarModeTests.swift`:

```swift
// ios/Tests/StarkKitTests/CalendarModeTests.swift
import Testing
@testable import StarkKit

@Suite("CalendarMode")
struct CalendarModeTests {
    @Test("expanding and collapsing walk week <-> month <-> year and stop at the ends")
    func walk() {
        #expect(CalendarMode.week.expanded == .month)
        #expect(CalendarMode.month.expanded == .year)
        #expect(CalendarMode.year.expanded == nil)
        #expect(CalendarMode.year.collapsed == .month)
        #expect(CalendarMode.month.collapsed == .week)
        #expect(CalendarMode.week.collapsed == nil)
    }

    @Test("a drag past the distance threshold changes the mode: down expands, up collapses")
    func dragByDistance() {
        #expect(CalendarMode.month.afterDrag(translation: 40, predictedEnd: 40) == .year)
        #expect(CalendarMode.month.afterDrag(translation: -40, predictedEnd: -40) == .week)
        #expect(CalendarMode.week.afterDrag(translation: 40, predictedEnd: 40) == .month)
        #expect(CalendarMode.year.afterDrag(translation: -40, predictedEnd: -40) == .month)
        #expect(CalendarMode.month.afterDrag(translation: CalendarMode.dragThreshold, predictedEnd: 0) == .year)
    }

    @Test("a short, slow drag changes nothing")
    func shortDrag() {
        #expect(CalendarMode.month.afterDrag(translation: 10, predictedEnd: 20) == .month)
        #expect(CalendarMode.month.afterDrag(translation: -10, predictedEnd: -20) == .month)
        #expect(CalendarMode.month.afterDrag(translation: 29.9, predictedEnd: 99.9) == .month)
    }

    @Test("a short but fast fling changes the mode by its predicted travel")
    func fling() {
        #expect(CalendarMode.month.afterDrag(translation: 12, predictedEnd: 150) == .year)
        #expect(CalendarMode.month.afterDrag(translation: -12, predictedEnd: -150) == .week)
        #expect(CalendarMode.month.afterDrag(translation: 0, predictedEnd: CalendarMode.flingThreshold) == .year)
    }

    @Test("a drag past an end mode stays put")
    func ends() {
        #expect(CalendarMode.year.afterDrag(translation: 40, predictedEnd: 40) == .year)
        #expect(CalendarMode.week.afterDrag(translation: -40, predictedEnd: -40) == .week)
    }

    @Test("titles are what VoiceOver reads")
    func titles() {
        #expect(CalendarMode.week.title == "Week")
        #expect(CalendarMode.month.title == "Month")
        #expect(CalendarMode.year.title == "Year")
    }
}
```

Create `ios/Tests/StarkKitTests/WeekRowTests.swift`:

```swift
// ios/Tests/StarkKitTests/WeekRowTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("MonthGrid.weekRow")
struct WeekRowTests {
    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }

    @Test("the row of a mid-month date is its Sunday-first week, all in the month")
    func midMonth() {
        let row = MonthGrid.weekRow(containing: d("2026-09-21"))

        #expect(row.map(\.iso) == ["2026-09-20", "2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25", "2026-09-26"])
        #expect(row.allSatisfy(\.isInMonth))
    }

    @Test("a week that straddles two months flags the days of the other month, relative to the date's month")
    func straddlingMonths() {
        let september = MonthGrid.weekRow(containing: d("2026-09-01"))
        #expect(september.map(\.iso) == ["2026-08-30", "2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"])
        #expect(september.map(\.isInMonth) == [false, false, true, true, true, true, true])

        let august = MonthGrid.weekRow(containing: d("2026-08-31"))
        #expect(august.map(\.iso) == september.map(\.iso))
        #expect(august.map(\.isInMonth) == [true, true, false, false, false, false, false])
    }

    @Test("a Sunday starts its own row and a Saturday ends it")
    func weekBoundaries() {
        #expect(MonthGrid.weekRow(containing: d("2026-09-20")).first?.iso == "2026-09-20")
        #expect(MonthGrid.weekRow(containing: d("2026-09-26")).first?.iso == "2026-09-20")
        #expect(MonthGrid.weekRow(containing: d("2026-09-26")).last?.iso == "2026-09-26")
    }

    @Test("the row crosses the year boundary")
    func yearBoundary() {
        let row = MonthGrid.weekRow(containing: d("2026-12-31"))

        #expect(row.first?.iso == "2026-12-27")
        #expect(row.last?.iso == "2027-01-02")
        #expect(row.map(\.isInMonth) == [true, true, true, true, true, false, false])
    }

    @Test("weekStepped moves by whole weeks across month and year boundaries and returns local noon")
    func stepped() {
        #expect(MonthGrid.weekStepped(d("2026-09-21"), by: 1) == d("2026-09-28"))
        #expect(MonthGrid.weekStepped(d("2026-09-21"), by: -1) == d("2026-09-14"))
        #expect(MonthGrid.weekStepped(d("2026-09-28"), by: 1) == d("2026-10-05"))
        #expect(MonthGrid.weekStepped(d("2026-12-30"), by: 1) == d("2027-01-06"))
        #expect(MonthGrid.weekStepped(d("2026-09-21"), by: 0) == d("2026-09-21"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/view-modes/ios && swift test --filter "CalendarModeTests|WeekRowTests"`
Expected: FAIL to compile — `CalendarMode`, `weekRow`, `weekStepped` not defined.

- [ ] **Step 3: Implement**

Create `ios/Sources/StarkKit/Planner/CalendarMode.swift`:

```swift
// ios/Sources/StarkKit/Planner/CalendarMode.swift

/// How much calendar the screen shows, smallest to largest: one week row, the month grid (with
/// the agenda below), or a whole year. A drag bar between grid and agenda moves between them.
public enum CalendarMode: Equatable, Sendable {
    case week, month, year

    /// The next larger mode (drag down), or nil at the largest.
    public var expanded: CalendarMode? {
        switch self {
        case .week: return .month
        case .month: return .year
        case .year: return nil
        }
    }

    /// The next smaller mode (drag up), or nil at the smallest.
    public var collapsed: CalendarMode? {
        switch self {
        case .year: return .month
        case .month: return .week
        case .week: return nil
        }
    }

    /// What VoiceOver reads as the drag bar's value.
    public var title: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }

    /// Points of vertical travel on release that count as a deliberate drag.
    public static let dragThreshold: Double = 30
    /// Predicted travel (points) that makes a short, fast fling count.
    public static let flingThreshold: Double = 100

    /// The mode after a vertical drag on the bar ends. `translation` is the travel so far and
    /// `predictedEnd` where the gesture would have coasted to (both positive = down). Down
    /// expands, up collapses; a drag past an end mode changes nothing. Travel of at least
    /// `dragThreshold` decides; otherwise a predicted travel of at least `flingThreshold` does;
    /// otherwise nothing changes.
    public func afterDrag(translation: Double, predictedEnd: Double) -> CalendarMode {
        let travel: Double
        if abs(translation) >= Self.dragThreshold {
            travel = translation
        } else if abs(predictedEnd) >= Self.flingThreshold {
            travel = predictedEnd
        } else {
            return self
        }
        return (travel > 0 ? expanded : collapsed) ?? self
    }
}
```

In `MonthGrid.swift`, inside `enum MonthGrid`, add:

```swift
    /// The seven cells of the Sunday-first week containing `date`. `isInMonth` is relative to
    /// `date`'s own month, so the days of a neighbouring month in the same row are flagged.
    public static func weekRow(containing date: Date) -> [GridDay] {
        let iso = DateMath.isoDate(from: date)
        let c = DateMath.components(iso)
        let weekday = DateMath.weekday(year: c.year, month0: c.month0, day: c.day)
        return (0..<7).map { index in
            let day = DateMath.components(DateMath.addDays(iso, index - weekday))
            return GridDay(
                year: day.year,
                month0: day.month0,
                day: day.day,
                isInMonth: day.year == c.year && day.month0 == c.month0
            )
        }
    }

    /// The day `weeks` whole weeks from `date` (negative goes back), as local noon.
    public static func weekStepped(_ date: Date, by weeks: Int) -> Date {
        DateMath.date(from: DateMath.addDays(DateMath.isoDate(from: date), weeks * 7))
    }
```

- [ ] **Step 4: Run to verify pass, then the full suite**

Run: `swift test --filter "CalendarModeTests|WeekRowTests"` → PASS; then `swift test` → all pass (284 + 11 = 295; three env-gated tests skipped). If a date expectation looks wrong, verify the weekday with `DateMath.weekday` before touching the implementation and report any correction.

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/view-modes add ios/Sources/StarkKit/Planner/CalendarMode.swift ios/Sources/StarkKit/Planner/MonthGrid.swift ios/Tests/StarkKitTests/CalendarModeTests.swift ios/Tests/StarkKitTests/WeekRowTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/view-modes commit -m "feat(ios): CalendarMode with its drag rule, and the week row (#95)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Year density (StarkKit)

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/AgendaDensity.swift` (add `DayDensity.level`, `YearGrid`, `yearDensity`; share the counting loop with `gridDensity`)
- Create tests: `ios/Tests/StarkKitTests/YearDensityTests.swift`

**Interfaces:**
- Consumes: `MonthGrid`, `gridDensity`, `buildAgendaItems`, `DateMath`.
- Produces (used by Task 4): `DayDensity.level: Int` (0...3), `YearGrid.range(year: Int, calendar: Calendar = gregorian) -> ClosedRange<Date>` (start of Jan 1 through the last second of Dec 31), `yearDensity(events:reminders:year:today:calendar:) -> [String: DayDensity]` keyed by ISO date, only days of that year with something on them.

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/StarkKitTests/YearDensityTests.swift`:

```swift
// ios/Tests/StarkKitTests/YearDensityTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("yearDensity")
struct YearDensityTests {
    private let cal = Calendar(identifier: .gregorian)
    private var today: Date { DateMath.date(from: "2026-09-20") }

    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }

    @Test("the year range runs from the start of Jan 1 to the last second of Dec 31")
    func range() {
        let range = YearGrid.range(year: 2026)

        #expect(range.lowerBound == cal.startOfDay(for: d("2026-01-01")))
        #expect(range.upperBound == cal.startOfDay(for: d("2027-01-01")).addingTimeInterval(-1))
        #expect(range.contains(d("2026-12-31")))
        #expect(!range.contains(d("2025-12-31")))
        #expect(!range.contains(d("2027-01-01")))
    }

    @Test("counts land on their days across the year and nothing outside the year is counted")
    func countsAcrossTheYear() {
        let events = [
            Event(id: "e0", title: "Last year", start: d("2025-12-31")),
            Event(id: "e1", title: "New Year", start: d("2026-01-01")),
            Event(id: "e2", title: "June", start: d("2026-06-15")),
            Event(id: "e3", title: "New Year's Eve", start: d("2026-12-31")),
            Event(id: "e4", title: "Next year", start: d("2027-01-01")),
        ]
        let reminders = [Reminder(id: "r1", title: "October", dueDate: d("2026-10-05"))]

        let result = yearDensity(events: events, reminders: reminders, year: 2026, today: today)

        #expect(result["2026-01-01"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-06-15"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-10-05"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-12-31"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2025-12-31"] == nil)
        #expect(result["2027-01-01"] == nil)
        #expect(result.count == 4)
    }

    @Test("a weekly event is counted on each of its days")
    func recurringEvent() {
        let weekly = Event(id: "w", title: "Weekly", start: d("2026-01-05"), recurrence: RecurrenceRule(frequency: .weekly))

        let result = yearDensity(events: [weekly], reminders: [], year: 2026, today: today)

        #expect(result["2026-01-05"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-01-12"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-12-28"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-01-06"] == nil)
        #expect(result.count == 52)
    }

    @Test("an overdue reminder counts on today's day when today is in the year, and nowhere otherwise")
    func overdue() {
        let reminders = [Reminder(id: "r1", title: "Missed", dueDate: d("2026-09-01"))]

        let inYear = yearDensity(events: [], reminders: reminders, year: 2026, today: today)
        #expect(inYear["2026-09-20"] == DayDensity(tasks: 1, events: 0))
        #expect(inYear["2026-09-01"] == nil)

        let otherYear = yearDensity(events: [], reminders: reminders, year: 2027, today: today)
        #expect(otherYear.isEmpty)
    }

    @Test("it agrees with gridDensity for the days both cover")
    func agreesWithGridDensity() {
        let events = [
            Event(id: "e1", title: "A", start: d("2026-09-03")),
            Event(id: "e2", title: "B", start: d("2026-09-03")),
            Event(id: "w", title: "Weekly", start: d("2026-09-02"), recurrence: RecurrenceRule(frequency: .weekly)),
        ]
        let reminders = [
            Reminder(id: "r1", title: "Later", dueDate: d("2026-09-28")),
            Reminder(id: "r2", title: "Missed", dueDate: d("2026-09-05")),
        ]

        let year = yearDensity(events: events, reminders: reminders, year: 2026, today: today)
        let grid = gridDensity(events: events, reminders: reminders, month: YearMonth(year: 2026, month0: 8), today: today)

        #expect(!grid.isEmpty)
        for (iso, density) in grid {
            #expect(year[iso] == density)
        }
    }

    @Test("level buckets the total count: 0, 1, 2-3, 4 or more")
    func level() {
        #expect(DayDensity.none.level == 0)
        #expect(DayDensity(tasks: 1, events: 0).level == 1)
        #expect(DayDensity(tasks: 0, events: 1).level == 1)
        #expect(DayDensity(tasks: 1, events: 1).level == 2)
        #expect(DayDensity(tasks: 2, events: 1).level == 2)
        #expect(DayDensity(tasks: 2, events: 2).level == 3)
        #expect(DayDensity(tasks: 5, events: 0).level == 3)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter YearDensityTests`
Expected: FAIL to compile — `YearGrid`, `yearDensity`, `level` not defined.

- [ ] **Step 3: Implement**

In `AgendaDensity.swift`:
1. Inside `DayDensity`, add:

```swift
    /// The tint strength for the year view: the total count bucketed 0, 1, 2-3, 4 or more.
    public var level: Int {
        switch tasks + events {
        case 0: return 0
        case 1: return 1
        case 2...3: return 2
        default: return 3
        }
    }
```

2. Extract the counting loop of `gridDensity` into a private helper and have both call it (behaviour of `gridDensity` unchanged; its existing tests must pass untouched):

```swift
/// The counting rule shared by the grid and the year: per-day task/event counts for every row
/// `buildAgendaItems` produces inside `range`, keyed by ISO date, only days with something.
private func densityCounts(
    events: [Event],
    reminders: [Reminder],
    range: ClosedRange<Date>,
    today: Date,
    calendar: Calendar
) -> [String: DayDensity] { … the existing loop body from gridDensity … }
```

3. Add:

```swift
/// Everything the year view shows: from the start of Jan 1 to the last second of Dec 31, stepped
/// with `calendar` (never by 86 400 seconds), so DST days are right. Like `MonthGrid.range`, the
/// injected `calendar` must share the current time zone.
public enum YearGrid {
    public static func range(year: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> ClosedRange<Date> {
        let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let start = calendar.startOfDay(for: first)
        let nextYear = calendar.date(byAdding: .year, value: 1, to: start) ?? start.addingTimeInterval(365 * 86_400)
        return start...nextYear.addingTimeInterval(-1)
    }
}

/// Per-day task/event counts for a whole calendar year, keyed by ISO date (`yyyy-MM-dd`), only
/// days of that year with something on them. Same rules as `gridDensity` (built on
/// `buildAgendaItems`; an overdue reminder counts on today's day, and only when today is inside
/// the year). The same time-zone contract applies.
public func yearDensity(
    events: [Event],
    reminders: [Reminder],
    year: Int,
    today: Date = Date(),
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> [String: DayDensity] {
    densityCounts(events: events, reminders: reminders, range: YearGrid.range(year: year, calendar: calendar), today: today, calendar: calendar)
}
```

- [ ] **Step 4: Run to verify pass, then the full suite**

Run: `swift test --filter "YearDensityTests|GridDensityTests|AgendaDensity"` → PASS; then `swift test` → all pass (295 + 6 = 301; three env-gated tests skipped). Also add a timing test for `yearDensity` next to the existing `largeDatasetGridDensityTiming` in `AgendaDensityTests.swift` (same migrated-size dataset and 2 s budget; copy its structure, a year of that dataset instead of a month).

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/view-modes add ios/Sources/StarkKit/Planner/AgendaDensity.swift ios/Tests/StarkKitTests/YearDensityTests.swift ios/Tests/StarkKitTests/AgendaDensityTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/view-modes commit -m "feat(ios): yearDensity, YearGrid.range and DayDensity.level (#95)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Drag bar and week mode (month <-> week)

**Files:**
- Create: `ios/App/Stark/Stark/ModeHandle.swift`
- Modify: `ios/App/Stark/Stark/MonthGridView.swift`
- Modify: `ios/App/Stark/Stark/ContentView.swift`

**Interfaces:**
- Consumes (Task 1): `CalendarMode` (`afterDrag`, `title`, `expanded`, `collapsed`), `MonthGrid.weekRow(containing:)`, `MonthGrid.weekStepped(_:by:)`. Existing: `MonthGridView`'s `dayCell`, header, density snapshot, `loadVisibleMonths()`; `ContentView.selectDate`.
- No unit tests (SwiftUI wiring; the logic is tested in Tasks 1-2). Verify with the app build check plus `swift test`.
- This task wires only week and month; year is wired in Task 4. So `ModeHandle` takes `available: [CalendarMode]` (Task 3 passes `[.week, .month]`); a drag whose result is not available is ignored. Task 4 removes the parameter.

- [ ] **Step 1: `ModeHandle.swift` (new)**

A view `ModeHandle(mode: Binding<CalendarMode>, available: [CalendarMode])`:
- A full-width strip about 20 pt tall containing a centred flat bar (`Rectangle().fill(Colors.checkboxBorder)`, 40 x 4, no rounding), `.contentShape(Rectangle())` so the whole strip is draggable.
- `DragGesture(minimumDistance: 8)`; on `.onEnded`, `let target = mode.afterDrag(translation: value.translation.height, predictedEnd: value.predictedEndTranslation.height)`; if `target != mode && available.contains(target)`, `withAnimation(.easeInOut(duration: 0.2)) { mode = target }`.
- Accessibility: one element (`.accessibilityElement(children: .ignore)`), label "Calendar view", value `mode.title`, `.accessibilityAdjustableAction` where increment = `expanded`, decrement = `collapsed` (each only if available), same animation.
- Doc comment explaining it is visuals plus one gesture, and that the rule is `CalendarMode.afterDrag`.

- [ ] **Step 2: `MonthGridView.swift`**

1. Add `let mode: CalendarMode` (only `.month` and `.week` are ever passed in this task).
2. `.week`: render the header, the weekday label row, then a single `LazyVGrid` row of `MonthGrid.weekRow(containing: selectedDate)` using the existing `dayCell` (same markers, dimming, today/selection highlight, accessibility labels); the grid's fixed frame height becomes `rowHeight` (one row) instead of `rowHeight * maxRows`. `.month` is unchanged.
3. Header: in week mode the title is the selected day's month (same style), and the chevrons (labels "Previous week" / "Next week") call `onSelectDate(MonthGrid.weekStepped(selectedDate, by: ∓1 / +1))`; month mode's chevrons are unchanged (they page months).
4. `visibleMonth` sync (so density and loaded months always cover the shown week): `.onChange(of: mode)` → `visibleMonth = YearMonth(date: selectedDate)` then `loadVisibleMonths()`; `.onChange(of: selectedDate)` → if `mode == .week`, the same. In month mode, selecting a day must still not change `visibleMonth` (issue #96 behaviour).
5. Update the struct's doc comment (week mode) and keep every existing behaviour in month mode byte-for-byte.

- [ ] **Step 3: `ContentView.swift`**

1. `@State private var mode: CalendarMode = .month`.
2. Pass `mode` to `MonthGridView`. Between the grid and the existing 1 pt separator, insert `ModeHandle(mode: $mode, available: [.week, .month])`.
3. Changing `mode` animates the grid's height (the handle uses `withAnimation`); nothing else in `ContentView` changes. `selectDate` and `followCalendarDay` keep working (`selectedDate` is the source of truth for the week shown).
4. Update the struct's doc comment ("one screen: grid on top (a week row when collapsed), drag bar, agenda").

- [ ] **Step 4: Verify**

App build check → `** BUILD SUCCEEDED **`, no new warnings from the three files; `swift test` from `ios/` → all pass (301).

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/view-modes add ios/App/Stark/Stark/ModeHandle.swift ios/App/Stark/Stark/MonthGridView.swift ios/App/Stark/Stark/ContentView.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/view-modes commit -m "feat(ios): drag bar and a one-week collapsed grid (#95)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Year view + docs

**Files:**
- Create: `ios/App/Stark/Stark/YearView.swift`
- Modify: `ios/App/Stark/Stark/ContentView.swift`, `ios/App/Stark/Stark/ModeHandle.swift`
- Modify: `CLAUDE.md` (Native iOS App section)

**Interfaces:**
- Consumes (Tasks 1-2): `CalendarMode`, `MonthGrid.days(for:)`, `YearGrid.range(year:)`, `yearDensity(...)`, `DayDensity.level`. Existing: `PlannerStore.loadMonths(covering:)`, `AgendaFormat` (month names: use `AgendaFormat.monthYear` or a month-name helper — look at what exists and reuse), `ModeHandle`, `ContentView.selectDate`.
- No unit tests (SwiftUI wiring). Verify with the app build check plus `swift test`.

- [ ] **Step 1: `YearView.swift` (new)**

`YearView(today: Date, selectedDate: Date, mode: Binding<CalendarMode>, onSelectDate: (Date) -> Void)`:
- `@State year` initialised from `selectedDate`'s year (via `YearMonth(date:)`); header: the year title (`Fonts.mono`, same style family as the month title) with ‹ › chevrons (labels "Previous year"/"Next year"), 44 pt tall like the month header.
- Body: a `ScrollView` with a two-column `LazyVGrid` of 12 mini-months. Each mini-month: the month name, a `S M T W T F S` row (`Fonts.mono(9)`, `Colors.textSecondary`), and 6 week rows from `MonthGrid.days(for: YearMonth(year: year, month0: m))` with `Fonts.mono(11)` day numbers. In-month days are `Colors.text`, neighbouring days `Colors.textSecondary` (never tinted). A day with `level > 0` gets a `Rectangle` background of `Colors.accent` at opacity 0.15 / 0.30 / 0.50 for level 1 / 2 / 3 (named constants). Today (`iso == todayIso`, in-month or not) is the filled accent square with `Colors.background` text. Each day is a `Button` (`.buttonStyle(.plain)`, real hit area) calling `onSelectDate(day.date)` — for an out-of-month cell the tap still selects that real date. Accessibility: each day cell labelled with `counts.accessibilityLabel(title: <month day>, isToday:)`; in-month cells use `AgendaFormat.monthDay`.
- Density: `@State` snapshot tagged with its year, computed off the main actor in a `.task(id:)` keyed on `(year, today, store.events, store.reminders)` with the same stale-drop and "only use a snapshot for the shown year" rules as `MonthGridView`; `yearDensity(events:reminders:year:today:)`.
- Loading: `.task(id: year)` (and on appear) calls `store.loadMonths(covering: YearGrid.range(year: year))` so no month of the year is silently empty. (Twelve months load; that is the intended cost.)
- The drag bar sits below the scroll area: `ModeHandle(mode: $mode)`. Tapping the bar in year mode returns to month (see Step 2).
- Hard edges everywhere; only `Colors.*`/`Spacing.*`/`Fonts.mono`.

- [ ] **Step 2: `ModeHandle.swift` and `ContentView.swift`**

1. `ModeHandle`: remove the `available` parameter (all three modes are now reachable) and its checks. Add a tap: when `mode == .year`, tapping the strip sets `mode = .month` (animated); in other modes a tap does nothing. Keep the adjustable accessibility action.
2. `ContentView`: in `.year`, show `YearView(today: today, selectedDate: selectedDate, mode: $mode) { date in selectDate(date); withAnimation(.easeInOut(duration: 0.2)) { mode = .month } }` in place of the grid, separator and agenda; in `.week`/`.month`, keep what Task 3 built with `ModeHandle(mode: $mode)`. `selectDate` is unchanged and loads what the agenda window needs.
3. Update the doc comment.

- [ ] **Step 3: Docs**

In `CLAUDE.md`, Native iOS App section, add one paragraph after the "Month grid shows the neighbouring months' days" paragraph:

> **Week / month / year modes with a drag bar** (`CalendarMode`, `ModeHandle`, `MonthGridView`, `YearView`; logic in `CalendarMode`, `MonthGrid.weekRow`/`weekStepped`, `YearGrid`, `yearDensity`, `DayDensity.level`; issue #95): a thin flat bar between the grid and the agenda switches the screen between **week** (the grid collapses to the one week row containing the selected day; ‹ › step by a week via `onSelectDate`, so the agenda follows), **month** (the default) and **year** (a scrolling two-column grid of twelve mini-months, days with items tinted `Colors.accent` at three strengths by `DayDensity.level` — 1 / 2-3 / 4+ items — neighbouring-month days dimmed and never tinted; tapping a day selects it, returns to month mode and scrolls the agenda). Dragging up collapses and down expands; the mode changes **on release** (`CalendarMode.afterDrag`: 30 pt of travel, or a predicted 100 pt fling), animated, not tracking the finger. Tapping the bar in year mode returns to month; VoiceOver gets the bar as an adjustable "Calendar view" element. `MonthGridView.visibleMonth` follows the selected day's month when entering week mode, while in week mode, and on returning to month mode; in month mode selecting a day still never pages the grid (issue #96). `yearDensity` counts on the same `buildAgendaItems` as the grid (an overdue reminder counts on today's day only when today is in the year), and `YearView` loads all twelve months of the year with `store.loadMonths(covering: YearGrid.range(year:))`. The mode is not persisted. Not built: Fantastical's collapsed strip of only-event-days, live finger tracking, pinch to zoom.

- [ ] **Step 4: Verify**

App build check → `** BUILD SUCCEEDED **`, no new warnings from the edited files; `swift test` from `ios/` → all pass (301).

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/view-modes add ios/App/Stark/Stark/YearView.swift ios/App/Stark/Stark/ContentView.swift ios/App/Stark/Stark/ModeHandle.swift CLAUDE.md
git -C /Users/eladio/src/todo-txt/.claude/worktrees/view-modes commit -m "feat(ios): year view and the full week/month/year drag bar (#95)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
