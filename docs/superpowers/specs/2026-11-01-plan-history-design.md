# Plan history (look back at past days)

Approved in chat 2026-11-01. Size: small/medium.

## Why
The user wants to see how productive they are: flip back through earlier days, see the timeline as planned, which blocks got done and which did not, with numbers on top.

## What
- A read-only **History** screen (`DayHistoryView`), opened by a button in the planner header. It opens on yesterday (today if the planner was opened for today and there is nothing earlier is not a case: it always opens on the planner's day if that is today, else today). Decision: opens on **today**, with ‹ steps back as far as the user wants, › forward up to today. No future days.
- Shows that day's timeline: events (banner + timed), done blocks (dimmed, check, struck title), and **open blocks** (planned, task not completed). On a past day open blocks are labelled MISSED; on today OPEN.
- Header numbers for the viewed day: `3 DONE - 2 MISSED`, `4h planned - 2h30 done`, completion `60%`. A day with no plan says `NO PLAN`.
- A week line (Sunday-Saturday containing the day, same as Weekly Review): `WEEK: 11 of 16 blocks done - 69%`. Hidden when the week has no plan. (Assistant's call, easy to drop.)
- Entry point is a header button in the planner, not arrows inside the planner (assistant's call: PlannerView is already ~1000 lines).

## Rules
- Pure logic in StarkKit: `DayHistory.make(day:events:reminders:plans:today:)` and `DayHistory.week(...)`. The view only draws.
- A plan block is **done** when its task is completed (same matching as `DayPlanModel.doneBlocks`), **open** when the reminder (by id) still exists and is not completed for that occurrence, and **ignored** when its reminder no longer exists.
- Events marked Skip are left out (as in the planner, issue #117); the midnight-ending-event workaround is reused.
- Planned minutes = sum of done + open block minutes; done minutes = done blocks only. Completion = done / (done + open), nil when 0.
- Never writes anything. Future days are not reachable.
- Limits (told to the user): only planned days have data; a task finished without a block has no slot and does not count; today's numbers are partial.

## Not in v1
Month/trend charts, per-task history, export, editing past plans.
