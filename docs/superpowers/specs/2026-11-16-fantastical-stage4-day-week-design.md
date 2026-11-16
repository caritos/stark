# Fantastical redesign, stage 4: Day and Week timelines, planner restyle

Date: 2026-11-16. Status: 4a built (v2.0.30); approved by the owner's standing "just go ahead" (2026-11-16). Parent: `2026-11-15-fantastical-visual-design.md`. References: `docs/fantastical/CATALOG.md` IMG_1880 (Day), IMG_1881 (Week).

## Intent
The view menu gets Day and Week: read-only hour timelines of what Apple Calendar and Reminders hold, like Fantastical. The timeboxing planner (tray, drag, plan blocks) stays a separate screen; it is restyled and its 1340-line file split. Two sub-stages, each shipped: 4a Day/Week (v2.0.30), 4b planner restyle + split (v2.0.31).

## Goals (4a)
- Menu order: DayTicker, Day, Week, Month, Quarter, Year (checkmark on the current one). Day and Week are full-screen like Month/Quarter (`FullScreenCalendar` gains `.day`, `.week`).
- Day: title "November 16, 2026" (year red), chevrons and swipe step one day; small row "MONDAY" (blue caps, today only blue) ; all-day items as chips above the timeline; hour grid, label at each rule ("2 AM", "noon" in red), about 60 pt per hour, scrolls; opens scrolled near now (today) or 8 AM; red now-line with dot on today.
- Week: title "November 2026"; 7 columns (Sunday first, as the grid), caps weekday + day number (today blue circle, column pale blue), all-day strip, same hour grid with vertical hairlines, now-line across today's column; chevrons/swipe step one week.
- Timed events are rounded blocks in the calendar colour (pale fill, colour bar at left, title + time), overlapping events share width in columns; timed reminders are 30-minute blocks with a checkbox glyph; an event crossing midnight is clipped to the day; tap a block opens the same detail as the agenda row; tap a day header in Week opens the DayTicker on that day.
- Pure layout in StarkKit, tests first, four time zones.

## Non-goals
Weather, drag-to-create/move on the timeline, settings for day start/end hours, highlight weekends, pinch zoom.

Multi-day timed events (ruling 2026-11-16, review M3): a clipped block on their first and last day, an all-day chip on each fully covered middle day; a block's time text reads the real start and end (with the date when that end is on another day).

## Constraints
Data from `buildAgendaItems` + `agendaWithApple` like Month; own `AppleFetchWindow.Screen` cases (`.fullDay`, `.fullWeek`); no change to write paths. Hit targets: blocks may be small (a 15 minute event is 15 pt) but get a 22 pt minimum drawn height.

## Done when
- `cd ios && swift test` green with `TimelineLayoutTests` (4 zones); `cd web && make test-fast` green (Node 24); Release device build green.
- Simulator screenshots light and dark of Day and Week with seeded overlapping events, all-day chip, reminder; menu with six entries; idb: menu opens each, chevrons/swipe step, block tap opens detail, Week header tap lands on DayTicker day.
- TestFlight v2.0.30 uploaded. Not part of done: device check.

## Approaches
1. Reuse the planner's timeline view: couples read-only display to the editing machinery (1340 lines). Rejected.
2. **New small read-only views over a new Kit layout (chosen).**
3. UIKit calendar component: no.
