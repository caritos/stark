# Timeboxing: plan tomorrow onto a timeline

Date: 2026-11-01. App: native iOS (`ios/`), with StarkKit holding all logic. Status: draft for approval.

## Why

Eladio read Marc Zao-Sanders (HBR, "How Timeboxing Works...") and Cal Newport ("Deep Habits: the importance of planning every minute of your work day") and wants to try timeboxing to be more productive. The idea from both: a to-do list does not know how much time you have and does not hold you to anything; moving each task onto the calendar as a block of fixed length does both, stops a task expanding to fill the day, and leaves a record of what was done. Newport plans the next day in one sitting the evening before, and leaves room to rework the day when it slips.

The hypothesis to test: if Eladio spends ten minutes each evening placing tomorrow's tasks as blocks, he gets more of the right things done. This is an experiment, so the first version is the smallest thing that lets him run it for a couple of weeks.

## What he decided

- **Use pattern:** plan tomorrow in one sitting the evening before. Not dragging tasks onto today's open slots as the day goes.
- **Interaction:** drag tasks onto a day timeline. A new block drops at a default length and he resizes it afterwards (no length prompt).
- **What gets placed:** tasks, meaning reminders (the items with a checkbox). Events are never placed; they already have a time and appear on the timeline as fixed, dimmed blocks to plan around.
- **Which tasks are available:** any open task, past, present or future. Recurring tasks included under the rule below.
- **Recurring tasks:** a recurring task with a time is already set; its occurrence due tomorrow shows on the timeline at that time. A recurring task that was not completed is a *past* task: the app already shows it as one open row carrying its oldest miss (no new occurrences are listed while one is open), and that row is in the tray like any past task. No new task is created for a missed occurrence.
- **Due dates do not move.** Placing a task creates a separate plan entry ("do this on this day, at this time, for this long"). The task's own due date, time and recurrence are untouched. A missed task keeps its original due date and its overdue label.
- **Rework:** after saving, the planner can be reopened for the same day to rework it (move, resize, add, remove). *(Today as well as tomorrow is my reading of his "yes" to my guess; the planner takes a day, either today or tomorrow.)*
- **Screen size:** the phone is small, so the planner is its own full-screen view, not part of the agenda.

## Goals

- Plan tomorrow in a single sitting from a full-screen planner.
- See every open task not yet placed in one tray, and drag it onto a scrolling timeline that also shows tomorrow's events.
- Resize, move and remove blocks easily; the plan is editable until he stops caring.
- The agenda then shows a planned task at its planned time with its range ("9:00-9:30"), and ticking it completes the task through the existing completion path (history, recurrence, undo window all unchanged).
- Everything stays local, in the existing `.ics` files, with no new storage mechanism.

## Non-goals and anti-goals

- No countdown timer, focus mode, notifications or alarms.
- No blocks that are not tied to a task ("Email", "Deep work") in v1.
- No automatic scheduling or suggestion of where things go.
- No "move everything unfinished to a later slot" in v1. Unfinished blocks simply lapse when the day passes.
- No changes to how reminders are due, repeat, complete or become overdue.
- Not a new calendar: no multiple calendars, time zones, or planning any day other than today or tomorrow.
- Anti-goal: it must never silently change a task's due date or recurrence, and a plan entry must never make an open task disappear from its normal agenda row.

## How it behaves

**Entry.** A button on the Today and Tomorrow agenda headers (next to the existing export button on Today/Yesterday) opens the planner for that day; it is shown before and after planning, and a saved plan loads back as editable blocks. The title shows the date; a square close button (cancel) and a square check button (save), per the app's sheet convention.

**Timeline.** A vertically scrolling day, about 60 pt per hour. Blocks snap to 15 minutes. Dragging near the top or bottom edge auto-scrolls. Events appear as dimmed purple blocks. Visible range and initial scroll position are the builder's call, but it must reach early morning and late evening and open near the start of the day.

**Tray.** A bottom tray holds the tasks that are open and have no block tomorrow. It shrinks as tasks are placed. Membership:
- One-off open tasks of any date (overdue, due tomorrow with no time, due later), and
- the single open row of a recurring series that has a miss or an unfinished occurrence, per the existing agenda rules,
- minus tasks that already appear on tomorrow's timeline (see next point).

**Already-timed tasks.** A task (one-off or recurring) whose occurrence is due tomorrow at a set time is on the timeline at that time, not in the tray. Dragging it moves it by creating a plan entry; its due time is unchanged. *(My call: not explicitly confirmed.)*

**Placing.** Dragging a task from the tray onto the timeline creates a block of default length 30 minutes *(my call)* starting at the snapped drop position. The block's bottom edge is the resize handle. Dragging a block moves it; dragging it back to the tray, or a remove action, deletes the plan entry and the task returns to the tray.

**Overlaps.** Blocks may not overlap each other; a drop that would overlap lands in the nearest free slot or is refused *(my call, builder picks the exact behaviour)*. Overlapping an event is allowed and shown, since he may deliberately plan around or through it.

**Save.** Check saves the plan; close discards unsaved changes after a confirm if there are any.

**Afterwards.** A planned task appears in tomorrow's agenda section at its planned time with its range, and keeps its original due date text if it was overdue ("due Sep 19"). It shows once per day, not also as an unplanned row. Month and year density treat it like any other item. Completing it follows existing behaviour: an open recurring series' carried misses are cleared together exactly as today, `completeReminder` stays idempotent, and the 2.5 s undo window applies. The plan entry stays after completion as the record of what was planned; removing it never uncompletes anything.

## Constraints

- All logic (tray membership, snapping, overlap handling, plan entries, how the agenda merges them) lives in StarkKit with Swift Testing tests written first; the app target only draws and handles gestures.
- Storage: a new plan entry type persisted in the existing month `.ics` files (the month of the planned day). Older files must still load unchanged, and files without plan entries must be byte-identical to today's output. A missing file means no plans; a read failure throws and is never treated as empty. Never persist absolute paths.
- Plan entries reference tasks by stable id plus the occurrence they plan, not by list position. Because a recurring series' completed copies and exception dates are rewritten as the series advances, the entry must survive completion and skipping (builder designs the reference).
- Any code that moves the agenda window or reads plans must `loadMonths(covering:)` first, as elsewhere in the app.
- Also builds as Mac Catalyst; drag must work with a pointer.
- Same Braun look: dark, hard edges, one accent, no hardcoded hex, `Fonts.mono`.
- Drag, resize, auto-scroll and snapping cannot be proven by unit tests: they get verified on a real iPhone and logged "confirmed on device" separately.
- Add the usual updates: CLAUDE.md Done / Not yet verified log, website FAQ copy for the new feature if user-visible, `swift test`, then a full build for device, then `ship.sh`.

## Left to the builder

Plan entry file format and where in the `.ics` it lives; exact default visible hours; overlap resolution; exact drag gesture implementation; haptics; accessibility actions for people who cannot drag (an "Add to plan" action with a time picker is expected, since VoiceOver users cannot drag).

## Calls settled from the builder check (mine, not his)

- **Deleted task:** its plan entry is dropped silently on load/cleanup. **Edited series:** the entry keeps the task id and the occurrence day it was made for; it is not re-derived.
- **Carried miss:** the entry binds to the series id plus the oldest-miss occurrence shown in the carried row. The planned row *is* the carried row, with its "due Sep 19" label. Completing it clears the misses and the planned day's own occurrence exactly as today, and the timeline drops the block for any cleared occurrence.
- **Lapsed plans:** a plan entry whose day has passed is ignored (not deleted, not shown); the task is back on its normal row. There is no past-plan UI.
- **Timed task that was dragged:** on the planned day its row shows the planned time, and the original due time appears once as a secondary line, never as a second row.
- **All-day and multi-day events:** shown in a banner above the timeline, not as blocks.
- **Default length:** a fixed 30 minutes, no memory per task.
- **Day edges:** blocks are clamped to the visible range and cannot cross midnight; a drop with no free room is refused.

## Open at hand-over

My calls to check: 30 minute default length; already-timed tasks sit on the timeline rather than the tray; blocks cannot overlap each other; today or tomorrow only; entry buttons on the Today and Tomorrow headers; no Duration field on the task itself (the length lives only in the plan entry, which replaces my earlier sketch).
