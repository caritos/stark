# Fantastical Redesign, Stage 2 (agenda and DayTicker) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The main screen (grid header + agenda + floating buttons) looks like Fantastical's DayTicker, with no behaviour change.

**Architecture:** Restyle in place. One small Kit change (per-day event colours for the grid dots, tested first); everything else is app-target drawing. Window/anchor/loading/selection logic and `AgendaRowTargets` are untouched.

**Tech Stack:** SwiftUI iOS 17+, StarkKit (Swift Testing).

**Spec:** `docs/superpowers/specs/2026-11-16-fantastical-stage2-agenda-design.md`. Visual reference: `docs/fantastical/CATALOG.md` and the images beside it (IMG_1876-1879, 1895, 1868, IMG_8828, IMG_8831 are the DayTicker/agenda/month-grid shots; read the catalog entries first).

## Global Constraints

- Stage 1 tokens only (`Colors.*`, `Fonts.mono` = system font, `Spacing`); no new hardcoded colours except an Apple calendar's own `colorRGB`.
- No change to `CalendarMode` rules, `AgendaWindow`, `store.loadMonths`, scroll-sync (`onDayInView`, `GridPagingRequest`), or `AgendaRowTargets` (two sibling `.plain` Buttons; never nest Buttons in a List row).
- TDD for Kit logic; styling verified by simulator screenshots in light AND dark (`xcrun simctl ui booted appearance light|dark`, `xcrun simctl io booted screenshot`, `idb ui tap`; always redirect idb_companion output).
- Build: `cd ios/App/Stark && xcodebuild -scheme Stark -destination 'generic/platform=iOS Simulator' -quiet build CODE_SIGNING_ALLOWED=NO`. Kit tests: `cd ios && swift test` (1094 before this plan; only grows).
- Ship step (controller only): merge to main, full suite on the merged result, device Release build, `ios/App/ship.sh` with credentials from `~/.appstoreconnect/env` sourced in a subshell, TestFlight only.

## Done when

- `cd ios && swift test` green; `cd web && make test-fast` green (Node 24 via nvm); Release device build green.
- Simulator screenshots, light and dark: month-grid state, week state, agenda with an all-day chip, a timed event, a reminder with repeat glyph, an overdue reminder under TODAY, an empty today ("No Events"), the bottom bar; compared with the matching Fantastical catalog shots.
- Checkbox tap completes and row tap opens detail (verified with idb in the simulator).
- TestFlight build uploaded (v2.0.26). Not part of done: owner's device check (reported not verified).

## Review Focus

- Checkbox/row hit targets after the row restyle (a restyled row must not make the whole row one target).
- Today/selected/week-band states when the selected day is today, in an adjacent month's dimmed cell, and in week mode.
- Dots for a day with more than five calendars; a day with only Stark-local (non-Apple) events (no colour: fall back to `Colors.eventDot`).
- Dynamic Type at AX5 on the header, day headers and the bottom bar (no clipping, bar stays reachable).
- Bottom bar vs the last agenda rows (content must scroll clear of the bar).

---

### Task 1: Per-day event colours in the density (Kit, TDD)

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/AgendaDensity.swift`
- Test: `ios/Tests/StarkKitTests/GridDensityTests.swift` (add cases)

**Interfaces:**
- Produces: `DayDensity.eventColors: [UInt32]` (distinct 0xRRGGBB calendar colours of that day's event rows, first-seen order, at most 5; empty when none or when events have no colour), with `init(tasks:events:eventColors: [UInt32] = [])`; `DayDensity` stays `Equatable`/`Sendable`; `.none` unchanged; existing call sites and `level` unaffected. Colours come from Apple events' `colorRGB` (see `AppleModels`); Stark's own events contribute none.

- [ ] **Step 1:** Write failing tests in `GridDensityTests`: (a) two Apple events on one day in different calendars give both colours in first-seen order; (b) the same calendar twice gives one colour; (c) six distinct calendars give exactly five; (d) a local Stark event gives `[]` while `events == 1`; (e) a day with only a reminder has `eventColors == []`.
- [ ] **Step 2:** Run `cd ios && swift test --filter GridDensityTests`; expect failures (no `eventColors`).
- [ ] **Step 3:** Add the field and fill it in `densityCounts` from the event rows `buildAgendaItems` produced (use the agenda item's Apple source colour; look at how `AgendaRow.swift:300` gets `source.colorRGB`).
- [ ] **Step 4:** Run the filter, then the full `swift test`; expect all green.
- [ ] **Step 5:** Commit `feat(kit): per-day event calendar colours in the grid density`.

### Task 2: Header panel and grid (month and week states)

**Files:**
- Modify: `ios/App/Stark/Stark/MonthGridView.swift`, `ModeHandle.swift`, and the header composition in `ContentView.swift` as needed.

**Interfaces:**
- Consumes: `DayDensity.eventColors`, stage 1 tokens, existing `CalendarMode`.
- Produces: no new public types required; drawing only.

- [ ] **Step 1:** Title: large bold month name with the year in red (`Color.red`-family system colour via a token if one is added in `Theme.swift`), chevrons kept (same actions).
- [ ] **Step 2:** Weekday strip in caps (SUN..SAT, grey; today's weekday in the accent). Cells: today = solid accent circle, white number; selected (not today) = outlined circle; current week row on a light grey rounded band (`Colors.separator` at low opacity) in month mode; neighbouring-month days stay dimmed.
- [ ] **Step 3:** Under each number draw up to five 4 pt dots from `eventColors` (fallback single `Colors.eventDot` dot when `events > 0` and `eventColors` is empty) plus a small check-square glyph when `tasks > 0`, replacing the two hairlines; keep the block's fixed height so the grid does not jiggle. VoiceOver labels unchanged (`DayDensity.accessibilityLabel`).
- [ ] **Step 3b:** Week mode keeps the existing single-row behaviour with the same cells (the "ticker" look; no skip-empty-days logic).
- [ ] **Step 4:** `ModeHandle` grabber: a 36 x 5 grey rounded pill at the panel's bottom edge on the header's background (`Colors.separator`), same strip height, same gestures and accessibility.
- [ ] **Step 5:** Screenshots light and dark for month and week states with seeded simulator data (events in 2-3 calendars, a reminder); compare with IMG_1878/IMG_8831; fix; commit `feat(app): DayTicker-style header and grid`.

### Task 3: Agenda rows

**Files:**
- Modify: `ios/App/Stark/Stark/AgendaView.swift` (`headerRow`), `AgendaRow.swift`

**Interfaces:**
- Consumes: existing `AgendaItem`, `AgendaRowTargets` (unchanged behaviour).

- [ ] **Step 1:** Day header: all-caps bold weekday + grey `M/D/YY`; today shows "TODAY" in the accent; keep the plan and export buttons and their accessibility labels; today with no items keeps its "No events" row, reworded "No Events".
- [ ] **Step 2:** All-day events render as a rounded chip (8 pt radius) filled with the calendar colour, white text, hugging the leading margin (not full row width); fall back to `Colors.eventDot` for local events.
- [ ] **Step 3:** Timed events keep their time line, with a 4 pt rounded calendar-colour bar at the leading edge; reminders: outlined rounded-square checkbox (stroke in the list colour, `Colors.checkboxBorder` fallback), repeat glyph (`arrow.triangle.2.circlepath`) after the title when `isRecurring`; completed rows keep strikethrough.
- [ ] **Step 4:** Overdue reminder: the missed date and time in red (system red) above the title (replaces "N days overdue"; the Kit text helpers `OverdueLabel`/`daysOverdue` stay, only the row's drawing changes; VoiceOver still reads the days-overdue text).
- [ ] **Step 5:** Verify with idb: a checkbox tap completes (after the 2.5 s window as before) and a row tap opens the detail; no nested Buttons. Screenshots light and dark of each row kind; commit `feat(app): Fantastical-style agenda rows`.

### Task 4: Floating bottom bar

**Files:**
- Modify: `ios/App/Stark/Stark/ContentView.swift` (the floating add/search/settings buttons, lines near `addButton`, `searchButton`, `settingsButton`)

**Interfaces:**
- Consumes: the existing actions (open Add, Search, Settings) and the Apple calendar visibility screen (`AppleSettingsView` or its calendar list; reuse the existing presentation).

- [ ] **Step 1:** Replace the three round buttons with one bottom bar: left round button (Settings, `gearshape`), centre pill "All Calendars" (opens the existing calendar visibility screen), right pill holding magnifier (Search) and plus (Add); glass effect on iOS 26 (`#available`), `.ultraThinMaterial` on 17; keep every accessibility label and hit target at least 44 pt.
- [ ] **Step 2:** Add bottom padding to the agenda list so the last rows scroll clear of the bar; check at AX5.
- [ ] **Step 3:** Screenshots light and dark (default and AX5); commit `feat(app): Fantastical-style bottom bar`.

### Task 5: Docs, verification and ship (controller)

- [ ] **Step 1:** Update `CLAUDE.md` (add "Stage 2" to the "Fantastical redesign log" with Done / Not yet verified / Deferred; update "Theme/UI rules" if tokens changed), `docs/ios-feature-notes.md` where the grid markers ("two 1 pt lines", "flat accent square") are described, and the spec status.
- [ ] **Step 2:** Full verification (`swift test`, `make test-fast`, Release device build), merge to main locally, rerun on merged main, push main, `ship.sh` (v2.0.26), log the upload, vault session note.
