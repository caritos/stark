# Plan the week: day chevrons in the planner

Approved in chat 2026-11-02 (mockup `planner-header-chevrons` accepted). Size: project (a written design, then a plan).

## Why
Timeboxing today covers only today and tomorrow. Eladio wants to time-block the whole week ahead (and later try themed days, Jack Dorsey style, which needs planning a day that is not tomorrow). He also likes reviewing past days *inside the planner*, not in a separate screen. Hypothesis: if the planner can step to any day, he plans a full week in one sitting (Newport's evening-before idea, widened to the week) and keeps using the review numbers.

## What
- The planner stays a one-day, full-screen editor. The header gets **‹ and ›** chevrons on either side of the day title, stepping one calendar day. Header layout: `✕  ‹  WEDNESDAY / WED NOV 4  ›  ✓`. The day word keeps TODAY / TOMORROW for those two days (existing `dayWord`), otherwise the weekday name.
- **Today and future days are editable**, exactly as today: tray, drag, resize, tap menu (Done / Move / Remove from plan), save. No limit on how far ahead (assistant's call).
- **Past days are view-only** (a day before today's start of day). Same timeline look, shown with the existing plan-history content: events and banner, done blocks (dimmed, check, struck title), open blocks outlined and labelled MISSED. Under the title: `2 DONE - 1 MISSED`, `3h planned - 2h done - 67%` (or `NO PLAN`), and the Sunday-Saturday week line, i.e. what `DayHistory` already computes. "VIEW ONLY" appears in the date line. No tray, no drag, no resize, no block menu, and no ✓ button (✕ only).
- **The separate History screen is removed**: delete the header History button and `DayHistoryView` as a screen. Keep and reuse its drawing for past days; keep `DayHistory` in StarkKit as the logic.
- Entry points are unchanged (calendar-clock button on the Today and Tomorrow agenda headers opens the planner on that day).

## Rules
- A day is editable when `startOfDay(day) >= startOfDay(today)`, else view-only. `today` is the value `ContentView` passes down (views never call `Date()`); if the app is left open past midnight, the day just stepped to may flip from editable to view-only, so the check uses the live `today`.
- Plans may now exist for any editable day. The old rule "plans exist only for today and tomorrow" is lifted; the rule that a plan whose day has passed is **ignored by the agenda/density** (lapsed plans) stays, and those same plans are what the past-day view reads.
- Stepping to a day loads the months it needs (`store.loadMonths(covering:)`, widened by the overdue lookback as `DayHistory`'s view does today); a day in an unloaded month must not silently show empty.
- Each day keeps its own draft. Stepping away from a day with unsaved changes keeps those changes for that day (assistant's call): ✓ saves every day with changes, ✕ discards all of them. Save never deletes entries the planner does not show (existing `PlanDraft.blocksToSave` rule) and never changes a task's due date.
- The tray is built per viewed day by the existing `DayPlanModel` (PAST | day | FUTURE panes split against the viewed day); the middle tab and hint text name the viewed day instead of always TODAY/TOMORROW.
- Block menu "Done" still completes the task through `completeReminder(id:on:)`; it is only reachable on editable days.
- Pure logic stays in StarkKit and is tested first (editable/view-only decision, per-day draft handling, day stepping, any new `DayPlanModel` day wording). The view only draws. `PlannerView.swift` is already about 1000 lines: extract what the change touches rather than growing it.

## Goals
- Plan any future day in the same planner with the same gestures.
- Review any past day in the same screen with no way to edit it.
- Delete the History screen without losing its numbers.

## Non-goals
- A week grid, a day strip, swiping between days (rejected in the mockup round; chevrons only).
- Themed days (a later feature that builds on this).
- Non-task blocks, auto-scheduling, move-unfinished, per-task history, export (all still deferred).
- Editing past plans, in any way.

## Anti-goals (a failure even if it technically works)
- Any path that edits, completes, moves or removes a block on a past day.
- A silent empty timeline for a day whose month file was not loaded.
- Stepping to a day losing the user's unsaved edits on the day they left.

## How it gets made (assistant's calls, existing stack)
Native Swift/SwiftUI in `ios/`, logic in `StarkKit`, Swift Testing, XcodeGen unchanged. No data-format change: plans already live as `X-STARK-PLAN` entries in each day's month `.ics`.

## Verification
Unit tests in StarkKit for the new logic, a clean `swift test`, a build for a physical device, then a simulator run with idb screenshots: chevrons stepping across today, a future day, and a past day (no edit affordances). Touch behavior and VoiceOver (chevron labels, "view only") are logged as "not yet verified on device" until checked on the phone. The `CLAUDE.md` Timeboxing log gets a dated entry; the website FAQ/copy is updated if it mentions History.

## More calls (assistant's, from the builder check; easy to change)
- **One plan per task occurrence across days.** A task occurrence placed in any day's draft or saved plan is hidden from the other days' trays (the same rule as "already on tomorrow's timeline" today). To move it to another day, remove it from the first day, and it returns to the tray.
- **Save and close.** ✓ saves every day with changes, then closes the planner. If any save fails (for example a month file that will not load), the planner stays open, keeps the drafts and shows an error banner. ✕ asks for confirmation only when some day has unsaved changes.
- **Midnight.** If a day with an unsaved draft becomes a past day while the planner is open, that draft is dropped and the day turns view-only; ✓ never writes to a past day.
- **No bounds on stepping**, back or forward. Each step loads the months it needs.
- **Numbers.** Today and future days keep the planner's existing `N DONE - N PLANNED` header. The `3h planned - 2h done - 67%` line and the Sunday-Saturday week line appear on past days only.

## Decided: recurring tasks on a future day (user, 2026-11-02)
A recurring series shows as one open row in the tray (its first unresolved miss, or its next occurrence), and later occurrences stay hidden until that one is completed or skipped (issue #107). Planning a recurring task on any day attaches that one offered occurrence; the next occurrence appears after it is done or skipped. The tray does not offer every occurrence inside the week. Known limit: two sessions of the same recurring task cannot be planned in one sitting.

## Left to the builder
How to split `PlannerView.swift`, the exact chevron button styling (square flat buttons like the other sheets), how the past-day body reuses the history drawing, and accessibility labels.
