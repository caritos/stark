# Event attendance (attended / skipped) — design

Native Swift app (`ios/`) only. Status: approved in conversation 2026-09-21, pending written-spec review.

## Goal

Let the user record, per occurrence of an event, that they **attended** it or **skipped** it (chose
not to go), and show that in the agenda. Works for one-off and recurring events. The record stays
visible; it never removes the occurrence.

## Background

- `Event` has no per-occurrence state. Reminders get per-occurrence completion by leaving a
  completed one-off copy; that pattern is heavier and forks a series, and is not used here.
- "Skip This Occurrence" on a recurring event today adds an exception date (`skipEvent`): the
  occurrence *disappears*. That is a different meaning from "I didn't go", so its button is renamed.
- `ICSParser` reads only known properties and drops the rest, so the new data must be parsed
  explicitly. The Swift package is the ground truth for the `.ics` format.
- Prior art: Apple Calendar dims and strikes through *declined* events; Google Calendar draws them
  striped. Neither tracks "did I actually attend". Users ask for exactly this (Google Calendar
  Community, "mark myself as attending … without deleting the event").

## Data model (`StarkKit/Models/Event.swift`)

```swift
public enum EventOutcome: String, Equatable, Codable, Sendable { case attended, skipped }

public struct EventOutcomeRecord: Equatable, Codable, Sendable {
    public var date: Date            // the occurrence (its start), day-granular for matching
    public var outcome: EventOutcome
}
```

`Event` gains `public var outcomes: [EventOutcomeRecord]` (default `[]`, last init parameter, so
every existing call site compiles unchanged). Nothing persists `Event` via `Codable` (only `.ics`),
so the synthesized coding change is safe.

Matching an occurrence to a record is by **calendar day** (gregorian, current time zone), the same
convention as `exceptionDates`. Consequences: editing an event's time of day keeps its marks;
moving its start to a different day orphans marks on the old days (they stop matching and are
harmless; not migrated). An event has at most one occurrence per day, so one record per day.

## `.ics` format (`ICSSerializer` / `ICSParser`)

One line per record on the event's own `VEVENT`, written **after all `EXDATE` lines**, in
`outcomes` order:

```
X-STARK-ATTENDED:20260920T190000
X-STARK-SKIPPED;VALUE=DATE:20260921        (all-day events, mirroring EXDATE's parameter)
```

- Date value formatted with `ICSDateFormat.format(date, allDay: event.isAllDay)`, like `EXDATE`.
- Parser: scan the event block's lines in file order; a line whose property name (text before the
  first `:` or `;`) is exactly `X-STARK-ATTENDED` / `X-STARK-SKIPPED` and whose value parses becomes
  a record; unparseable values are ignored. Order is preserved, so parse → serialize is
  byte-stable. Unknown outcome names are ignored (forward compatibility).
- `VTODO` is unchanged. Other apps ignore `X-` properties.
- A golden fixture (an event with both kinds of mark, one all-day) pins the exact bytes and is
  round-tripped in a test, as the migration fixtures are.
- The TypeScript converter is unchanged: `todo.txt` has no equivalent, so exports never contain
  these lines.

## Store (`PlannerStore`)

`public func setEventOutcome(id: String, on date: Date, outcome: EventOutcome?)`

- Finds the event in `recurringEvents` or any loaded month; unknown id → no-op.
- Removes any existing record for `date`'s calendar day, then (if `outcome != nil`) appends the
  new one and keeps `outcomes` sorted by date, so the file is deterministic.
- Idempotent: setting the state a day already has, or clearing an unmarked day, writes nothing.
- Persists only the file the event lives in (`persistRecurring()` or `persistMonth`), then
  `rebuild()`. It does not move the event between files (no start/recurrence change).
- `skipEvent(id:on:)` is unchanged (still the "remove this occurrence" primitive).
- Deleting an event removes its marks with it (they live on the event).

## Agenda (`AgendaBuilder`)

`AgendaItem` gains `public var outcome: EventOutcome? { get }`: for `.event(let event)`, the
outcome of the record matching `occurrence`'s calendar day, else `nil`; always `nil` for reminders.
It is derived, not stored, so `AgendaItem`'s stored properties and initializer are unchanged.
Sorting, overdue rules, `isCompleted` and `dayDensity` are unaffected (an attended/skipped event
does not move and is still an event for density purposes).

## Row (`AgendaRow.swift`, visuals only)

Event marker and title, using existing `Colors`/`Fonts`, no new colours, hard edges:

| State | Marker (16 pt box) | Title |
| --- | --- | --- |
| none | today's small filled accent square | normal |
| attended | filled accent square with a background-colour ✓ (same as a completed reminder) | normal (the event happened) |
| skipped | outlined square (`Colors.checkboxBorder`) with a ✗ in `Colors.textSecondary` | `Colors.textSecondary`, strikethrough |

VoiceOver summary appends "attended" or "didn't attend". Whole-row tap still opens the detail sheet
(events keep no checkbox target; `AgendaRowTargets` is unchanged).

## Detail sheet (`EditItemView.swift`)

For events, the action section shows, in order: **Attended** (unless already attended), **Didn't
Attend** (unless already skipped), **Clear** (only when a mark exists), then the recurring-only
**Remove This Occurrence** (was "Skip This Occurrence"; behaviour unchanged, events only —
reminders keep "Skip This Occurrence"), then **Delete**. Each mark action calls
`setEventOutcome(id:on: item.occurrence, …)` and dismisses. Marking is allowed for any event, past
or future (no enforcement that it has started). Presentation logic (which buttons show) goes in a
small testable StarkKit type, not in the view.

## Testing

StarkKit (Swift Testing), written test-first:

- Serializer/parser: round trip with attended, skipped, all-day, several marks, none; golden
  fixture byte-equality; unknown/garbled `X-STARK-*` values ignored; marks survive a full
  `serialize → parse → serialize` byte-for-byte.
- Store: set attended / skipped on a one-off (month file) and a recurring occurrence (recurring
  file); replace attended→skipped on the same day; clear; idempotent no-op writes nothing; unknown
  id no-op; persists across reload; two days of one series are independent; a marked day is still
  in the agenda (not exdated); time-of-day differences on the same day match.
- Agenda: `AgendaItem.outcome` for one-off, recurring (marked vs unmarked occurrences), reminders
  (`nil`), orphaned record (`nil`).
- Presentation helper: button set for none / attended / skipped, recurring vs one-off.
- App: build via `xcodebuild`, and verify the row markers and sheet on the real iPhone with
  `ios/App/deploy.sh` (touch and visuals are not unit-testable). The user's real data must stay
  intact; marks are written to the imported `.ics` files, so a backup exists first.

## Out of scope

Tapping the marker to toggle; attendance statistics or history view; reminders; the Expo app;
the TypeScript converter and `todo.txt`; per-occurrence edits other than the mark; migrating marks
when an event's start day changes.

## Docs

Update `CLAUDE.md`'s Native iOS App section: the `X-STARK-ATTENDED`/`X-STARK-SKIPPED` lines, day
matching, and that "Remove This Occurrence" (exception date) differs from "Didn't Attend".
