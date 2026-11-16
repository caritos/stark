# Fantastical Stage 4a (Day and Week timelines) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Day and Week timeline screens in the view menu.
**Architecture:** Kit `TimelineLayout` (pure) turns agenda items into all-day chips and positioned timed blocks per day; app views `FullDayView`/`FullWeekView` draw them over a shared `HourGrid`. Menu/`FullScreenCalendar` extended.
**Tech Stack:** SwiftUI iOS 17+, StarkKit (Swift Testing).
**Spec:** `docs/superpowers/specs/2026-11-16-fantastical-stage4-day-week-design.md`. Visual: `docs/fantastical/CATALOG.md` IMG_1880/1881; model after `FullQuarterView.swift` (header, debounced off-main layout, fetch window, swipe).

## Global Constraints
- Tokens from `Theme.swift` only (add `nowLine`=red = `yearRed`, block fill derived from the calendar colour at 18% opacity; nothing hardcoded except Apple calendar colours).
- Build: `cd ios/App/Stark && xcodebuild -scheme Stark -destination 'generic/platform=iOS Simulator' -quiet build CODE_SIGNING_ALLOWED=NO`; tests `cd ios && swift test`; stale cache: `rm -rf ios/.build/arm64-apple-macosx/debug/ModuleCache`. Never `git add ios/.build`; run `git checkout -- ios/.build; git clean -fdq ios/.build` before commits.
- Day boundaries use the passed `Calendar`; run tests in New York, Tokyo, Honolulu, UTC.
- Ship (controller): merge locally, suite on merged result, `make test-fast` (Node 24 via `. ~/.nvm/nvm.sh; cd web; nvm use`), Release device build, `(set -a; . ~/.appstoreconnect/env; set +a; ios/App/ship.sh)`, TestFlight only.

## Done when
As in the spec.

## Review Focus
- Event crossing midnight (start before day, end after): clipped, both days show it. Zero-length and end-before-start events get 15 minutes. Event ending exactly at midnight does not appear on the next day. DST day (23/25 hours): minutes measured from `startOfDay`, grid always 24 rows. Ten overlapping events: column count 10 does not crash. Empty day.

### Task 1: TimelineLayout (Kit, TDD)
**Files:** Create `ios/Sources/StarkKit/Planner/TimelineLayout.swift`; Test `ios/Tests/StarkKitTests/TimelineLayoutTests.swift`.
**Interfaces:** Produces `public struct TimelineBlock: Equatable, Identifiable { id: String; title: String; startMinute: Int; endMinute: Int /*>= start+15, <= 1440*/; column: Int; columnCount: Int; colorRGB: UInt32?; isReminder: Bool; isCompleted: Bool; isHoliday: Bool? no }`, `public struct TimelineChip: Equatable, Identifiable { id; title; colorRGB: UInt32?; isHoliday: Bool }`, `public struct DayTimeline: Equatable { allDay: [TimelineChip]; blocks: [TimelineBlock] }`, `public func timelineLayout(items: [AgendaItem], day: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> DayTimeline`.
Rules: all-day events and events spanning more than one day (`spanDays`>0 and covering the day) are chips; Apple timed events ending exactly at midnight end the instant before; timed events clip to the day; reminders with a time (not date-only) are 30 minute blocks at their time (clamped to 1440), date-only reminders are chips; overlap grouping: sort by start then longer first, cluster items that transitively overlap, assign the first free column in each cluster, `columnCount` = cluster's column total; holiday = calendar title contains "holiday" (as `gridLayout`). Items whose `displayDate` is not on `day` are ignored.
- [ ] Failing tests (names): `allDayEventIsChip`, `timedEventMinutes`, `crossingMidnightClipsBothDays`, `endAtMidnightNotNextDay`, `zeroLengthGetsFifteenMinutes`, `overlapSharesColumns` (A 9-11, B 10-12, C 11-12 -> A col0, B col1, C col0, count 2), `touchingEventsDoNotShareColumns`, `timedReminderIsThirtyMinuteBlock`, `dateOnlyReminderIsChip`, `dstDayUsesWallClockMinutes` (US spring-forward day, event 9:00 local = minute 540), `tenOverlapsHaveTenColumns`, `otherDaysIgnored`, `emptyDay`; run under the four time zones like `MonthLayoutTests`.
- [ ] Run filter, see red; implement; run filter then full `swift test`; commit `feat(kit): day timeline layout`.

### Task 2: Menu, screens enum, fetch window (Kit, TDD)
**Files:** Modify `CalendarViewMenu.swift`, `AppleFetchWindow` (find with grep), tests `CalendarViewMenuTests`, the fetch window tests.
**Interfaces:** `CalendarViewChoice` order dayTicker, day, week, month, quarter, year (titles "Day", "Week"; images `rectangle.portrait`, `rectangle.split.3x1`); `FullScreenCalendar` adds `.day`, `.week`; `current`/`target` handle them (Day/Week from Year keep `.month` underneath, as Month); `AppleFetchWindow.Screen` adds `.fullDay`, `.fullWeek`.
- [ ] Tests first (current for each full, target from each mode incl. year, titles unique, allCases order); implement; full `swift test`; commit `feat(kit): day and week menu choices`. Fix any app `switch` that becomes non-exhaustive (ViewMenu, ContentView) minimally so the app builds (full wiring is Task 3/4).

### Task 3: Day screen
**Files:** Create `ios/App/Stark/Stark/HourGrid.swift` (shared 24-row grid, labels "12 AM".."noon" red, 60 pt/hour, `NowLine`, minute-to-y helper), `FullDayView.swift`; modify `ContentView.swift`, `ViewMenu.swift`, `Theme.swift`.
- [ ] `FullDayView(today:selectedDate:onSelectDate:onOpenItem:)` mirroring `FullQuarterView` plumbing (inputs struct, debounced detached `timelineLayout`, `AppleFetchWindow.Screen.fullDay` range = the day, load months, unregister on disappear, swipe/chevrons by one day, follows midnight). Header title with red year, caps weekday row (blue if today), chip strip, scrollable grid with blocks (pale fill, colour bar, title and time, min 22 pt drawn height), reminders with a small checkbox glyph, now-line on today updating each minute (`TimelineView(.everyMinute)`), initial scroll to max(now-1h, 7 AM) today else 8 AM. Tap a block calls `onOpenItem` using the same detail path as an agenda row (find how `AgendaView` opens its detail sheet and reuse it; if it needs an `AgendaItem`, keep the item beside the block id). Accessibility: each block `"<title>, <start> to <end>"`, chips by title.
- [ ] Wire ContentView (`full == .day`) and menu; build; seed events with an idb-free approach (simulator Calendar via a temporary seed you delete before committing; never commit seeds); screenshots light/dark/AX5 vs IMG_1880; idb checks: menu, chevrons, block tap opens detail, switching views keeps agenda scroll; commit `feat(app): full-screen Day view`.

### Task 4: Week screen
**Files:** Create `FullWeekView.swift`; modify `ContentView.swift`.
- [ ] 7 columns from the Sunday on or before the selected day (`.fullWeek` range = the 7 days), per-column `timelineLayout`, shared `HourGrid` with vertical hairlines, today's column pale blue (`Colors.todayCell`), header caps weekday + number (today blue circle, tap a header = `onSelectDate`), all-day strip as the union row of chips per column (truncated), blocks without time text when the column is under 60 pt wide (title only, clipped), now-line across with a dot in today's column, title "November 2026" (year red, month of the week's first day... use the Wednesday), chevrons/swipe one week. Screenshots light/dark vs IMG_1881; idb: header tap lands on DayTicker day, block tap opens detail; commit `feat(app): full-screen Week view`.

### Task 5: Docs, verification, ship (controller)
- [ ] `CLAUDE.md` log (Stage 4a Done / Not yet verified / Deferred; Next line now "4b planner restyle + split"), `docs/ios-feature-notes.md` paragraph, spec status; whole-branch review by subagent; full verification and merge; ship v2.0.30; vault `%session` note.
