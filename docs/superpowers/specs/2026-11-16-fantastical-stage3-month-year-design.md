# Fantastical redesign, stage 3: view menu, year, month, quarter

Date: 2026-11-16. Status: approved 2026-11-16; 3a built (v2.0.27), 3b and 3c pending (the menu gets Month and Quarter entries then). Parent: `2026-11-15-fantastical-visual-design.md`. References: `docs/fantastical/CATALOG.md` (IMG_1880-1886, IMG_8832-8834, day-week-year-view/IMG_9158-9159).

## Intent

Stark gets Fantastical's calendar screen family: a round view-menu button, a restyled Year view with the heat map, a full-screen Month view and a Quarter view. The owner wants "pretty much a duplicate" of Fantastical; stages 1-2 (v2.0.25, v2.0.26) restyled the palette, the header/grid, agenda rows and the bottom bar.

## Approaches (owner chose 2)

1. Year restyle only: small, leaves no Month/Quarter screens.
2. **Three sub-stages, each shipped (chosen)**: 3a year + view menu, 3b Month, 3c Quarter.
3. Rebuild the whole family at once: biggest, no feedback until the end.

## Goals

**3a, view menu and Year**
- Left round button of the bottom bar becomes a hamburger (`line.3.horizontal`) that opens a popover menu (frosted, large radius, anchored above it; a plain sheet-style menu on iPhone is acceptable if a popover cannot anchor): group 1 = DayTicker (the current main screen), group 2 = Month, Quarter, Year (checkmark on the current one), group 3 = Settings. Settings moves out of the bar.
- Year view: title "2026" with the year in red, two-column mini-months, weekday initials (today's weekday blue in the displayed month), adjacent-month days grey, heat map from pale yellow (1-2 items) through amber to salmon (heavy) replacing the purple tint (levels from `DayDensity.level`), today = solid blue rounded square with white bold number, pressing/dragging a day shows a magnified white rounded square with a soft shadow (IMG_9159); a tap selects the day and returns to the DayTicker on that day (today's behaviour).
- Fix: year mode must be leavable: the menu entry DayTicker returns to month/week header; the existing drag handle keeps working above the bar (content ends above the bar).

**3b, Month (full screen)**
- Large title "November 2026" (red year), caps weekday strip, six tall week rows; each day cell: number top-right (today = blue circle, cell tinted pale blue), pale-tint rounded bars for all-day events (multi-day events as one continuous bar across cells), lilac chips for holidays (calendar named "Holidays" or subscribed holiday type; otherwise treated as all-day), a coloured dot + truncated title for timed events, a red outlined checkbox + title for reminders (repeat glyph when recurring), overflow "N more…" in grey at the cell bottom; adjacent-month days in grey; the displayed month outlined in blue. Tap a day: opens the DayTicker on that day. Swipe/chevrons page months.
- Layout logic (which items fit, multi-day bar spans per week row, overflow count) is pure and goes in StarkKit with tests first.

**3c, Quarter**
- Title "Nov 2026 - Jan 2027" (years red), 13 week rows, small day numbers, text-less coloured bars per all-day event, dots for timed events, month-start grey pills ("Nov 1"), thicker seam lines between months, today's cell pale blue. Tap a day: DayTicker on that day. Reuses 3b's layout logic with a "no text" density.

## Non-goals

No Day/Week timeline views (stage 4, with the planner), no weather, no calendar sets (the "All Calendars" pill stays as is), no Tasks list screen, no quick add, no new data sources. Data and write paths do not change.

## Constraints

- Items come from the existing engines (`buildAgendaItems`, `agendaWithApple`, `gridDensity`, `AppleSnapshot`); Month/Quarter must not disagree with the agenda about what is on a day (same rule as `gridDensity`).
- New pure logic in StarkKit, tests first, run under four time zones (New York, Tokyo, Honolulu, UTC). Views verified by simulator screenshots in light and dark, each compared with the catalog images; owner device check reported as not verified.
- Fetch windows: Month/Quarter register their visible range with the existing `AppleFetchWindow`/`AppleOverlayModel` so Apple items load (no new store access).
- Row/cell taps must not break the DayTicker's `AgendaRowTargets`; Month/Quarter cells are single tap targets (a day) with 44 pt minimum height.

## My calls (owner can change)

1. Holiday chips are used for calendars whose title contains "Holiday" (case-insensitive) or the subscribed US holidays set; no new setting.
2. "Calendar" family in the menu = Month, Quarter, Year only; DayTicker is the current main screen; Day and Week are hidden until stage 4.
3. Settings moves into the menu; the bottom bar keeps All Calendars and Search+Add.
4. Month cells show at most as many bars/rows as fit; no scrolling inside a cell; "N more…" opens the DayTicker on that day.
5. The current drag-to-year gesture stays as a shortcut.

## Done when (per sub-stage, then overall)

- `cd ios && swift test` green with new layout tests (incl. four time zones); `cd web && make test-fast` green; Release device build green.
- Screenshots light and dark of: the menu, Year (heat map, today square, press preview), Month (dense seeded data: multi-day bar, holiday chip, timed events, tasks, "N more…"), Quarter; compared with the catalog images.
- A day tap lands on the DayTicker at that day; the menu's Settings opens Settings; Search/Add/All Calendars still work.
- TestFlight build uploaded after each sub-stage (v2.0.27, .28, .29); owner device check reported as not verified.
