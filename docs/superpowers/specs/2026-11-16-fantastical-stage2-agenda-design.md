# Fantastical redesign, stage 2: agenda and DayTicker

Date: 2026-11-16. Status: awaiting owner approval. Parent: `2026-11-15-fantastical-visual-design.md`. Reference: `docs/fantastical/CATALOG.md` (45 owner screenshots, catalogued).

## Intent

Make Stark's main screen (grid header + agenda) read as Fantastical's DayTicker: a header panel with a large title and a grabber that switches between title-only, a week strip and the month grid, over a continuous agenda with Fantastical's row anatomy. The owner wants "pretty much a duplicate"; stage 1 shipped the palette (v2.0.25).

## What already exists (do not rebuild)

Stark already has week/month/year modes with a drag bar (`CalendarMode`, `ModeHandle`, `MonthGridView`, `YearView`), a week row stepped by chevrons, scroll-synced selection and the agenda in one `List`. Stage 2 restyles and reshapes these; it does not change window/anchor/loading logic (CLAUDE.md "Agenda architecture").

## Goals

1. Header: large bold title (month and year, year in red; the existing chevrons stay), weekday caps strip (SUN..SAT, grey; today's weekday blue), today = solid blue circle with white number, selected day = outlined circle, current week row on a light grey rounded band in the month grid, density as up to five colour dots (Apple calendar colours) plus a small check glyph when the day has reminders (replaces the purple/orange hairlines).
2. Grabber: the flat `ModeHandle` bar becomes a grey rounded grabber pill at the panel's bottom edge, same gestures.
3. Week strip state (the ticker): the week mode shows the selected week as day columns (caps weekday, big number, colour bars for events); this is today's week mode restyled, not the "skips empty days" ticker (that variant is deferred, see below).
4. Agenda rows: day headers ALL-CAPS bold weekday plus grey M/D/YY date (today blue "TODAY"), "No Events" row for an empty today; all-day events as rounded filled chips in the calendar colour with white text; timed events keep a time line plus a calendar-colour bar; reminders as an outlined rounded-square checkbox in the list colour with a repeat glyph when recurring; overdue reminders stay pinned under TODAY with the missed date and time in red above the title (matches IMG_1868 and the existing overdue rules).
5. Floating buttons: Settings, Search and Add become Fantastical's bottom bar: left round button, centre pill "All Calendars" (opens the existing Apple calendar visibility screen), right pill with magnifier and plus; glass on iOS 26, material on 17.
6. Light/dark follows the phone (see call 1).

## Non-goals

- No new views (Day, Week timeline, Quarter) and no hamburger popover: stage 4. Month/year restyle: stage 3. Weather, calendar sets editor, quick add, onboarding rebuild: later (issue #120). Behaviour (completion, overdue, selection, windows) does not change.
- No copying of Fantastical assets or wording beyond generic conventions.

## Constraints

- Layout and selection logic that has tests stays in StarkKit; any new pure logic (e.g. which days show a task glyph, caps header text) goes in StarkKit with tests first. Views are verified by screenshots in light and dark, simulator now and the owner's device via TestFlight.
- Row hit-testing rules in CLAUDE.md stay (`AgendaRowTargets` sibling buttons, never nest Buttons in a List row).
- Apple calendar colours come from `colorRGB`; no hardcoded event colours.

## Approaches

1. Restyle in place (chosen): keep the existing views and logic, change drawing and a few components. Lowest risk, matches how stage 1 went.
2. Rebuild the main screen as a new view hierarchy (DayTicker container): closest to Fantastical's structure but discards the tested scroll-sync code. Rejected.

## My calls (owner can change)

1. **Dark list under a light header**: Fantastical's screenshots show the agenda list black under a white header; I do NOT copy that. Header and list both follow the phone's appearance, because a forced split fights the system setting and doubles the colour work. If you want the black list, it is a one-line token swap later.
2. The "skip empty days" ticker and the Day/Week/Quarter views wait for stage 4.
3. "All Calendars" pill opens the existing calendar visibility screen; no calendar sets until a later stage.
4. Weather is not included.

## Done when

- `cd ios && swift test` green (new logic tests included), `make test-fast` green, Release build for a device green.
- Simulator screenshots, light and dark, of: month grid state, week strip state, agenda with all-day chip, timed event, reminder with repeat glyph, overdue reminder under TODAY, empty today ("No Events"), the bottom bar. Compared side by side with the matching Fantastical screenshots from the catalog.
- No change to `AgendaRowTargets` behaviour: checkbox tap completes, row tap opens (verified in the simulator).
- TestFlight build uploaded; owner device check reported as not verified.
