# Recurrence Picker — Design

Date: 2026-09-18

## Overview

**Goal:** Give Stark's native app a Fantastical-quality recurrence picker, closing
the largest gap identified in the MVP rewrite's final review: `AddItemView`
currently has no way to create a `RecurrenceRule` at all, so `recurring.ics`,
`RRULE`, and `OccurrenceExpander`'s rule-matching are unreachable dead code from
a real user's perspective.

**Reference:** Apple Calendar's own "Repeat" flow (screenshots reviewed
2026-09-18): a top-level preset list (Never / Every Day / Every Week / Every 2
Weeks / Every Month / Every Year / Custom), and a Custom screen built around a
`[N] [day/week/month/year]` wheel with contextual sections below it — "On Days"
for weekly, "On Days"/"On Week" for monthly, "On Months" plus the same "On
Days"/"On Week" for yearly.

**Scope decision (made during brainstorming):** match that reference's full
richness rather than a cut-down subset — multi-month yearly recurrence
(`byMonth` as a list), multi-day monthly recurrence (`byMonthDay` as a list),
and multiple positional-day rules per recurrence (`byPositionalDay` as a
list), plus generic day-types (`day`/`weekday`/`weekend-day`) alongside
specific weekdays for positional rules. Each of these maps to a native,
standard RRULE mechanism (see "RRULE encoding" below) — richness here costs
UI complexity, not interop.

**Non-goals for this pass:**
- Wiring the picker into an edit flow. `EditItemView` currently has no edit
  capability at all (only Done/Delete) — that's the separate, not-yet-designed
  "Edit" gap from the final review. This spec only wires the picker into
  `AddItemView`. Editing an existing recurring item's rule is deferred until
  Edit itself is designed.
- Natural-language recurrence entry (still out of scope per the original MVP spec).
- Any change to `PlannerStore`'s file-routing logic — a recurring item still
  goes to `recurring.ics` exactly as today; this spec only changes what a
  `RecurrenceRule` can express and how it's constructed.

## Data model

Three new types, and `RecurrenceRule` grows three fields. No migration
concern — nothing has shipped yet, so this is a straightforward breaking
change to a type that exists only in this branch's history.

```swift
// ios/Sources/StarkKit/Models/Month.swift
public enum Month: Int, Codable, Equatable, CaseIterable, Sendable {
    case january = 1, february, march, april, may, june, july, august,
         september, october, november, december
}

// ios/Sources/StarkKit/Models/PositionalDay.swift
public enum Position: Int, Codable, Equatable, Sendable {
    case first = 1, second, third, fourth
    case last = -1
}

public enum DayTypeOrWeekday: Codable, Equatable, Sendable {
    case weekday(Weekday)   // specific: Sunday...Saturday
    case anyDay             // "day" — any day of the month
    case weekdayOnly        // Mon-Fri
    case weekendDay         // Sat/Sun
}

public struct PositionalDay: Equatable, Codable, Sendable {
    public var position: Position
    public var dayType: DayTypeOrWeekday

    public init(position: Position, dayType: DayTypeOrWeekday) {
        self.position = position
        self.dayType = dayType
    }
}
```

```swift
// ios/Sources/StarkKit/Models/RecurrenceRule.swift (updated)
public struct RecurrenceRule: Equatable, Codable, Sendable {
    public enum Frequency: String, Codable, Equatable, Sendable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    public var interval: Int
    public var byDay: [Weekday]?                 // weekly only
    public var byMonthDay: [Int]?                 // monthly/yearly: "on day(s) N" — mutually exclusive with byPositionalDay
    public var byPositionalDay: [PositionalDay]?  // monthly/yearly: "on the Nth/last [day-type]" — mutually exclusive with byMonthDay
    public var byMonth: [Month]?                  // yearly only: which month(s); nil = anchor's own month
    public var count: Int?
    public var until: Date?
}
```

**Semantics:**
- `byMonth` only applies to `.yearly` (ignored for `.monthly`/`.weekly`/`.daily`).
  `nil` means "whatever month the anchor date falls in" — today's existing
  behavior, unchanged.
- `byMonthDay` and `byPositionalDay` are shared by `.monthly` and `.yearly`
  (they answer "which day(s) within the applicable month(s)"), and are
  mutually exclusive with each other. The picker UI enforces this by clearing
  one when the other gains a value. If a persisted rule somehow has both set
  (hand-edited `.ics`, or a future bug), `OccurrenceExpander` gives
  `byPositionalDay` precedence and ignores `byMonthDay` — an explicit,
  documented tie-break rather than undefined behavior.
- Both `nil` (monthly/yearly, no day specifier) falls back to the anchor
  date's own day-of-month — today's existing default, unchanged.

## `OccurrenceExpander` changes

`matches()`'s `.monthly` and `.yearly` branches need to evaluate the new
fields. Conceptually, for a candidate date to match:

1. **Yearly month gate:** if `byMonth` is set, the candidate's month must be
   in that list; otherwise the candidate's month must equal the anchor's
   month (existing behavior).
2. **Day match**, evaluated within whichever month(s) passed the gate above:
   - if `byPositionalDay` is set: the candidate's day must equal the
     resolved day-of-month for *any* entry in the list, for the candidate's
     specific month/year (a "2nd Tuesday" resolves to a different date each
     month — this must be computed fresh per candidate month, not cached)
   - else if `byMonthDay` is set: the candidate's day must equal *any* value
     in the list, each independently clamped to that month's day count
     (reuses the existing single-value clamping logic, applied per list entry)
   - else: the candidate's day must equal the anchor's day-of-month, clamped
     (existing default, unchanged)
3. **Interval gate:** existing month-count/year-count-since-anchor modulo
   `interval` check, unchanged.

Resolving a `PositionalDay` for a given month: find every day in that month
matching the `dayType` (a specific weekday, or every day for `.anyDay`, or
every Mon-Fri for `.weekdayOnly`, or every Sat/Sun for `.weekendDay`), then
take the `position`-th one from the front (`.first`...`.fourth`) or the one
at the end (`.last`). In practice every weekday occurs at least 4 times in
every possible month length (28-31 days), so `.first`...`.fourth` always
resolve for a real weekday — the resolver still returns `nil` defensively
if a position can't be found (kept for robustness and any future position
beyond `.fourth`, e.g. a hypothetical "5th Friday"), and `matches()` treats
that as "no occurrence this candidate," never an error.

## RRULE encoding (`RRuleCodec`)

Almost everything maps to standard, interoperable RRULE — no custom
`X-` properties needed for this feature:

| Model field | RRULE encoding |
|---|---|
| `byMonthDay: [Int]` | `BYMONTHDAY=1,15` (native list) |
| `byMonth: [Month]` | `BYMONTH=3,9` (native list, 1-12) |
| `byPositionalDay` with `.weekday(w)` | ordinal-prefixed `BYDAY`, e.g. `BYDAY=2TU,-1FR` |
| `byPositionalDay` with `.weekdayOnly`/`.weekendDay` | `BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1` — `BYSETPOS` selects the Nth item (or -1 = last) from the set the other BY-rules generate; this is RRULE's real, standard mechanism for "last weekday of the month" style rules |
| `byPositionalDay` with `.anyDay` at `.last` | `BYMONTHDAY=-1` ("last day of the month") — the only pairing the picker allows (see below) |

**`.anyDay` is only meaningful at `.last`.** `.anyDay` at `.first`/`.second`/
`.third`/`.fourth` would encode as `BYMONTHDAY=1`/`2`/`3`/`4` — indistinguishable
from a plain `byMonthDay` rule on decode, and redundant with "On Days" anyway
("the 2nd day of the month" is just `byMonthDay: [2]`). The picker only offers
`.anyDay` paired with `.last`, which is both the only day-type/position
combination genuinely useful here (no other way to express "the last day of
the month," since month lengths vary) and the only one with an unambiguous
encoding (`BYMONTHDAY=-1`).

`byPositionalDay` as a *list* mixing specific-weekday and generic-day-type
entries (e.g. "2nd Tuesday AND last weekday") requires combining an
ordinal-`BYDAY` entry with a separate `BYSETPOS`-qualified entry in the same
`RRULE` value — RRULE's grammar allows exactly one `BYDAY` and one
`BYSETPOS` property per rule, not per-entry, so a mixed list needs either
(a) restricting `.anyDay`/`.weekdayOnly`/`.weekendDay` to be the *only*
`byPositionalDay` entry when present (simplest, and covers every realistic
use case — nobody needs "2nd Tuesday AND last weekday" in the same rule), or
(b) falling back to encoding the *whole* `byPositionalDay` list as computed
concrete BYMONTHDAY values for that one rule's likely month range, which
defeats genericity. **Decision: (a)** — the picker UI only allows multiple
*specific-weekday* positional entries together (e.g. "1st Monday AND last
Friday" — both plain ordinal `BYDAY`, which combine fine as
`BYDAY=1MO,-1FR`); choosing a generic day-type (`day`/`weekday`/`weekend-day`)
for any entry restricts that rule to a single `byPositionalDay` entry. This
is a picker-level constraint, documented in the UI section below, not a
silent data-model limitation.

`RRuleCodec.decode` correspondingly needs to recognize `BYSETPOS` and
negative `BYMONTHDAY` values and route them back into `byPositionalDay`
rather than `byMonthDay`.

## UI flow

```
AddItemView
  "Repeat" row (label + live summary, e.g. "Never", "Every day", "Custom")
    → RepeatPickerView
        List: Never, Every Day, Every Week, Every 2 Weeks, Every Month,
              Every Year, Custom
        - Selecting a non-Custom preset builds a plain RecurrenceRule
          (or nil, for "Never") directly and pops back.
        - Selecting Custom pushes...
    → CustomRepeatView
        - Header: "Repeat: <live summary>"
        - Wheel picker: [interval 1...99] [day | week | month | year]
        - Contextual section, based on the unit:
          - day: none
          - week: "On Days" — checkable list, Sunday...Saturday (→ byDay)
          - month: "On Days" (→ OnDaysPickerView) and "On Week"
            (→ OnWeekPickerView) rows, mutually exclusive (picking a value
            in one clears the other)
          - year: "On Months" — checkable list, January...December
            (→ byMonth), plus the same "On Days"/"On Week" rows as month
        - "Ends" section: Never / On Date (date picker) / After [N] times
          (→ until / count, mutually exclusive)
```

**New view files** (`ios/App/Stark/Stark/`):
- `RepeatPickerView.swift` — the preset list
- `CustomRepeatView.swift` — the wheel + contextual sections + Ends
- `OnDaysPickerView.swift` — multi-select day-of-month (1...31), shared by
  month and year contexts
- `OnWeekPickerView.swift` — manage a list of `PositionalDay` entries
  (add/remove position+day-type pairs), shared by month and year contexts.
  Enforces the single-generic-entry constraint from the RRULE encoding
  section: selecting a generic day-type (`day`/`weekday`/`weekend-day`)
  for any entry clears all other entries and disables adding more until
  that entry is removed or changed back to a specific weekday.

**Modified:** `AddItemView.swift` gains the "Repeat" row and holds the
in-progress `RecurrenceRule?` as local `@State`, passed to
`store.addEvent`/`addReminder` on submit exactly as any other field today.

## Testing strategy

`StarkKit` stays fully TDD, matching the original MVP plan's discipline:

- **Models:** `PositionalDay`/`Month`/`Position`/`DayTypeOrWeekday` are
  plain, no dedicated tests beyond what's needed to support the tests below.
- **`OccurrenceExpander`:** new cases for — multi-day-of-month monthly
  (`byMonthDay: [1, 15]`), multi-month yearly (`byMonth: [.march, .september]`),
  positional monthly with a specific weekday (2nd Tuesday), positional
  monthly with a generic day-type (last weekday), positional yearly
  combined with `byMonth`, a `.fourth`-position rule that has no match in a
  short month (produces zero occurrences that month, not an error), and the
  documented `byPositionalDay`-wins-over-`byMonthDay` tie-break when both
  are somehow set.
- **`RRuleCodec`:** round-trip encode/decode for every row in the encoding
  table above, including the `BYSETPOS` and negative-`BYMONTHDAY` cases, and
  a test confirming a list of purely-specific-weekday positional entries
  round-trips as a single multi-value ordinal `BYDAY`.
- **UI (`RepeatPickerView`, `CustomRepeatView`, `OnDaysPickerView`,
  `OnWeekPickerView`):** not unit-tested — verified manually in the
  simulator, per the established pattern for this app's SwiftUI layer.

## Relationship to existing work

This extends three tasks from the original MVP plan
(`docs/superpowers/plans/2026-09-17-stark-native-rewrite.md`): the
`RecurrenceRule` model (originally Task 3), `OccurrenceExpander` (Task 4),
and `RRuleCodec`/`ICSSerializer`/`ICSParser` (Task 5/6) all gain the fields
and encoding logic above. `AddItemView` (Task 11) gains the Repeat row and
four new sibling view files. No changes to `PlannerStore`, `PlannerFile`, or
the `.ics` file-partitioning scheme (`recurring.ics` vs. `YYYY-MM.ics`) —
those are unaffected by what a `RecurrenceRule` can express.
