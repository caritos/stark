# Weather in Day, Week and Month Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** The opt-in forecast also shows in the Day, Week and Month views.

**Architecture:** Views read `WeatherModel.forecast` (already injected); a compact chip variant in the app target; a Kit test pins the day-key match.

**Tech Stack:** SwiftUI, Swift Testing, Go + static HTML for copy.

**Spec:** `docs/superpowers/specs/2026-11-18-weather-views-design.md`

## Global Constraints
- Worktree; tests first for any logic (view-only layout changes are verified by screenshots); small commits; never `git add` `ios/.build` or `.superpowers`.
- Kit tests: `cd ios && swift test --scratch-path /private/tmp/claude-501/wv`. Web: `cd web && make test-fast`, `make e2e` (Node 24: `nvm use` inside `web/`, same shell).
- Weather off means nothing drawn and no layout shift; no new data leaves the device; theme tokens only; chips stack or hide at accessibility sizes; VoiceOver labels start "Weather forecast".
- The day key must be the one `WeatherModel.forecast` uses (Gregorian start of day in the phone's time zone).

## Review Focus
- Week/Month on a phone set to a non-Gregorian calendar: the forecast still lands on the right day (the views' own calendars may differ from the model's).
- Month cell too narrow, AX sizes, 4 colour bars plus a glyph: nothing overlaps or clips.
- Days at the edge of the forecast (no forecast): nothing drawn, no gap.
- Weather turned off while a view is open: chips disappear without a relaunch.

### Task 1: Day, Week and Month chips, copy
**Files:** Modify `ios/App/Stark/Stark/FullDayView.swift`, `FullWeekView.swift`, `FullMonthView.swift`; create `ios/App/Stark/Stark/WeatherMiniChip.swift`; modify `FAQView.swift`, `web/public/pages/faq.html`, `docs/ios-feature-notes.md`, `CLAUDE.md`; Test `ios/Tests/StarkKitTests/WeatherDayKeyTests.swift` (new, if a Kit helper is needed) and `web/api/internal/web/web_test.go`.
- [ ] **Step 1:** Web test first: the weather FAQ entry names the Day, Week and Month views (anchored phrase, red); a Kit test (red) that a forecast keyed by the model's Gregorian day is found by the lookup the views use for a Buddhist-calendar `Calendar` and a Hebrew-calendar `Calendar`.
- [ ] **Step 2:** Implement the Kit lookup helper (e.g. `WeatherForecastLookup.day(_ date: Date, in forecast: [Date: DayWeather]) -> DayWeather?`) that normalises through a Gregorian calendar with the phone's time zone; use it in all views including `AgendaView`.
- [ ] **Step 3:** Views: Day header chip (`WeatherChip`); Week column header `WeatherMiniChip` (glyph + high); Month cell glyph in a corner, hidden at accessibility sizes and when the cell is under a minimum width.
- [ ] **Step 4:** Copy (FAQ web and in-app, feature notes, CLAUDE.md "Weather views log (2026-11-18)" with Done / Not yet verified / Deferred); web tests green.
- [ ] **Step 5:** Simulator (iPhone 17, idb): Weather on (simulate a location with `xcrun simctl location <udid> set 37.77,-122.42`), screenshots of Day, Week and Month; Weather off shows none; dark mode; AX5 if feasible. Record seen / not seen honestly.
- [ ] **Step 6:** Full `swift test`, generic iOS and Mac Catalyst Debug builds (`CODE_SIGNING_ALLOWED=NO`), `make test-fast`, `make e2e`; commit `feat: weather in Day, Week and Month`.
