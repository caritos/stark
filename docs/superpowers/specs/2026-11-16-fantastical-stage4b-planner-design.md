# Fantastical redesign, stage 4b: planner restyle and split

Date: 2026-11-16. Status: built (v2.0.31); approved by the owner's standing "just go ahead" ("Just continue development"). Parent: stage 4 spec `2026-11-16-fantastical-stage4-day-week-design.md`.

## Intent
The timeboxing planner (tray, drag, resize, plan blocks, past-day view) keeps all behaviour but looks like the new Day view, and `PlannerView.swift` (1340 lines) is split so no file is a monolith.

## Goals
1. Split (pure refactor, no behaviour change, committed first): `PlannerView.swift` keeps state, body, header, save/close; `PlannerView+Timeline.swift` (positions, banner, timeline, slot rows, event/timed task/plan/done blocks), `PlannerView+Lift.swift` (lift/drag/auto-scroll), `PlannerView+Tray.swift` (tray, tabs, panes, chips, changes), `PlannerSupport.swift` (`Lift`, `LiftRecognizer`, `Resize`, `TimePick`, `PlanTimePicker`). Members lose `private` only where an extension in another file needs them; each file under about 450 lines.
2. Restyle: hour labels, rules and the red now-line use the `HourGrid` tokens (`Colors.hourRule`, `Colors.nowLine`, red "noon"); calendar event blocks look like Day-view blocks (rounded 6 pt, pale calendar-colour fill, colour bar at the left); plan blocks and timed tasks get the same rounded corners with the accent fill; tray chips and tabs rounded to match; header uses the stage 2 large-title style. The drag, resize, placement and snapping geometry (15 minute grid, slot height) does not change.

## Non-goals
Behaviour changes, new planner features, Day/Week editing.

## Done when
- `cd ios && swift test` green (1183 before); simulator Release/Debug build green; Release device build green; `cd web && make test-fast` green.
- Split commit changes no behaviour: the same tests pass and a diff of the moved code shows only access-level changes.
- Simulator screenshots light and dark: planner with events, a placed block, a timed task, tray panes, past day; idb: open planner, tap-to-place from tray, tap block opens menu, step days, save, close.
- TestFlight v2.0.31 uploaded. Not part of done: device drag/resize check.
