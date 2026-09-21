# Month Grid Adjacent-Month Days (issue #96) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The native app's month grid shows the neighbouring months' days in its leading and trailing cells (dimmed, with their density markers), like Fantastical, so you can see what the previous month's last day and the next month's first days hold.

**Architecture:** Two pure StarkKit pieces — `MonthGrid` (the 42 cells of a month's grid, with an in-month flag, and the date range they cover) and `gridDensity` (task/event counts per cell, keyed by ISO date, over that whole range, built on `buildAgendaItems` exactly as `dayDensity` is). `MonthGridView` renders those cells and loads the months the grid covers.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM package `StarkKit` tested with Swift Testing (`import Testing`, `@Test`, `#expect`; never XCTest).

**Issue:** https://github.com/caritos/todo-txt/issues/96 (screenshot: Fantastical's September 2026 grid shows Aug 30, 31 in the first row and Oct 1-10 in the last two rows, dimmed, with their dots).

**Design (approved in conversation 2026-09-21, bounded change — no separate spec):**
- The grid is always 6 rows x 7 columns = 42 cells, Sunday-first (the grid already reserves 6 rows so it never resizes). The cells before day 1 and after the last day are the neighbouring months' real dates.
- Neighbour cells are dimmed (number in `Colors.textSecondary`) and show the same density markers as in-month cells. No new colours.
- **Tapping a neighbour cell** selects that day and scrolls the agenda to it, and the grid stays on the current month (the selection outline shows on the dimmed cell). This is what `ContentView.selectDate` already does for any date; the grid does not page. The month chevrons still page.
- Today's filled highlight shows on whichever cell is today, in or out of the month.
- VoiceOver reads a neighbour cell with its month, e.g. "Oct 1, 1 task", so the bare number is not ambiguous.
- Counts cover the whole grid range; an overdue reminder still counts only on today's cell, and only when today is inside the grid range (the same rule as `dayDensity`). The store must have loaded every month the grid touches.
- `dayDensity(month:)` is left as is (still tested); the view moves to `gridDensity`.
- **Out of scope:** paging when a neighbour cell is tapped, week numbers, changing marker style or count caps, the drag-bar/year view (issue #95).

## Global Constraints

- **Working directory:** `/Users/eladio/src/todo-txt/.claude/worktrees/grid-adjacent-days` (a git worktree, branch `worktree-grid-adjacent-days`). Use absolute paths; run Swift tests from its `ios/` directory (`swift test`).
- **Shell:** compound commands and heredocs may be rejected. Use plain single commands, the Write/Edit tools for files, `git -C <worktree>` and multiple `-m` flags for commits.
- **Commits:** stage specific paths only (never `git add -A`, `.` or `commit -a`). End every commit message with a separate `-m` paragraph: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Never push.
- **Logic goes in StarkKit, views are thin.** If it can be tested, it lives in `ios/Sources/StarkKit` with a Swift Testing test.
- **Tests first** for StarkKit work: write the failing test, run it and see it fail for the stated reason, then implement.
- **Baseline:** `swift test` currently passes 270 tests (three env-gated parity tests are skipped by design). It must stay green after every task.
- **Dates:** never build inclusive day-range bounds from `DateMath.date(from:)` (it is local noon); use `Calendar.startOfDay` and step with the calendar, as `dayDensity` and `AgendaWindow` do.
- **Theme:** only `Colors.*`, `Spacing.*`, `Fonts.mono` from `Theme.swift`; no hardcoded hex, no new colours, no rounded corners.
- **Do not touch the author's phone** (no `xcrun devicectl`, no `deploy.sh`); the controller does the on-device check.
- **App build check** (Task 2): `cd /Users/eladio/src/todo-txt/.claude/worktrees/grid-adjacent-days/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` must end in `** BUILD SUCCEEDED **`.

---

### Task 1: `MonthGrid` and `gridDensity` (StarkKit)

**Files:**
- Create: `ios/Sources/StarkKit/Planner/MonthGrid.swift`
- Modify: `ios/Sources/StarkKit/Planner/AgendaDensity.swift` (add `gridDensity` after `dayDensity`; add the `accessibilityLabel(title:isToday:)` overload to `DayDensity`)
- Create tests: `ios/Tests/StarkKitTests/MonthGridTests.swift`, `ios/Tests/StarkKitTests/GridDensityTests.swift`
- Modify test: `ios/Tests/StarkKitTests/AgendaDensityTests.swift` (append the accessibility-label test inside the suite)

**Interfaces:**
- Produces (used by Task 2):
  - `public struct GridDay: Hashable, Sendable, Identifiable` with `year`, `month0`, `day`, `isInMonth`, `iso: String`, `id: String` (= `iso`), `date: Date` (local noon of `iso`, `DateMath.date(from:)`).
  - `MonthGrid.dayCount` (42), `MonthGrid.days(for: YearMonth) -> [GridDay]`, `MonthGrid.range(for: YearMonth, calendar: Calendar = gregorian) -> ClosedRange<Date>`.
  - `gridDensity(events:reminders:month:today:calendar:) -> [String: DayDensity]` keyed by ISO date (`yyyy-MM-dd`), holding only days with something on them.
  - `DayDensity.accessibilityLabel(title: String, isToday: Bool) -> String`: the same phrases as the existing `accessibilityLabel(day:isToday:)` with `title` in place of the day number; the existing method becomes `accessibilityLabel(title: "\(day)", isToday: isToday)` (its output is unchanged).
- Existing APIs used: `DateMath.weekday(year:month0:day:)` (0 = Sunday), `DateMath.isoDate(year:month0:day:)`, `DateMath.addDays(_ iso:, _ n:)`, `DateMath.components(_:)`, `YearMonth`, `buildAgendaItems(events:reminders:in:today:)`.

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/StarkKitTests/MonthGridTests.swift`:

```swift
// ios/Tests/StarkKitTests/MonthGridTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("MonthGrid")
struct MonthGridTests {
    private let cal = Calendar(identifier: .gregorian)

    private func isos(_ days: [GridDay]) -> [String] { days.map(\.iso) }

    @Test("September 2026 (starts on a Tuesday): Aug 30-31 lead, Oct 1-10 trail, 42 cells")
    func september2026() {
        let days = MonthGrid.days(for: YearMonth(year: 2026, month0: 8))

        #expect(days.count == 42)
        #expect(days.count == MonthGrid.dayCount)
        #expect(days[0].iso == "2026-08-30")
        #expect(!days[0].isInMonth)
        #expect(!days[1].isInMonth)
        #expect(days[2].iso == "2026-09-01")
        #expect(days[2].isInMonth)
        #expect(days[31].iso == "2026-09-30")
        #expect(days[31].isInMonth)
        #expect(days[32].iso == "2026-10-01")
        #expect(!days[32].isInMonth)
        #expect(days[41].iso == "2026-10-10")
        #expect(days.filter(\.isInMonth).count == 30)
        #expect(DateMath.weekday(year: days[0].year, month0: days[0].month0, day: days[0].day) == 0)
    }

    @Test("a month that starts on Sunday has no leading days and a full trailing fortnight")
    func februaryStartsOnSunday() {
        let days = MonthGrid.days(for: YearMonth(year: 2026, month0: 1))

        #expect(days[0].iso == "2026-02-01")
        #expect(days[0].isInMonth)
        #expect(days[27].iso == "2026-02-28")
        #expect(days[28].iso == "2026-03-01")
        #expect(!days[28].isInMonth)
        #expect(days[41].iso == "2026-03-14")
    }

    @Test("a month that starts on Saturday has six leading days")
    func augustStartsOnSaturday() {
        let days = MonthGrid.days(for: YearMonth(year: 2026, month0: 7))

        #expect(days[0].iso == "2026-07-26")
        #expect(days[5].iso == "2026-07-31")
        #expect(!days[5].isInMonth)
        #expect(days[6].iso == "2026-08-01")
        #expect(days[6].isInMonth)
        #expect(days[41].iso == "2026-09-05")
    }

    @Test("the grid crosses year boundaries in both directions")
    func yearBoundaries() {
        let december = MonthGrid.days(for: YearMonth(year: 2026, month0: 11))
        #expect(december[0].iso == "2026-11-29")
        #expect(december[41].iso == "2027-01-09")
        #expect(december[41].year == 2027)
        #expect(december[41].month0 == 0)

        let january = MonthGrid.days(for: YearMonth(year: 2026, month0: 0))
        #expect(january[0].iso == "2025-12-28")
        #expect(january[0].year == 2025)
        #expect(january[0].month0 == 11)
    }

    @Test("a cell's id is its ISO date and its date is local noon of that day")
    func idAndDate() {
        let day = MonthGrid.days(for: YearMonth(year: 2026, month0: 8))[2]

        #expect(day.id == "2026-09-01")
        #expect(day.date == DateMath.date(from: "2026-09-01"))
    }

    @Test("the range runs from the start of the first cell's day to the last second of the last cell's day")
    func range() {
        let range = MonthGrid.range(for: YearMonth(year: 2026, month0: 8))

        #expect(range.lowerBound == cal.startOfDay(for: DateMath.date(from: "2026-08-30")))
        #expect(range.upperBound == cal.startOfDay(for: DateMath.date(from: "2026-10-11")).addingTimeInterval(-1))
        #expect(range.contains(DateMath.date(from: "2026-08-30")))
        #expect(range.contains(DateMath.date(from: "2026-10-10")))
        #expect(!range.contains(DateMath.date(from: "2026-10-11")))
    }
}
```

Create `ios/Tests/StarkKitTests/GridDensityTests.swift`:

```swift
// ios/Tests/StarkKitTests/GridDensityTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("gridDensity")
struct GridDensityTests {
    private let sept = YearMonth(year: 2026, month0: 8)
    private var today: Date { DateMath.date(from: "2026-09-20") }

    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }

    @Test("counts land on neighbouring-month cells too, and nothing beyond the grid is counted")
    func countsNeighbours() {
        let events = [
            Event(id: "e1", title: "Aug 31", start: d("2026-08-31")),
            Event(id: "e2", title: "Sep 15", start: d("2026-09-15")),
            Event(id: "e3", title: "Oct 2", start: d("2026-10-02")),
            Event(id: "e4", title: "Oct 20", start: d("2026-10-20")),
        ]
        let reminders = [
            Reminder(id: "r1", title: "Sep 25", dueDate: d("2026-09-25")),
            Reminder(id: "r2", title: "Oct 5", dueDate: d("2026-10-05")),
        ]

        let result = gridDensity(events: events, reminders: reminders, month: sept, today: today)

        #expect(result["2026-08-31"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-09-15"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-09-25"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-10-02"] == DayDensity(tasks: 0, events: 1))
        #expect(result["2026-10-05"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-10-20"] == nil)
        #expect(result.count == 5)
    }

    @Test("an overdue reminder counts on today's cell, not its missed day")
    func overdueCountsOnToday() {
        let reminders = [Reminder(id: "r1", title: "Missed", dueDate: d("2026-09-01"))]

        let result = gridDensity(events: [], reminders: reminders, month: sept, today: today)

        #expect(result["2026-09-20"] == DayDensity(tasks: 1, events: 0))
        #expect(result["2026-09-01"] == nil)
    }

    @Test("an overdue reminder is not counted when today is outside the grid range")
    func overdueIgnoredWhenTodayOutside() {
        let reminders = [Reminder(id: "r1", title: "Missed", dueDate: d("2026-09-01"))]

        let result = gridDensity(events: [], reminders: reminders, month: YearMonth(year: 2026, month0: 11), today: today)

        #expect(result.isEmpty)
    }

    @Test("for days inside the month it agrees with dayDensity")
    func agreesWithDayDensity() {
        let events = [
            Event(id: "e1", title: "A", start: d("2026-09-03")),
            Event(id: "e2", title: "B", start: d("2026-09-03")),
            Event(id: "w", title: "Weekly", start: d("2026-09-02"), recurrence: RecurrenceRule(frequency: .weekly)),
        ]
        let reminders = [
            Reminder(id: "r1", title: "Later", dueDate: d("2026-09-28")),
            Reminder(id: "r2", title: "Missed", dueDate: d("2026-09-05")),
        ]

        let month = dayDensity(events: events, reminders: reminders, month: sept, today: today)
        let grid = gridDensity(events: events, reminders: reminders, month: sept, today: today)

        #expect(!month.isEmpty)
        for (day, density) in month {
            #expect(grid[DateMath.isoDate(year: 2026, month0: 8, day: day)] == density)
        }
    }
}
```

Append to the existing suite in `ios/Tests/StarkKitTests/AgendaDensityTests.swift` (before its closing `}`; open the file first and match its suite name and style):

```swift
    @Test("accessibilityLabel(title:) uses the title in place of the day number; the day form is unchanged")
    func accessibilityLabelWithTitle() {
        let counts = DayDensity(tasks: 1, events: 2)

        #expect(counts.accessibilityLabel(title: "Oct 1", isToday: false) == "Oct 1, 1 task, 2 events")
        #expect(counts.accessibilityLabel(title: "Oct 1", isToday: true) == "Oct 1, today, 1 task, 2 events")
        #expect(counts.accessibilityLabel(day: 20, isToday: true) == "20, today, 1 task, 2 events")
        #expect(DayDensity.none.accessibilityLabel(title: "Oct 1", isToday: false) == "Oct 1")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/grid-adjacent-days/ios && swift test --filter "MonthGridTests|GridDensityTests|AgendaDensity"`
Expected: FAIL to compile — `GridDay`, `MonthGrid`, `gridDensity` not defined.

- [ ] **Step 3: Implement**

Create `ios/Sources/StarkKit/Planner/MonthGrid.swift`:

```swift
// ios/Sources/StarkKit/Planner/MonthGrid.swift
import Foundation

/// One cell of the month grid: a real calendar date, flagged with whether it belongs to the month
/// being shown (the others are the neighbouring months' leading/trailing days).
public struct GridDay: Hashable, Sendable, Identifiable {
    public let year: Int
    public let month0: Int
    public let day: Int
    public let isInMonth: Bool

    public init(year: Int, month0: Int, day: Int, isInMonth: Bool) {
        self.year = year
        self.month0 = month0
        self.day = day
        self.isInMonth = isInMonth
    }

    /// `yyyy-MM-dd`.
    public var iso: String { DateMath.isoDate(year: year, month0: month0, day: day) }
    public var id: String { iso }
    /// Local noon of this day (`DateMath.date(from:)`), the app's usual "a day" timestamp.
    public var date: Date { DateMath.date(from: iso) }
}

/// The cells of a Sunday-first month grid. Always 6 rows x 7 columns = 42 cells, so the grid (and
/// the agenda below it) never resizes as the user pages between months.
public enum MonthGrid {
    public static let dayCount = 42

    public static func days(for month: YearMonth) -> [GridDay] {
        // DateMath.weekday: 0 = Sunday ... 6 = Saturday, i.e. how many cells precede day 1.
        let leading = DateMath.weekday(year: month.year, month0: month.month0, day: 1)
        let firstOfMonth = DateMath.isoDate(year: month.year, month0: month.month0, day: 1)
        return (0..<dayCount).map { index in
            let c = DateMath.components(DateMath.addDays(firstOfMonth, index - leading))
            return GridDay(
                year: c.year,
                month0: c.month0,
                day: c.day,
                isInMonth: c.year == month.year && c.month0 == month.month0
            )
        }
    }

    /// Everything the grid shows: from the start of the first cell's day to the last second of the
    /// last cell's day. Stepped with `calendar`, never by 86 400 seconds, so DST days are right.
    public static func range(
        for month: YearMonth,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ClosedRange<Date> {
        let cells = days(for: month)
        let first = calendar.startOfDay(for: cells[0].date)
        let lastStart = calendar.startOfDay(for: cells[cells.count - 1].date)
        let dayAfterLast = calendar.date(byAdding: .day, value: 1, to: lastStart) ?? lastStart.addingTimeInterval(86_400)
        return first...dayAfterLast.addingTimeInterval(-1)
    }
}
```

In `AgendaDensity.swift`, inside `DayDensity`, replace the existing `accessibilityLabel(day:isToday:)` with the two methods below (keep its doc comment on the new `title` form, adapted; the `day` form must produce exactly the same strings as before):

```swift
    public func accessibilityLabel(day: Int, isToday: Bool) -> String {
        accessibilityLabel(title: "\(day)", isToday: isToday)
    }

    /// The same label with `title` (for example "Oct 1" for a neighbouring-month cell) in place
    /// of the bare day number, e.g. "Oct 1, today, 3 tasks, 1 event".
    public func accessibilityLabel(title: String, isToday: Bool) -> String {
        var parts = [title]
        if isToday { parts.append("today") }
        if tasks > 0 { parts.append("\(tasks) \(tasks == 1 ? "task" : "tasks")") }
        if events > 0 { parts.append("\(events) \(events == 1 ? "event" : "events")") }
        return parts.joined(separator: ", ")
    }
```

Then add after `dayDensity`:

```swift
/// Per-day task/event counts for every cell of `month`'s grid — the month itself plus the
/// neighbouring months' leading/trailing days — keyed by ISO date (`yyyy-MM-dd`).
///
/// Same rules as `dayDensity` (it is built on `buildAgendaItems` over the whole grid range so the
/// grid can never disagree with the agenda): an overdue reminder counts on **today's** cell, and
/// only when today falls inside the grid range. Only days with something on them are stored.
public func gridDensity(
    events: [Event],
    reminders: [Reminder],
    month: YearMonth,
    today: Date = Date(),
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> [String: DayDensity] {
    let range = MonthGrid.range(for: month, calendar: calendar)

    var result: [String: DayDensity] = [:]
    for item in buildAgendaItems(events: events, reminders: reminders, in: range, today: today) {
        // buildAgendaItems can also return rows pinned to today (overdue) when today is outside
        // the range; they belong to a cell that is not on this grid.
        guard range.contains(item.displayDate) else { continue }
        let c = calendar.dateComponents([.year, .month, .day], from: item.displayDate)
        guard let year = c.year, let month = c.month, let day = c.day else { continue }
        let iso = DateMath.isoDate(year: year, month0: month - 1, day: day)
        switch item.kind {
        case .event: result[iso, default: .none].events += 1
        case .reminder: result[iso, default: .none].tasks += 1
        }
    }
    return result
}
```

- [ ] **Step 4: Run to verify pass, then the full suite**

Run: `swift test --filter "MonthGridTests|GridDensityTests"` → PASS; then `swift test` → all pass (270 + 10 = 280; three env-gated tests skipped). If a date expectation in the tests is off (for example a weekday), check it with `DateMath.weekday` before touching the implementation and report any correction.

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/grid-adjacent-days add ios/Sources/StarkKit/Planner/MonthGrid.swift ios/Sources/StarkKit/Planner/AgendaDensity.swift ios/Tests/StarkKitTests/MonthGridTests.swift ios/Tests/StarkKitTests/GridDensityTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/grid-adjacent-days commit -m "feat(ios): MonthGrid cells and gridDensity over the whole grid range (#96)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `MonthGridView` shows the neighbouring days

**Files:**
- Modify: `ios/App/Stark/Stark/MonthGridView.swift`
- Modify: `CLAUDE.md` (Native iOS App section)

**Interfaces:**
- Consumes (Task 1): `GridDay`, `MonthGrid.days(for:)`, `MonthGrid.range(for:)`, `gridDensity(...)`. Existing: `PlannerStore.loadMonths(covering:)`, `AgendaFormat.monthDay(_:)`, `DayDensity.accessibilityLabel(day:isToday:)`.
- No unit tests (SwiftUI wiring; the logic is tested in Task 1). Verify with the app build check plus `swift test`.

- [ ] **Step 1: Wire the grid**

In `MonthGridView.swift`:
1. Remove the `Cell` enum and `cells(leadingBlanks:daysInMonth:)`, and the `daysInMonth` / `leadingBlanks` locals in `body`.
2. Render one `ForEach(MonthGrid.days(for: visibleMonth))` (the type is `Identifiable`, so no `id:` argument) of `dayCell(...)`, passing the `GridDay`. Keep the `LazyVGrid`, the fixed `rowHeight * maxRows` height and the weekday header row exactly as they are.
3. The density snapshot becomes `[String: DayDensity]` keyed by ISO (`DensitySnapshot.days`), computed with `gridDensity(events:reminders:month:today:)` in the existing detached task (replace the `dayDensity` call). Look a cell up with `visibleDensity[day.iso] ?? .none`.
4. Load the months the grid touches: replace `store.loadMonth(visibleMonth)` in the `.task`, in `changeMonth(by:)` and in the `.onChange(of: today)` handler with `store.loadMonths(covering: MonthGrid.range(for: visibleMonth))`.
5. `dayCell`: take a `GridDay`. The tap is `onSelectDate(day.date)` (unchanged behaviour: the grid does not page). The number text uses `Colors.textSecondary` when `!day.isInMonth`, unless the cell is today (today keeps `Colors.background` on its accent fill) — `isToday` and `isSelected` are computed from `day.iso` against `todayIso` / `selectedIso` for every cell, in or out of the month. The markers row is unchanged. The accessibility label is `counts.accessibilityLabel(title: day.isInMonth ? "\(day.day)" : AgendaFormat.monthDay(day.date), isToday: isToday)` (the new `title:` overload from Task 1), so an in-month cell's label is byte-identical to today's and an out-of-month Oct 1 with one task reads "Oct 1, 1 task".
6. Update the struct's doc comment: the grid is 6 rows always, the cells before day 1 and after the last day show the neighbouring months' dates dimmed with their markers.

- [ ] **Step 2: Docs**

In `CLAUDE.md`, Native iOS App section, add one paragraph after the "Add/edit fields" paragraph:

> **Month grid shows the neighbouring months' days** (`MonthGridView`; logic in `MonthGrid`, `GridDay`, `gridDensity`; issue #96): the grid is always 6 rows x 7 columns (42 cells, Sunday-first) and the cells before day 1 / after the last day are the neighbouring months' real dates, dimmed, with their density markers — like Fantastical. `MonthGrid.days(for:)` builds the cells and `MonthGrid.range(for:)` the whole date range they cover; `gridDensity` counts tasks/events per cell keyed by ISO date over that range, on the same `buildAgendaItems` as the agenda (an overdue reminder still counts only on today's cell, and only when today is inside the range). `MonthGridView` loads every month the grid touches with `store.loadMonths(covering: MonthGrid.range(for:))` — a neighbour cell whose month was never loaded would silently show no markers. Tapping a neighbour cell selects it and scrolls the agenda (`ContentView.selectDate`), but the grid stays on the current month; only the chevrons page. `dayDensity(month:)` is no longer used by the app (its tests remain).

- [ ] **Step 3: Verify**

App build check → `** BUILD SUCCEEDED **`, no new warnings from `MonthGridView.swift`; `swift test` from `ios/` → all pass (280).

- [ ] **Step 4: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/grid-adjacent-days add ios/App/Stark/Stark/MonthGridView.swift CLAUDE.md
git -C /Users/eladio/src/todo-txt/.claude/worktrees/grid-adjacent-days commit -m "feat(ios): month grid shows the neighbouring months' days with their markers (#96)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
