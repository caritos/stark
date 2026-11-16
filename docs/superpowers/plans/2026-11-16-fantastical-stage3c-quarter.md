# Fantastical Redesign, Stage 3c (Quarter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox syntax.

**Goal:** A full-screen Quarter view (13 week rows) like Fantastical IMG_1884/1885/8833: title "Nov 2026 – Jan 2027" (years red), small day numbers, text-less colour bars, dots, month-start grey pills, thicker seams between months, today's cell pale blue. Menu gets a Quarter entry.

**Architecture:** Generalise the tested `monthLayout` core to take any list of grid days (Kit, tests first), add a 13-week `QuarterGrid`, extend `CalendarViewMenu` with `.quarter`, and draw `FullQuarterView` beside `FullMonthView` as another screen state (like Year/Month, not a `CalendarMode`).

**Tech Stack:** SwiftUI iOS 17+, StarkKit (Swift Testing).

**Spec:** `docs/superpowers/specs/2026-11-16-fantastical-stage3-month-year-design.md` (section 3c). Reference: `docs/fantastical/CATALOG.md`, IMG_1884, IMG_1885, IMG_8833 (in `/Users/eladio/src/stark/docs/fantastical/`, untracked).

## Global Constraints

- Tokens only (`Colors.*`, stage 3a/3b tokens `holidayChip`, `todayCell`, `monthOutline`); no hardcoded colours except an Apple calendar's `colorRGB`. Fonts via `Fonts.mono`.
- Quarter must agree with the agenda about what is on a day: same `buildAgendaItems` + `agendaWithApple` rows as `FullMonthView`.
- Do not change `CalendarMode`, `AgendaWindow`, `AgendaRowTargets`, the existing `monthLayout` behaviour (its tests stay green unchanged).
- Quarter range = 13 weeks starting at the Sunday on or before the first of the displayed month ("Start Quarter View On: First Week of Month"); chevrons and swipe page ONE month (shows next month's 13 weeks), like Fantastical.
- Kit tests under New York, Tokyo, Honolulu, UTC (run with `TZ=` env like the 3b tests). Build: `cd ios/App/Stark && xcodebuild -scheme Stark -destination 'generic/platform=iOS Simulator' -quiet build CODE_SIGNING_ALLOWED=NO`. Kit: `cd ios && swift test` (1138 before). Stale module cache: `rm -rf ios/.build/arm64-apple-macosx/debug/ModuleCache`. `ios/.build` is tracked: never `git add` it; `git checkout -- ios/.build; git clean -fdq ios/.build` before commits.
- Screenshots: `xcrun simctl ui booted appearance light|dark`, `xcrun simctl io booted screenshot`, `idb ui tap` (redirect idb_companion output, never print env). Ship (controller): merge to main, full suite on merged result, Release device build, `(set -a; . ~/.appstoreconnect/env; set +a; ios/App/ship.sh)`, TestFlight v2.0.29. The owner pre-approved TestFlight uploads; never submit for review; website deploy not part of this.

## Done when

- `swift test` green (new tests included), `make test-fast` green (Node 24: `. ~/.nvm/nvm.sh; cd web; nvm use`), Release device build green.
- Screenshots light, dark and AX5 of Quarter with seeded data compared with IMG_1885/8833; idb: menu Quarter opens it, chevrons/swipe page by one month, day tap lands on that day in the DayTicker, Month/Year/DayTicker/Settings entries still work, agenda scroll kept after leaving.
- TestFlight v2.0.29 uploaded. Not part of done: owner device check (report not verified).

## Review Focus

- A quarter starting in a 5-row month, February (leap and not), and a year boundary (Nov -> Jan).
- Bars crossing week rows and month seams; daily repeats stay separate; overdue reminders only on today.
- Capacity: cells about 85 pt tall at default; bars/dots never overflow the cell, no "N more" text (use a small count-free fallback: extra items just not drawn).
- Today tint, month-start pills ("Nov 1" for the 1st of each month, grey), seam lines between months in the right place when a month starts mid-week.

---

### Task 1: Grid-generic layout and QuarterGrid (Kit, TDD)

**Files:** Modify `ios/Sources/StarkKit/Planner/MonthLayout.swift`; create `ios/Sources/StarkKit/Planner/QuarterGrid.swift`, `ios/Tests/StarkKitTests/QuarterGridTests.swift`; add cases to `MonthLayoutTests.swift`.

**Interfaces:**
- Produces: `public func gridLayout(items: [AgendaItem], days: [GridDay], rowCapacity: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> [MonthWeek]` (the existing algorithm with `days` as the grid; `days.count` a multiple of 7); `monthLayout(items:month:rowCapacity:calendar:)` becomes `gridLayout(items:days: MonthGrid.days(for: month), ...)` with identical results. `public enum QuarterGrid { static let weekCount = 13; static func days(startingAt month: YearMonth) -> [GridDay] /* 91 days from the Sunday on or before the 1st */; static func range(for month: YearMonth) -> ClosedRange<Date> or the same type MonthGrid.range returns; static func title(for month: YearMonth) -> (first: String, second: String) /* "Nov 2026", "Jan 2027" parts for red years */; static func monthStarts(in days: [GridDay]) -> [Int] /* indexes of each 1st */; static func seam... }`. Use `GridDay` and range types exactly as `MonthGrid` does; read `MonthGrid.swift` first.
- [ ] **Step 1:** Tests first: `QuarterGridTests` (91 days; starts on the Sunday on or before the 1st; Nov 2026 -> Nov 1 2026 first day... verify with a known calendar; Feb 2027 and Feb 2028 (leap); year boundary Nov 2026 title "Nov 2026"/"Jan 2027"; `monthStarts` finds the 1sts; `range` covers all 91 days) and a `MonthLayoutTests` case proving `gridLayout` over `MonthGrid.days(for:)` equals `monthLayout`, plus one over a 91-day quarter (a bar crossing the Dec seam keeps one lane across weeks, 13 weeks returned).
- [ ] **Step 2:** Run red; implement; full `swift test` green; commit `feat(kit): quarter grid and grid-generic layout`.

### Task 2: Quarter menu entry (Kit, TDD)

**Files:** Modify `ios/Sources/StarkKit/Planner/CalendarViewMenu.swift` and `ios/Tests/StarkKitTests/CalendarViewMenuTests.swift`.

**Interfaces:** `CalendarViewChoice` gains `.quarter` (title "Quarter", image `rectangle.split.3x3`), order `dayTicker, month, quarter, year`. Screen state generalises from `fullMonth: Bool` to `enum FullScreenCalendar { case none, month, quarter }` (public, Equatable, Sendable): `current(for mode:, full: FullScreenCalendar)`, `target(after choice:, current mode:) -> (mode: CalendarMode, full: FullScreenCalendar)` (Month/Quarter from Year give mode `.month`, as Month does now), `accessibilityValue(for:full:)`. Keep behaviour of existing cases; update existing tests to the new signatures and add Quarter cases (quarter from each mode, quarter from year -> month mode, month <-> quarter switches, year turns full off).
- [ ] **Step 1-3:** tests first (red), implement, full `swift test` green, commit `feat(kit): Quarter in the view menu`. The app target will not compile until Task 3.

### Task 3: FullQuarterView and wiring (app)

**Files:** Create `ios/App/Stark/Stark/FullQuarterView.swift`; modify `ContentView.swift` (state `full: FullScreenCalendar` replaces `fullMonth`), `ViewMenu.swift`, `FloatingBottomBar.swift`, `Theme.swift` if a token is needed (`quarterSeam`), and `AppleFetchWindow.Screen` (add `.fullQuarter`, test it like `.fullMonth`).

**Interfaces:** Consumes `gridLayout`, `QuarterGrid`, `FullScreenCalendar`, `CalendarViewMenu`.
- [ ] **Step 1:** Model `FullQuarterView` on `FullMonthView` (read it first, reuse its debounced off-main loader pattern, range registration with `.fullQuarter`, header with red years and chevrons/swipe paging ONE month, caps weekday strip with a light-grey rule). 13 week rows filling the height (minimum 56 pt; scroll if smaller, AX5), day number top-right small, month-start grey pill ("Nov 1", "Dec 1", "Jan 1": month abbreviation + 1) top-right in place of the number, thicker grey seam lines along each month boundary, today's cell `Colors.todayCell` with blue circle number, adjacent cells normal (the quarter has no dimmed days). Events: text-less rounded colour bars (calendar colour, holiday bars use `holidayChip`), timed events and reminders as small dots in the cell (no text); extra items beyond capacity are simply not drawn. Whole cell is one Button (44 pt+): tap selects the date and returns to the DayTicker on that day (same as Month's tap, including moving the DayTicker grid to that month).
- [ ] **Step 2:** Wire menu, bar and ContentView: Quarter opens it, Month/Quarter/Year/DayTicker switching per the Kit target, leaving keeps agenda scroll (agenda hidden not removed, like Year/Month), the `ModeHandle` hidden under Quarter like Month.
- [ ] **Step 3:** Verify in the simulator (seed dense data as 3b did, seed code NOT committed): screenshots light, dark, AX5; compare with IMG_1885/8833; run the idb checks in Done-when; `swift test`; commit `feat(app): full-screen Quarter view`.

### Task 4: Docs, verification and ship (controller)

- [ ] Update `CLAUDE.md` (Stage 3c log: Done / Not yet verified / Deferred; Next), `docs/ios-feature-notes.md` (Quarter next to the Month paragraph), spec status line (3c built). Full verification, merge to main locally (`--ff-only`), rerun on main (clear ModuleCache), push, `ship.sh` v2.0.29, log the upload, remove worktree and branch.
