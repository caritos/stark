# todo.txt → Stark Native Migration — Design

Date: 2026-09-20

## Overview

**Goal:** get the author's existing `todo.txt` (8,302 lines: events, birthdays,
tasks, recurring series and completion history) into the native Stark app
(`ios/`) with nothing lost and nothing invented, as the native app's own
`.ics` files (`recurring.ics` + one `YYYY-MM.ics` per month).

The native rewrite (`2026-09-17-stark-native-rewrite-design.md`) abandoned the
`todo.txt` format and shipped no migration path; on its own it would start
every existing user, including the author, on an empty calendar.

**Decisions already made with the user (this design implements them):**

1. **Where it runs:** a TypeScript CLI converter in the existing console layer
   — *not* an in-app importer. The author is the only person who needs it.
2. **How the files are produced:** the TypeScript code writes the `.ics` files
   directly (not JSON handed to a Swift tool). Fidelity to the Swift reader is
   enforced by cross-language tests (see Testing), not by sharing code.
3. **Completed history:** import all of it (4,990 lines), as completed
   reminders / past events.
4. **Tags:** `+project`, `~person`, `%tag`, `@context` stay in the title exactly
   as written. Many real lines are *only* tags (e.g. `~sophia %driving
   %practice`), so moving them out would leave empty titles.

**Not goals:** an in-app importer; keeping the two apps in sync (this is a
one-way, re-runnable export); multi-day event *display* (a native feature gap,
see Known gaps); the birthday age badge; any tag/filter UI.

## The real data (numbers this design was checked against)

Counted from the author's live file with the repo's own parser
(`shared/parser.ts`); every line is accounted for exactly once.

| Bucket | Lines | Becomes |
|---|---:|---|
| Open `type:event` | 3,096 | Event |
| Open `type:birthday` | 72 | Event (yearly where `frequency:yearly`, else one-off) |
| Open `type:anniversary` | 9 | Event, yearly |
| Open, no `type:` | 135 | Reminder |
| Done, plain (no `start:`, no `frequency:`) | 4,665 | Completed Reminder |
| Done, `start:` but no `frequency:`, not typed | 165 | Completed Reminder, due = `start:` |
| Done, `start:` but no `frequency:`, typed event/birthday | 155 | Event (past) |
| Done, `frequency:` + `start:` (live or finished series) | 5 | Recurring Event |
| **Total** | **8,302** | **3,337 Events + 4,965 Reminders** |

Other facts that drive rules below: 371 open recurring items (270 weekly,
70 yearly, 16 daily, 15 monthly); 178 with `frequency-day` (177 weekly and 1
monthly, which is an invalid combination); 11 rules with `frequency-month-day`
(10 monthly: 3 numeric and 7 positional; 1 yearly; none `fifth-*`); 24 with
`every`; 150 with `exdate`; 303 with `recur-until`; 929 all-day and 2,167 timed
open events; 209 events whose `end:` date differs from `start:`; 818 events
with no `end:`; 1,273 events with `location:`; 1,152 events and 21 tasks with
`description:`/`note:` (encoded with `_` for spaces, e.g.
`description:Review_finances_on_personal_capital`); 6 open tasks with neither
`start:` nor `due:`; 39 lines with `key:value`-looking tokens that are not
structural (times in prose such as `9:00`, and real custom keys like
`bus:16:00`); 3 lines using `end-time:`. No priorities. The first real export
also surfaced data problems the converter reports instead of hiding: 1 open task
with `frequency:yearly` and a `due:` but no `start:` (imported as a one-off,
which is how the console's own focus logic treats it too), 2 *completed* lines
with a malformed `start:` (`YYYY-MM-DD:HH:MM` with a colon, and a one-digit
hour) that fall back to the completion date, and 3 lines whose `end:` is
before their `start:`. (An earlier hand count missed these because it skipped
completed lines and did not compare `end:` with `start:`.)

## Architecture

Follows the repo's layering (`shared/` pure transforms, `console/` thin I/O):

- **`shared/commands/exportIcs.ts`** — `applyExportIcs(tasks: Task[]):
  { files: Record<string, string>; report: ExportReport }`. Pure: `Task[]` in,
  file contents and a report out. No I/O, no `process.exit`, no clock
  (`Date.now()` is never read, so output is deterministic and diffable).
  Throws only for programmer errors; every data problem is a *report entry*,
  never an exception and never a silently dropped line.
- **`shared/` helper for occurrences.** Anchor re-basing (below) reuses the
  existing, tested recurrence helpers (`generateTaskOccurrences`,
  `nextWeeklyDate`, `nextMonthlyDate`, `nextYearlyDate`) rather than
  re-deriving recurrence math.
- **`console/commands/export-ics.ts`** — `t export-ics [--file F] [--out DIR]
  [--force]`: resolve the file (`--file` → `TODO_FILE` → `./todo.txt`, the
  existing order), call the transform, write `DIR` (default `./stark-export`),
  print the summary. Refuses to write into a non-empty `DIR` without
  `--force`. Registered in `console/index.ts` and `help`.

**Output:** `DIR/recurring.ics`, `DIR/YYYY-MM.ics` (one per month that has
one-offs), and `DIR/export-report.txt` (human-readable) with the same content
as the returned `report`.

**File format = the format the Swift app already reads and writes.** Verified
against `ICSSerializer`, `ICSDateFormat`, `RRuleCodec`:

- `BEGIN:VCALENDAR` / `VERSION:2.0` / `PRODID:-//Stark//EN`, events then
  reminders, `\r\n` line endings, trailing `\r\n`, no line folding.
- Times are **floating local** (`yyyyMMdd'T'HHmmss`, no `Z`, no `TZID`) —
  todo.txt times are wall-clock, so this is a 1:1 mapping and DST cannot
  shift anything. All-day: `DTSTART;VALUE=DATE:yyyyMMdd`.
- Text escaping: `\` → `\\`, `;` → `\;`, `,` → `\,`, newline → `\n`.
- Event: `UID`, `SUMMARY`, `DTSTART`, `DTEND`?, `DESCRIPTION`?, `LOCATION`?,
  `RRULE`?, one `EXDATE` per exception. Reminder (`VTODO`): `UID`, `SUMMARY`,
  `DUE`?, `DESCRIPTION`?, `PRIORITY`?, `STATUS` (`NEEDS-ACTION`|`COMPLETED`),
  `COMPLETED`?, `RRULE`?, one `EXDATE` per exception.

## Mapping rules

Rules apply in this precedence order; the first match decides the bucket.

### Classification

1. `done` and (`frequency:` and `start:`) → **recurring Event** if typed
   (`event`/`birthday`/`anniversary`), else **recurring Reminder** (see
   Recurring anchors). *(5 lines today: 1 live yearly birthday, 4 anniversaries
   whose `recur-until` has expired — imported faithfully with their `UNTIL`, so
   they simply produce no future occurrences.)*
2. `done`, typed (event/birthday/anniversary) → **one-off Event** at its
   `start:`/`end:`.
3. `done` with `start:` (no `frequency:`) → **completed Reminder**, due =
   `start:`, `completedDate` = the `x` date.
4. `done` otherwise → **completed Reminder**, due = `completedDate` = the `x`
   date at 00:00. (The console's own recurring-completion copies look exactly
   like this: `x <date> [<created>] <title>` with all extensions removed, so
   the 4,665 lines are mostly copies of recurring tasks.)
5. open, typed → **Event**.
6. open, untyped → **Reminder**.

A line that is `%birthday`-tagged but has no `type:` is typed `birthday`, the
same alias `parseLine` already applies. An Event needs a `start:`: a typed line
without one is imported as an undated Reminder and reported
(`event-without-start`) rather than dropped (0 today).

### Dates and times

- `start:YYYY-MM-DD` → all-day (`isAllDay`, `;VALUE=DATE`).
  `start:YYYY-MM-DDTHH:MM` → timed, floating.
- **Event end:** `end:YYYY-MM-DDTHH:MM` → `DTEND` as given. `end:HH:MM` (bare
  time) or `end-time:HH:MM` → same-day `DTEND` at that time. A date-only
  `end:` on an all-day event → `DTEND` date **verbatim** (see Known gaps: the
  Swift serializer also writes `end` verbatim; inclusive vs. RFC-exclusive
  all-day end is a decision for whenever multi-day display is built). A
  date-only `end:` on a *timed* event → `DTEND` on that date at the start's
  time-of-day. An end before the start → `DTEND` omitted, reported
  (`end-before-start`).
- **Reminder due:** `DUE` = `start:` if present, else `due:`. A date-only value
  is written as `T000000` (the agenda already hides a midnight time). If both
  are present and are different dates, the `due:` date is preserved as a
  `Due: YYYY-MM-DD` line in the notes.
- A reminder with neither → no `DUE` (kept, reported `undated`).

### Title, notes, location

- **Title** = the text with **only the known structural keys removed**:
  `type`, `start`, `end`, `end-time`, `frequency`, `frequency-day`,
  `frequency-month-day`, `frequency-month`, `every`, `exdate`, `recur-until`,
  `last-done`, `due`, `location`, `note`, `description`, `reminders-id`;
  whitespace collapsed. **Every other token stays in the title untouched** —
  tags, `bus:16:00`, and the times in prose (`9:00`) that the parser mistakes
  for `key:value`. (`baseText()` strips *all* `key:value` tokens; the
  converter must not reuse it for open lines.) An empty result becomes
  `(untitled)` and is reported.
- **Notes** = `description:` and/or `note:` with `_` → space, joined by a
  newline (description first); plus the `Due:` line above when it applies.
- **Location:** Event → `LOCATION` (`_` → space; values like `@home` are kept
  as-is). Reminder (which has no location field) → a `Location: …` line
  prepended to its notes. (0 such lines today.)
- **Priority:** `(A)`–`(I)` → `PRIORITY:1`–`9`, `(J)`–`(Z)` → `9`. (0 today.)

### Recurrence → `RRULE`

| todo.txt | RRULE |
|---|---|
| `frequency:daily\|weekly\|monthly\|yearly` | `FREQ=DAILY\|WEEKLY\|MONTHLY\|YEARLY` |
| `every:N` (N > 1) | `INTERVAL=N` |
| `frequency-day:` (weekly) `M,T,W,Th,F,Sat,Sun` | `BYDAY=MO,TU,WE,TH,FR,SA,SU` (same order, mapped) |
| `frequency-month-day:N` (monthly or yearly) | `BYMONTHDAY=N` |
| `…:first\|second\|third\|fourth-<weekday>` | `BYDAY=1WE` etc. (ordinal + code) |
| `…:last-<weekday>` | `BYDAY=-1FR` etc. |
| `…:first…fourth-day` | `BYMONTHDAY=1…4` |
| `…:last-day` | `BYMONTHDAY=-1` |
| `…:<pos>-weekday` | `BYDAY=MO,TU,WE,TH,FR;BYSETPOS=<pos or -1>` |
| `…:<pos>-weekend-day` | `BYDAY=SA,SU;BYSETPOS=<pos or -1>` |
| `frequency-month:Jan,…` | `BYMONTH=1,…` |
| `recur-until:YYYY-MM-DD` | `UNTIL=YYYYMMDD` (date-only, as `RRuleCodec` writes) |
| `exdate:d1,d2,…` | one `EXDATE` each, at the anchor's time-of-day (or `;VALUE=DATE` for all-day) |

This matches `RRuleCodec.encode`/`decode` exactly (verified by the golden
tests). Edge rules:

- `fifth-*` is **not representable** (`Position` stops at `fourth` and
  `last`). Any recurrence the encoder cannot express falls back to importing
  the item as a **non-recurring** item at its `start:` and is reported
  (`unsupported-recurrence`, with the original text) — never dropped. (0 today.)
- `frequency-day:` is only meaningful on a weekly rule; `frequency-month-day:`
  only on monthly and yearly rules (the console's `help` documents both);
  `frequency-month:` only on yearly. Anywhere else the extension is ignored and
  reported (`ignored-extension`). Today that is exactly 1 line: a `frequency-day`
  on a monthly rule. (The one yearly rule with `frequency-month-day` is valid and
  converted.)
- Yearly rules need no `BYMONTH`/`BYMONTHDAY`: the anchor supplies month and
  day, and both apps clamp a 31st / Feb 29 to the month's last day.

### Recurring anchors and completion

- **Events keep their original `start:` as the anchor** — the anchor year of a
  yearly birthday is preserved so a future age badge can use it.
- **Reminders re-base to their next undone occurrence.** The console already
  advances `start:` when a weekly/monthly/daily task is completed (yearly is
  not advanced; only `last-done:` changes), so usually `start:` is already the
  right anchor. When `resolvedThrough` = the later of `last-done:` and (for a
  done line) the `x` date is on or after the `start:` date, the anchor becomes
  the **first occurrence of the series strictly after `resolvedThrough`**
  (time-of-day kept), enumerated with the existing shared helpers by passing
  `resolvedThrough + 1 day` as their reference date (no clock involved). The native
  app has no `last-done`, and this makes completed history unnecessary to
  replay as exceptions. A series with no later occurrence (`recur-until`
  passed) keeps its original anchor and its `UNTIL` and is reported
  (`finished-series`). (1 line + the yearly ones today.)
- `exdate:` values carry over unchanged; those before a re-based anchor are
  harmless.

### Identity and placement

- **UID** is deterministic: a UUID-shaped SHA-1 of `raw line + "#" + n` (n =
  the occurrence index of identical lines), so re-running the export produces
  byte-identical files and duplicate lines get distinct ids.
- **Placement copies `PlannerStore`'s routing exactly:** any item with a
  recurrence → `recurring.ics`; otherwise the month of the event's `start` or
  the reminder's `dueDate`. An undated reminder goes in the month of its
  creation date (`YYYY-MM-DD` after the optional priority) or, lacking one, the
  earliest month present in the export — the native store would use "the
  current month", which needs a clock; this stays deterministic and keeps
  `recurring.ics` holding recurring items only.
- Within a file: events, then reminders, each in source order.

## Getting the files onto the phone

Developer workflow, matching the existing `deploy.sh` device loop:

```
xcrun devicectl device copy to --device <id> \
  --domain-type appDataContainer --domain-identifier com.caritos.todo-txt \
  --source stark-export/ --destination /Documents
```

Same-named files overwrite the app's existing month files, so back up first
(`devicectl device copy from … /Documents`). The Expo app's own `todo.txt` in
that container is untouched. The app reads the files on next launch.

## Testing and acceptance

1. **Unit tests** (`shared/tests/commands/exportIcs.test.ts`, `bun test`): one
   test per mapping rule above — each classification bucket, every RRULE row,
   date/time forms, end forms, title rule (tags kept, unknown tokens kept,
   `9:00` kept), notes/location/priority, anchor re-basing (weekly,
   monthly, yearly, finished series), unsupported-recurrence fallback,
   determinism (two runs identical), placement, and **reconciliation**: item
   count in the output equals input line count minus reported drops (none are
   expected).
2. **Cross-language golden fixtures.** A synthetic `todo.txt` fixture covers
   every recurrence form and escaping case (commas, semicolons, backslashes,
   emoji, newlines in notes). Its export is checked in under
   `shared/tests/fixtures/ics/`. The TypeScript test asserts the converter's
   output equals those files **byte for byte**; a Swift test in `StarkKitTests`
   parses the **same files** with the real `ICSParser`/`RRuleCodec.decode`
   (locating them via `#filePath`) and asserts the resulting `Event`/`Reminder`
   values. Divergence between the two implementations fails one of the two
   suites.
3. **Real-data parity check (the acceptance test).** A script exports the
   author's real file plus an *expected agenda* computed with the existing TS
   logic (`applyFocusForWindow` / `generateTaskOccurrences`) for a given day and
   window; a Swift test, enabled only when `STARK_PARITY_DIR` is set (Swift
   Testing `.enabled(if:)`), loads the export directory into a real
   `PlannerStore`, runs `buildAgendaItems`, and compares. **Compared:** (a)
   every event start and every open reminder occurrence dated from today
   through today + 14 days, by kind, date, time and title; (b) open one-off
   reminders that are overdue by 1–90 days. **Not compared, by design:**
   Expo's per-day rows for multi-day events (native shows the start day only),
   completed rows, recurring-reminder overdue rows (Expo and native define
   "overdue" differently for weekday-set and yearly series — that is covered by
   the Swift `AgendaBuilder` unit tests, not a migration question), and
   anything overdue by more than 90 days (see Known gaps). Any other mismatch
   is a mapping bug to fix. The 7 weekly tasks with
   `every > 1` **and** `frequency-day` are the known risk (Expo cycles in 7-day
   blocks from `start:`; native aligns by calendar week); the parity run is
   what proves or disproves them.
4. **Report reconciliation on the real file:** the export summary must show
   exactly 3,337 Events and 4,965 Reminders and zero dropped lines, with each
   report category count matching the table above.

## Known gaps and risks

- **Multi-day events (209)** import correctly (`DTEND` is preserved) but the
  native agenda only expands an event onto its **start** day, so they show
  once, on the first day, and an event that started more than 14 days ago never
  shows even if it is still running. Needs a native feature; not part of this
  work.
- **All-day `DTEND` inclusive vs. exclusive** is written verbatim to match the
  Swift serializer. When native multi-day display is built, decide the
  convention and migrate; until then no native code interprets it.
- **Old overdue tasks stay invisible.** The native agenda pins overdue
  reminders to today only back to `AgendaWindow.overdueLookbackDays` (90 days),
  and `PlannerStore.start` only loads month files inside that range. The
  author's list has overdue one-off tasks going back to May, so those import
  correctly but will not appear until the lookback is raised (or every month
  file is loaded). The parity run counts them and lists them as exempt; the
  fix is a native change, not a converter change.
- **6 undated tasks** import as reminders with no `DUE`, so the native agenda
  cannot show them (`expand(reminder:)` needs a due date). They are also not
  shown by the Expo app today. Kept for a future "no date" list.
- **Week alignment (7 tasks)** described above; verified by the parity run.
- **Events' completion** (the 155 done events) has no native equivalent and is
  dropped as state; the events themselves are kept.
- **Scale:** ~3,300 events and ~5,000 reminders. Startup loads `recurring.ics`
  plus the ~6 month files covering the load window; the month grid's per-day
  counts are computed with caching (see the density-dots work). The parity run
  on the real file is also the first real-size exercise of the app.

## Workflow

1. This spec, reviewed by the user.
2. `writing-plans` → an implementation plan (TDD, one task per rule group, the
   golden-fixture task early because it pins the format).
3. Execution in an isolated worktree, subagent-driven, finishing with the
   parity run against the real `todo.txt` and a device import for the author
   to check by eye.
