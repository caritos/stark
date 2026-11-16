# Fantastical Redesign, Stage 3b (full-screen Month) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Month" entry in the view menu opens a full-screen month like Fantastical's: tall day cells with all-day bars (multi-day ones continuous across cells), lilac holiday chips, dot + title timed events, checkbox + title reminders and "N more…".

**Architecture:** One pure layout function in StarkKit turns the same agenda rows the agenda uses (`agendaWithApple`) into per-week bars, per-day lines and overflow counts (tested first, four time zones). A new `FullMonthView` only draws that layout. The menu gains a Month entry; Month is a screen state in `ContentView` like Year, not a `CalendarMode`.

**Tech Stack:** SwiftUI iOS 17+, StarkKit (Swift Testing).

**Spec:** `docs/superpowers/specs/2026-11-16-fantastical-stage3-month-year-design.md` (section 3b). Visual reference: `docs/fantastical/CATALOG.md` IMG_1882, IMG_8834, IMG_1883 (read those entries and look at the images).

## Global Constraints

- Stage 1/2/3a tokens only (`Colors.*`, `Spacing`, `Fonts.mono` = system font); new colours (holiday lilac, today cell tint) become tokens in `Theme.swift` with light and dark values. An Apple calendar's own `colorRGB`/`colorHex` is the only other colour source.
- Month and the agenda must never disagree about what is on a day: items come from `buildAgendaItems` then `agendaWithApple` (same call shape as `gridDensity`/`densityCounts` in `AgendaDensity.swift`); no second expansion of recurrences.
- Do not touch `CalendarMode`, `AgendaWindow`, `store.loadMonths` semantics, scroll-sync, `AgendaRowTargets`, `yearDensity`/`gridDensity`.
- Cells are single tap targets (one per day, 44 pt minimum height); no scrolling inside a cell; "N more…" is drawn inside the cell and also just selects the day.
- Holiday chip rule (spec call 1): the item's Apple calendar title contains "holiday", case-insensitive; no new setting.
- Pure logic in StarkKit, tests first, run under New York, Tokyo, Honolulu and UTC (see how `GridDensityTests` / Apple suites set the zone). Views verified by simulator screenshots in light and dark.
- `ios/.build` is TRACKED in git and builds dirty it: never `git add` it; before each commit and before merging run `git checkout -- ios/.build; git clean -fdq ios/.build`. Stale module cache after worktree builds: `rm -rf ios/.build/arm64-apple-macosx/debug/ModuleCache`.
- Build: `cd ios/App/Stark && xcodebuild -scheme Stark -destination 'generic/platform=iOS Simulator' -quiet build CODE_SIGNING_ALLOWED=NO`. Kit tests: `cd ios && swift test` (1112 before this plan).
- Ship (controller only): merge to main locally, full suite on the merged result, gate the push on checked results, Release device build, `(set -a; . ~/.appstoreconnect/env; set +a; ios/App/ship.sh)` in a subshell, TestFlight only (v2.0.28).

## Done when

- `cd ios && swift test` green (new `MonthLayoutTests` incl. four time zones, extended `CalendarViewMenuTests`); `cd web && make test-fast` green (Node 24 via nvm); Release device build green.
- Simulator screenshots, light and dark, of Month with seeded dense data (a multi-day bar crossing a week boundary, a holiday chip, timed events, reminders incl. a repeating one, a day with "N more…", today cell, adjacent months grey, current month outlined), compared with IMG_1882/IMG_8834.
- idb: menu > Month opens it; chevrons page months; a day tap opens the agenda on that day (DayTicker, agenda scrolled there); menu > DayTicker and > Year work from Month; Search/Add/All Calendars still open.
- TestFlight v2.0.28 uploaded. Not part of done: the owner's device check (report as not verified).

## Review Focus

- A multi-day event that starts before the visible grid or ends after it (clipped bars with `continuesBefore/After`) and one that crosses a week boundary (one bar piece per week row).
- A daily repeating all-day event must stay separate one-day chips, never one long bar (only events whose span is more than 0 days make bars).
- An overdue reminder is pinned to today by the agenda rules: it shows on today's cell only; completed reminders show struck through.
- A day with more items than rows: the last row becomes "N more…" and N counts every hidden bar and line of that day (including the one displaced by the label).
- A month with no items, a leap-February, and a 5-row month (rows fill the height) render without clipping; AX5 text does not break the grid (text size capped).

---

### Task 1: Month layout (Kit, TDD)

**Files:**
- Create: `ios/Sources/StarkKit/Planner/MonthLayout.swift`
- Test: `ios/Tests/StarkKitTests/MonthLayoutTests.swift`

**Interfaces:**
- Consumes: `AgendaItem` (kind, occurrence, appleSource, isCompleted), `MonthGrid.days(for:)` / `GridDay`, `YearMonth`, `Event.isAllDay`, `spanDays(of:calendar:)` (internal in `AgendaBuilder.swift`; same module, may be used; its meaning: days after the start day the occurrence runs).
- Produces (all `public`, `Equatable`, `Sendable`):
  - `struct MonthBar { let id: String; let title: String; let colorRGB: UInt32?; let isHoliday: Bool; let startColumn: Int; let endColumn: Int; let lane: Int; let continuesBefore: Bool; let continuesAfter: Bool }` (columns 0...6, Sunday first like `MonthGrid`)
  - `enum MonthLineKind: Equatable, Sendable { case timed(colorRGB: UInt32?), reminder(isCompleted: Bool, isRecurring: Bool) }`
  - `struct MonthLine { let id: String; let title: String; let kind: MonthLineKind }`
  - `struct MonthWeek { let bars: [MonthBar]; let lines: [[MonthLine]]; let overflow: [Int] }` (`lines` and `overflow` have exactly 7 entries, one per column)
  - `func monthLayout(items: [AgendaItem], month: YearMonth, rowCapacity: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> [MonthWeek]` (one `MonthWeek` per row of `MonthGrid.days(for: month)`; `items` are already merged agenda rows covering the grid's range).

Rules (decided here; tests pin them):
- Bar candidates: event rows where `event.isAllDay` or `spanDays(of:) > 0`, and not on a day outside the grid. Consecutive day rows of one event id are grouped into chunks of `spanDays + 1` days starting at the first day, so a daily single-day event yields one-day bars. A chunk crossing a week boundary is split into one `MonthBar` per week row (`continuesBefore`/`continuesAfter` true where it continues into the previous/next piece or beyond the grid). Chunk start/end columns come from the days present in the grid.
- Lanes: bars in a week are placed longest-first then by start column then id, each in the lowest lane free over its columns.
- Lines: every other event row is `.timed` (title, calendar colour; sorted by time then title) followed by reminder rows (open first by time, then completed), per day; reminders use `isRecurring` = `appleSource?.isRecurringSeries` or the local reminder's recurrence non-nil.
- Capacity: a day cell has `rowCapacity` rows. Used rows = lanes occupied by bars in that week (lane index + 1 of the highest bar covering that day, so lanes stay aligned) then that day's lines. If everything fits, `overflow[col] == 0`. Otherwise the last row is replaced by "N more…": bars with `lane >= rowCapacity - 1` are dropped from that week's `bars` only when they cannot fit anywhere, lines are cut so that `lines[col].count == max(0, rowCapacity - 1 - lanesUsed)`, and `overflow[col]` counts every hidden bar (covering that day) and line, including the one displaced by the label. A bar kept in `bars` that covers an overflowing day is fine.
- Holiday: `appleSource?.calendarTitle` lowercased contains "holiday".

- [ ] **Step 1:** Write failing tests (build local dates; wrap each in the four-zone helper the neighbouring suites use): `singleAllDayEventIsOneDayBar`; `multiDayEventOneBarWithinWeek` (start/end columns, lane 0); `multiDayCrossingWeekSplitsIntoTwoPieces` (first `continuesAfter`, second `continuesBefore`, same title); `eventStartingBeforeGridIsClippedWithContinuesBefore`; `dailyRepeatingAllDayEventStaysSeparateOneDayBars` (seven days give seven bars, none wider than one column); `overlappingBarsGetDifferentLanes`; `holidayCalendarTitleMakesHolidayChipCaseInsensitive` and a non-holiday title does not; `timedEventAndReminderLinesInOrder` (timed by time, open reminders then completed); `recurringReminderLineFlagged` (Apple `isRecurringSeries` and local recurrence); `overflowReplacesLastRowAndCountsAllHidden` (capacity 3, one bar + four lines gives two lines shown and overflow 3 on that day, other days 0); `barBeyondCapacityCountsInOverflowOfItsDays`; `emptyMonthHasSevenEmptyColumnsPerWeek`; `leapFebruaryAndFiveRowMonthProduceOneWeekPerGridRow`; `agendaRowsOutsideGridAreIgnored`; `overdueReminderAppearsOnlyOnItsDisplayDay`.
- [ ] **Step 2:** Run `cd ios && swift test --filter MonthLayoutTests`; expect compile failure/red.
- [ ] **Step 3:** Implement `monthLayout` and the types as specified (a pure function; no UI types; no `Date()`).
- [ ] **Step 4:** Run the filter, then the full `swift test`; expect all green. Clean `ios/.build` as in Global Constraints.
- [ ] **Step 5:** Commit `feat(kit): month layout (bars, lines, overflow)`.

### Task 2: Menu gains Month (Kit, TDD)

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/CalendarViewMenu.swift`, `ios/Tests/StarkKitTests/CalendarViewMenuTests.swift`

**Interfaces:**
- Produces: `CalendarViewChoice` cases `dayTicker, month, year` (menu order; titles "DayTicker", "Month", "Year"; Month image `calendar.badge.clock` is not wanted, use `square.grid.3x3`), `CalendarViewMenu.Screen` = `enum Screen: Equatable, Sendable { case dayTicker(CalendarMode), month, year }`-free alternative is NOT used; instead: `static func current(for mode: CalendarMode, fullMonth: Bool) -> CalendarViewChoice` (fullMonth wins, else year mode gives year, else dayTicker), `static func target(after choice: CalendarViewChoice, current mode: CalendarMode) -> (mode: CalendarMode, fullMonth: Bool)` (`.month` gives `(mode, true)` with the mode unchanged; `.year` gives `(.year, false)`; `.dayTicker` gives `(mode == .year ? .month : mode, false)`), `accessibilityValue(for mode: CalendarMode, fullMonth: Bool) -> String`. Remove the old two-argument forms (`current(for:)`, `mode(after:current:)`, `accessibilityValue(for:)`) and update their callers in `ContentView`/`FloatingBottomBar`/`ViewMenu` in Task 3.

- [ ] **Step 1:** Rewrite/extend the tests: `currentIsMonthWhenFullMonthShown` (any mode), `currentFollowsModeOtherwise`, `chooseMonthKeepsModeAndTurnsFullMonthOn`, `chooseYearTurnsFullMonthOff`, `chooseDayTickerFromYearGivesMonthAndFullMonthOff`, `chooseDayTickerKeepsWeekAndMonth`, `accessibilityValueNamesCurrentView`, `allChoicesHaveUniqueTitleAndImage`, `menuOrderIsDayTickerMonthYear`.
- [ ] **Step 2:** Run `swift test --filter CalendarViewMenuTests`; expect red.
- [ ] **Step 3:** Implement the new enum case and functions; the app target will not compile until Task 3 updates its callers (commit anyway, note it in the commit body; bisect only).
- [ ] **Step 4:** Run the filter and the full Kit `swift test` (Kit only; the app target is built in Task 3); expect green. Clean `ios/.build`.
- [ ] **Step 5:** Commit `feat(kit): Month entry in the view menu`.

### Task 3: FullMonthView and menu wiring

**Files:**
- Create: `ios/App/Stark/Stark/FullMonthView.swift`
- Modify: `ios/App/Stark/Stark/ContentView.swift`, `ViewMenu.swift`, `FloatingBottomBar.swift`, `Theme.swift`

**Interfaces:**
- Consumes: `monthLayout`, `MonthWeek/MonthBar/MonthLine`, `agendaWithApple`, `buildAgendaItems`, `PlannerStore`, `AppleOverlayModel`, `PlanCache`, `CalendarViewMenu.target/current/accessibilityValue`, `MonthGrid`.
- Produces: `FullMonthView(today: Date, selectedDate: Date, onSelectDate: (Date) -> Void)`; tokens `Colors.holidayChip`, `Colors.holidayText`, `Colors.todayCell`, `Colors.monthOutline`.

- [ ] **Step 1:** Wire the menu: `ContentView` gets `@State fullMonth = false`; `ViewMenu` lists `CalendarViewChoice.allCases` (now with Month); choosing calls `CalendarViewMenu.target(after:current:)` and sets `mode` and `fullMonth` with the existing animation; the hamburger's accessibility value uses the new three-argument-free forms; `FullMonthView` is shown in the same `ZStack` slot as `YearView` (agenda hidden, not removed, exactly as for year) with the bar overlay still on top and `FloatingBottomBar.clearance` at the bottom of its content.
- [ ] **Step 2:** `FullMonthView`: header like the month header of stage 2 (large month name, year in red, chevrons stepping `visibleMonth`, horizontal swipe also pages), SUN..SAT caps strip with a blue rule, then `MonthGrid.days(for:)` as week rows filling the available height (rows equal height, minimum cell height 80 pt; cap text with `.dynamicTypeSize(...DynamicTypeSize.xLarge)`). `rowCapacity` = floor((cellHeight - 24 pt number band) / 18 pt row height). Items: the visible grid range through `buildAgendaItems` + `agendaWithApple` computed off the main actor with the same inputs/debounce pattern as `YearView`'s density task (see `YearView.densityInputs`), tagged with the month; layout from `monthLayout`. Cell: day number top-right (today = blue circle and the cell tinted `todayCell`), adjacent-month cells grey tinted, the displayed month outlined in `monthOutline` (blue, 2 pt) as one block outline; bars as rounded rectangles in the calendar colour at about 20% opacity with text in the colour (fallback `Colors.eventDot`), holiday bars in `holidayChip`/`holidayText`, square the corner on a `continues` side, text only on the first piece of each week (and the first column of a week); lines: 6 pt calendar-colour dot + title (timed), outlined rounded checkbox in red (or the list colour) + title with `arrow.triangle.2.circlepath` when recurring, strikethrough when completed; "N more…" grey at the cell bottom when `overflow > 0`. Whole cell is one `Button` selecting `day.date` (VoiceOver label from the day's counts: reuse `DayDensity.accessibilityLabel` via `gridDensity`-equivalent counts, or build "day, N items" from the layout). Register the visible range exactly like `MonthGridView.loadVisibleMonths` (store.loadMonths + `overlay.reload`, with its own registration kind if `AppleFetchWindow` requires one; release on disappear like `YearView`).
- [ ] **Step 3:** Day tap: `selectDate(date)` then `fullMonth = false` (animated), landing on the DayTicker at that day, as the Year does.
- [ ] **Step 4:** Verify with idb: menu > Month opens; chevrons page; swipe pages; day tap lands on that day; menu > Year/DayTicker from Month; the three bar buttons open. Seed dense data first (multi-day bar over a week boundary, a "Holidays"-titled calendar item if the simulator has such a calendar, 4+ timed items on one day, a repeating reminder).
- [ ] **Step 5:** Screenshots light and dark and AX5; compare with IMG_1882/IMG_8834; fix; commit `feat(app): full-screen Month view`.

### Task 4: Docs, verification and ship (controller)

- [ ] **Step 1:** Update `CLAUDE.md` (Fantastical redesign log: Stage 3b Done / Not yet verified / Deferred; Theme/UI rules for new tokens), `docs/ios-feature-notes.md` (a short "Full-screen Month" paragraph: layout rules, holiday rule, agenda parity), spec status line (3b built).
- [ ] **Step 2:** Full verification (`swift test`, `make test-fast` with Node 24, Release device build), merge to main locally, rerun on merged main (clear ModuleCache), push only if all checked results are green, `ship.sh` v2.0.28, log the upload, then the owner's device check list.
