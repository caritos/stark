# Fantastical Redesign, Stage 3a (view menu and Year) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hamburger view menu replaces the bar's Settings button, and the Year view looks like Fantastical's (red year, heat map, blue today square, press preview) and can always be left.

**Architecture:** One small Kit type decides the menu entries, the checkmark and the mode a choice leads to (tested first). The rest is app-target drawing in `FloatingBottomBar`, a new `ViewMenu` view and `YearView`. No change to agenda windows, loading, density engines or `AgendaRowTargets`.

**Tech Stack:** SwiftUI iOS 17+, StarkKit (Swift Testing).

**Spec:** `docs/superpowers/specs/2026-11-16-fantastical-stage3-month-year-design.md` (section 3a). Visual reference: `docs/fantastical/CATALOG.md`, IMG_1880-1886, IMG_9158-9159 (year, menu).

## Global Constraints

- Stage 1/2 tokens only (`Colors.*`, `Fonts.mono` = system font, `Spacing`). New colours (heat ramp, year red) become tokens in `Theme.swift` with light and dark values; nothing hardcoded in views.
- Do not touch `CalendarMode` rules, `AgendaWindow`, `store.loadMonths`, scroll-sync, `AgendaRowTargets`, `yearDensity`/`DayDensity`.
- Settings keeps its sheet (`showSettings`); only its entry point moves. Search, Add, All Calendars unchanged.
- Month and Quarter do not exist yet: the menu lists only DayTicker, Year and Settings now (ruling: an entry that opens nothing is worse than a missing one). 3b/3c add their entries by extending the Kit enum.
- Build: `cd ios/App/Stark && xcodebuild -scheme Stark -destination 'generic/platform=iOS Simulator' -quiet build CODE_SIGNING_ALLOWED=NO`. Kit tests: `cd ios && swift test` (1106 before this plan). Stale module cache error after worktree builds: `rm -rf ios/.build/arm64-apple-macosx/debug/ModuleCache`.
- Screenshots: `xcrun simctl ui booted appearance light|dark`, `xcrun simctl io booted screenshot`, `idb ui tap` (redirect idb_companion output, never print env).
- Ship (controller only): merge to main locally, full suite on the merged result, gate the push on checked results, device Release build, `(set -a; . ~/.appstoreconnect/env; set +a; ios/App/ship.sh)` in a subshell, TestFlight only (v2.0.27).

## Done when

- `cd ios && swift test` green (new `CalendarViewMenuTests` included); `cd web && make test-fast` green (Node 24 via nvm); Release device build green.
- Simulator screenshots, light and dark: the menu open, Year (heat map, today square, red title), Year with a day pressed (magnified preview), compared with IMG_1880-1886/IMG_9158-9159.
- idb: hamburger opens the menu; "Settings" opens Settings; "Year" opens Year; "DayTicker" returns; a day tap in Year lands on that day in the agenda; the drag handle and the menu both leave Year; Search, Add, All Calendars still open.
- TestFlight v2.0.27 uploaded. Not part of done: the owner's device check (report as not verified).

## Review Focus

- Year mode left via the menu with the agenda scroll position intact (agenda is hidden, not removed).
- Menu button hit target at least 44 pt and its VoiceOver label/value ("View menu", current view).
- Press preview at the grid edges (leftmost/rightmost column, first/last row) stays on screen and does not select unless released on a day.
- A year with no items (empty heat map) and a day with only reminders still tint.
- Dark mode heat ramp legible (earlier note: year tints faint in dark); AX5 Dynamic Type on the title and menu.

---

### Task 1: View menu model (Kit, TDD)

**Files:**
- Create: `ios/Sources/StarkKit/Planner/CalendarViewMenu.swift`
- Test: `ios/Tests/StarkKitTests/CalendarViewMenuTests.swift`

**Interfaces:**
- Produces: `public enum CalendarViewChoice: CaseIterable, Equatable, Sendable { case dayTicker, year }` with `public var title: String` ("DayTicker", "Year"), `public var systemImage: String`; `public enum CalendarViewMenu` with `static func current(for mode: CalendarMode) -> CalendarViewChoice` (`.year` mode gives `.year`, week/month give `.dayTicker`), `static func mode(after choice: CalendarViewChoice, current: CalendarMode) -> CalendarMode` (`.year` gives `.year`; `.dayTicker` gives `.month` when `current == .year`, else `current` unchanged), `static func accessibilityValue(for mode: CalendarMode) -> String` (the current choice's title).

- [ ] **Step 1:** Write failing tests: `currentForEachMode` (week and month give dayTicker, year gives year); `chooseYearFromAnyMode` (always `.year`); `chooseDayTickerFromYearGivesMonth`; `chooseDayTickerKeepsWeekAndMonth` (week stays week, month stays month); `accessibilityValueNamesCurrentView`; `allChoicesHaveTitleAndImage` (non-empty, unique titles).
- [ ] **Step 2:** Run `cd ios && swift test --filter CalendarViewMenuTests`; expect compile failure/red.
- [ ] **Step 3:** Implement the enum and `CalendarViewMenu` as specified.
- [ ] **Step 4:** Run the filter, then full `swift test`; expect all green.
- [ ] **Step 5:** Commit `feat(kit): view menu choices and mode mapping`.

### Task 2: Hamburger and view menu

**Files:**
- Modify: `ios/App/Stark/Stark/FloatingBottomBar.swift`, `ios/App/Stark/Stark/ContentView.swift`
- Create: `ios/App/Stark/Stark/ViewMenu.swift`

**Interfaces:**
- Consumes: `CalendarViewMenu`, `CalendarViewChoice`, `mode: CalendarMode` state, `showSettings`.
- Produces: `ViewMenu` (SwiftUI view: rows DayTicker, Year with a checkmark on `CalendarViewMenu.current(for:)`, divider, Settings; calls `onChoose(CalendarViewChoice)` and `onSettings()`).

- [ ] **Step 1:** In `FloatingBottomBar` replace the left gear button with a hamburger (`line.3.horizontal`) taking `onMenu: () -> Void`; keep size 52, glass circle; accessibility label "View menu", value from `CalendarViewMenu.accessibilityValue`, hint "Opens the view and settings menu."; drop `onSettings`.
- [ ] **Step 2:** `ViewMenu`: frosted rounded panel (large radius, `.regularMaterial`, soft shadow), rows 44 pt minimum, SF Symbol + title, checkmark on the current view. Present it from `ContentView` as a popover anchored to the hamburger with `.presentationCompactAdaptation(.popover)` (iPhone keeps a popover; ruling: if the anchor fails to place it, fall back to a `.sheet` with `.presentationDetents([.height(220)])`).
- [ ] **Step 3:** In `ContentView`: `@State showViewMenu`; choosing a view sets `mode = CalendarViewMenu.mode(after:current:)` with the existing `withAnimation(.easeInOut(duration: 0.2))` and dismisses the menu; Settings dismisses then sets `showSettings = true` (use `onDismiss` or a short `Task` hop so the sheet is not presented under the popover).
- [ ] **Step 4:** Year content ends above the bar: keep `.contentMargins(.bottom, FloatingBottomBar.clearance)` and move the year `ModeHandle` above the bar's clearance (a bottom padding of `FloatingBottomBar.clearance` on the handle row, or an `.overlay` ordering change) so its drag and tap work. Verify with idb that dragging up leaves Year.
- [ ] **Step 5:** Verify with idb in the simulator: menu opens, each row works, Settings opens Settings, Year then DayTicker returns with the agenda where it was, Search/Add/All Calendars open. Screenshots light and dark of the menu. Commit `feat(app): hamburger view menu`.

### Task 3: Year restyle

**Files:**
- Modify: `ios/App/Stark/Stark/YearView.swift`, `ios/App/Stark/Stark/Theme.swift`

**Interfaces:**
- Consumes: `DayDensity.level` (0-3), `MonthGrid.days`, existing density tasks (unchanged).
- Produces: tokens `Colors.yearRed`, `Colors.heatLow`, `Colors.heatMedium`, `Colors.heatHigh` (pale yellow, amber, salmon in light; deeper equivalents in dark, each a `Color(light:dark:)`).

- [ ] **Step 1:** Header: large bold title with the year in `Colors.yearRed` (match the month header's treatment), chevrons kept (same actions and labels).
- [ ] **Step 2:** Mini-months: bold month name, weekday initials (the displayed current month's today-weekday in `accent`), adjacent-month days in `Colors.textSecondary` and never tinted, two columns kept. Remove the purple/orange tint and `tintColor`; tint a day's rounded-rectangle (6 pt radius) by level: 1 `heatLow`, 2 `heatMedium`, 3 `heatHigh`; text stays `Colors.text` (check contrast in dark). Today: solid `accent` rounded square, white bold number, regardless of heat.
- [ ] **Step 3:** Press preview: replace the per-cell `Button` with one drag gesture (`DragGesture(minimumDistance: 0)`) over each mini-month block that maps the touch to a cell by position (pure index math: column = x / cellWidth, row = y / cellHeight within the 6 x 7 grid); while pressed show a magnified white rounded square (about 2x, soft shadow, number centred, clamped to stay inside the screen, drawn above neighbours with `zIndex`); on release over a cell call `onSelectDate(day.date)`; releasing outside any cell, or after a scroll starts, selects nothing. Keep each cell's VoiceOver label (`counts.accessibilityLabel`) and add `.accessibilityAddTraits(.isButton)` plus `accessibilityAction` selecting the date, because the gesture replaces the Button; neighbouring-month cells stay hidden from VoiceOver.
- [ ] **Step 4:** Check scrolling still works (the vertical `ScrollView` must win for a vertical drag: use `.simultaneousGesture` or a small `minimumDistance` on the cell gesture with a long-press delay, whichever keeps scroll smooth) and verify with idb: tap a day lands on it in the agenda, swipe scrolls the year.
- [ ] **Step 5:** Screenshots light and dark: year with seeded events (1, 2-3, 4+ per day), today square, the preview at an edge; AX5 title. Compare with IMG_1880-1886/IMG_9158-9159; fix; commit `feat(app): Fantastical-style year view`.

### Task 4: Docs, verification and ship (controller)

- [ ] **Step 1:** Update `CLAUDE.md` ("Fantastical redesign log": Stage 3a Done / Not yet verified / Deferred; "Theme/UI rules" for the new tokens), `docs/ios-feature-notes.md` (year view tint colours "purple/orange" and the year-leaving paragraph), the spec status line (3a built; Month/Quarter entries to be added in 3b/3c).
- [ ] **Step 2:** Full verification (`swift test`, `make test-fast` with Node 24, Release device build), merge to main locally, rerun on merged main (clear ModuleCache first), push only if all checked results are green, `ship.sh` v2.0.27, log the upload, vault session note, update the stale Fantastical memory ("keep Braun look" is outdated: the owner chose the Fantastical light design on 2026-11-15).
