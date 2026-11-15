# EventKit write spikes (2026-11-15)

Task 1 of `docs/superpowers/plans/2026-11-15-apple-write-path-phase1.md`. Every result below was
observed on the **iOS Simulator only** (iPhone 17, iOS 26 runtime, Xcode 26.6, time zone
America/New_York, run on 2026-11-15 around 09:05 local, a Sunday). Nothing touched the owner's real
Calendar or Reminders. The harness was a throwaway SwiftUI app (`com.caritos.ekspike`, not committed)
that created a scratch calendar "Spike Calendar" and a scratch list "Spike List" in the simulator's
local source, ran each experiment, wrote structured lines to `Documents/spike.txt`, and was read back
with `xcrun simctl get_app_container <udid> com.caritos.ekspike data`. Access was granted with
`xcrun simctl privacy <udid> grant calendar|reminders com.caritos.ekspike` and confirmed by
`requestFullAccessToEvents()`/`requestFullAccessToReminders()` returning `true` (status 3 =
`.fullAccess`).

"D" below means today (Sun 2026-11-15); "D-2" two days ago, and so on. "Fresh fetch" means a second
`EKEventStore` instance, `reset()` before every read, so nothing comes from the writer's cache.

Harness pitfall worth keeping: creating a new `EKEventStore()` for every read stopped working after
roughly 30 instances in one process (every later fetch returned nil/empty without an error). The app
must keep one long-lived store (as `EventKitProvider` already does); a second reader store with
`reset()` is fine.

## (a) Completing a recurring reminder

**Calls:** `EKReminder(eventStore:)`, `dueDateComponents = [y,m,d,h,min]` (or `[y,m,d]` for
date-only), `addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily|.weekly|.monthly, interval: 1, end: nil))`,
`save(_:commit: true)`; then `isCompleted = true` and either `save(_:commit: true)` or
`save(_:commit: false)` + `commit()`. Read back with `calendarItem(withIdentifier:)`,
`calendarItems(withExternalIdentifier:)` and `fetchReminders(matching: predicateForReminders(in: [list]))`
on a fresh store.

**Observed (raw, condensed):**

| Case (now = D 09:04) | Before | After completion, open master (same `calendarItemIdentifier`) | Completed copy (new identifier) |
|---|---|---|---|
| daily, due D-2 07:30 | due 11-13 07:30 | due **11-16 07:30**, `isCompleted=false`, `completionDate=nil`, rule kept | due 11-13 07:30, `isCompleted=true`, `completionDate=D 09:04`, `rules=[]` |
| weekly, due D-2 07:30 | 11-13 | **11-20** 07:30 | 11-13, completed |
| monthly, due D-2 07:30 | 11-13 | **12-13** 07:30 | 11-13, completed |
| daily, due D 07:30 (already past) | 11-15 | **11-16** | 11-15, completed |
| daily, due D-2 **23:00** (later today still ahead) | 11-13 23:00 | **11-15 23:00** (today) | 11-13 23:00, completed |
| daily, **date-only**, due D-2 | 11-13 | **11-16** (date-only stays date-only) | 11-13, completed |
| weekly date-only, due D-3 | 11-12 | 11-19 | 11-12, completed |
| weekly BYDAY=MO,WE,FR, due Wed 11-11 08:00 | 11-11 | **Mon 11-16** (Fri 11-13 skipped) | 11-11, completed |
| weekly, due **D+6** (future) | 11-21 | 11-28 | 11-21, completed |
| second completion of the advanced daily (due 11-16) | 11-16 | 11-17 | 11-16, completed (a second copy) |
| daily COUNT=2, due D-1 08:00 | COUNT=2 | due 11-16, rule now **COUNT=1** | 11-14, completed |
| same, completed again (COUNT=1) | | **no copy; the master itself becomes `isCompleted=true`**, due 11-16, rule still COUNT=1 | none |
| daily UNTIL D 23:59, due D-1 08:00 | | **no copy; master completed** (next after now would be 11-16, past UNTIL; today's 08:00 is not offered) | none |

- The series **advances; it does not end** (unless no occurrence is left, see the last two rows).
  EventKit does the whole job in the one save: it writes a new non-recurring completed reminder for
  the occurrence just done and moves the open master to the next due date.
- The next due date is the first occurrence **after both the old due date and now**. Missed
  occurrences in between are skipped silently (no copies for them). A date-only occurrence on today
  counts as already passed (date-only due D-2 jumps to D+1), a timed one later today does not (23:00
  case stays on today).
- With a COUNT, every completion decrements COUNT by one; skipped misses are not counted.
- The in-memory object you saved reflects the result immediately (same object reads
  `isCompleted=false`, new due, `completionDate=nil`), and a fresh fetch agrees.
- `startDateComponents` moves together with the due date (it was set equal to the due by EventKit;
  a date-only due gets a start of 00:00).
- Identifiers on the local source: `calendarItemIdentifier == calendarItemExternalIdentifier` (one
  UUID) for reminders. The open master **keeps its identifier** through every completion; each
  completed copy gets a new UUID. `calendarItems(withExternalIdentifier:)` on the master's external id
  returns 1 item (the master), not the copies. Nothing links a copy to its series except title and
  list.
- `save(_:commit: true)` vs `save(_:commit: false)` + `commit()`: **identical results** for daily,
  weekly and monthly.
- Un-completing a completed copy (`isCompleted = false` + save) turns the copy into an ordinary open
  one-off reminder on its old due date; the master is not rolled back (both are then open).
- A recurring reminder without a due date cannot be saved: `EKErrorDomain Code=18 "A repeating
  reminder must have a due date."`

**Decision for Task 6:** `complete` for a recurring reminder is simply `isCompleted = true` + save;
the repository must **not** move the due date itself (EventKit already does; doing it too would skip
an extra occurrence). After the save, re-read the master: if it is `isCompleted == true` the series
ended (COUNT/UNTIL exhausted). Completion history is available: the completed copies are ordinary
completed reminders returned by `predicateForCompletedReminders` (match them to the series by title +
list only if needed). `uncomplete` of a completed copy cannot restore the master's previous due date;
plain `isCompleted = false` leaves two open items. Proposed: for a reminder without rules, uncomplete
as usual (it is a one-off or a copy, and both are a single item in EventKit); do not offer anything
that tries to "rewind" a series. Recurring reminders created by Stark must always carry a due date
(validate before save; Code 18 otherwise).

Behaviour difference from today's Stark worth knowing (not a spec contradiction, the spec says "as in
Apple's Reminders app"): when a timed daily reminder is carried from a miss and its time today is still
ahead, completing the carried row leaves today's occurrence open (master due today 23:00), whereas
Stark's local store folds today's occurrence into the carried row. For date-only reminders and times
already past today, EventKit and Stark agree.

## (b) Editing a recurring event series

**Calls:** a daily event, D-3 09:00-10:00, `EKRecurrenceEnd(occurrenceCount: 8)`, saved with
`.futureEvents`. Occurrence #4 (D+1) fetched with `predicateForEvents(withStart:end:calendars:)`,
title changed (and in one case moved to 15:00), saved with `.thisEvent` (becomes detached). Then
`event(withIdentifier: eventIdentifier)` on a fresh store, edit, `save(_:span: .futureEvents, commit: true)`.

**Observed:**

- `event(withIdentifier:)` returns the **master**: `startDate`/`occurrenceDate` = the series DTSTART
  (11-12 09:00), `isDetached=false`, the rule attached. It returns the series DTSTART **even when that
  first occurrence has been deleted** (`.thisEvent` on occurrence #0, then `event(withIdentifier:)`
  still reads start 11-12 and every remaining occurrence shares the same `eventIdentifier`).
- Title change on the master + `.futureEvents`: all 7 regular occurrences renamed, same
  `eventIdentifier`, rule unchanged (COUNT=8). The detached occurrence **survives** and keeps its own
  title ("... DETACHED").
- Time change on the master (+2 h) + `.futureEvents`: every regular occurrence moved to 11:00. The
  detached occurrence survives; if it still had the series time (only its title was changed) it
  **moved with the series** to 11:00; if it had its own time (moved to 15:00) it **kept 15:00**. Its
  title stayed its own in both cases.
- Recurrence rule change on the master (daily COUNT=8 -> weekly COUNT=3) + `.futureEvents`: the
  detached occurrence (11-16 15:00) **disappeared**; only 11-12, 11-19, 11-26 remain.
- Saving a **mid-series occurrence** (from the predicate, 11-14) with `.futureEvents` **splits the
  series**: the original keeps 11-12..11-13 with its rule rewritten to COUNT=2; a new series with a
  **new `eventIdentifier` and `calendarItemIdentifier`** holds 11-14 onward (COUNT=6, renamed), and the
  later detached occurrence moved to the new series (its id became `<newExtId>/RID=...`).
- Identifiers: `eventIdentifier` = `<sourceIdentifier>:<externalId>`; `calendarItemIdentifier` is a
  different UUID; `calendarItemExternalIdentifier` = the external id. All regular occurrences share the
  master's three identifiers. A detached occurrence has its own `calendarItemIdentifier`, and
  `eventIdentifier`/`calendarItemExternalIdentifier` = master's + `/RID=<seconds since 2001-01-01 UTC
  of the original occurrence>` (e.g. `/RID=816530400` = 2026-11-16 14:00Z = 09:00 local).

**Decision for Task 6 (and the spec's "Editing a series"):** confirmed. Whole-series edits must load
the master with `event(withIdentifier:)` and save `.futureEvents`; never save an occurrence from a
predicate fetch with `.futureEvents` (that splits the series and changes identifiers). Changing the
repeat rule drops detached exceptions; that is acceptable for Stark (it never creates detached
occurrences) but the edit sheet should not promise to keep them. Since `EventKitProvider` maps
`eventIdentifier` as the item id, a detached occurrence arrives with a `/RID=` id; to resolve its
series strip the `/RID=...` suffix (not tested here: whether `event(withIdentifier:)` with the
`/RID=` id returns the detached occurrence; Task 6 should not depend on it).

## (c) Deleting one occurrence and the whole series

**Calls and observed:**

- `remove(occurrence, span: .thisEvent, commit: true)` on occurrence #2 (11-14) of a COUNT=8 daily
  series: that day disappears (7 occurrences), the master's rule is unchanged (COUNT=8; EventKit adds
  an exception, the count still includes the removed day). Identifiers unchanged.
- `remove(occurrence 11-17, span: .futureEvents)` from the middle: the series ends before that
  occurrence (rule rewritten to COUNT=5, which counts the removed 11-14), 4 occurrences left.
- `remove(event(withIdentifier:), span: .futureEvents)` on a series with a detached occurrence: **all
  occurrences gone, the detached one too**; `event(withIdentifier:)` then returns nil.
- `remove(event(withIdentifier:), span: .thisEvent)`: removes **only the first occurrence**; the
  series continues from 11-13 with the same identifiers.
- Recurring reminder: `remove(_:commit: true)` removes it (fresh lookup by identifier is nil).

**Decision for Task 6:** delete series = `remove(master, span: .futureEvents)` with the master from
`event(withIdentifier:)` (never `.thisEvent` on the master; that only removes the first day). Skip one
event occurrence = `remove(occurrence, span: .thisEvent)` with the occurrence found by a predicate
fetch over that day (matching `eventIdentifier` and `occurrenceDate`/start).

## (d) Which `RecurrenceRule` shapes round-trip through `EKRecurrenceRule`

**Calls:** for each shape, `EKRecurrenceRule(recurrenceWith:interval:daysOfTheWeek:daysOfTheMonth:monthsOfTheYear:weeksOfTheYear:daysOfTheYear:setPositions:end:)`
set on a new event (start D+1 = Mon 11-16 09:00) and a new reminder (due the same), saved, read back
from a fresh store; for events, occurrences listed over 400 days. Built and read-back
`description` RRULE strings were identical in **every** case, for events and for reminders.

| Stark shape | EventKit form | RRULE read back | Occurrences (event) |
|---|---|---|---|
| weekly MO,WE,FR | `daysOfTheWeek [MO,WE,FR]` | `FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE,FR` | 11-16, 18, 20, 23 ... |
| weekly interval 2 TU,TH | interval 2 | `...;INTERVAL=2;BYDAY=TU,TH;WKST=MO` (EventKit adds WKST=MO) | 11-16(DTSTART), 17, 19, 12-01, 03 ... |
| daily interval 2 | interval 2 | `FREQ=DAILY;INTERVAL=2` | every 2nd day |
| monthly day 15 | `daysOfTheMonth [15]` | `BYMONTHDAY=15` | 12-15, 1-15 ... |
| monthly days 1,15 | `[1,15]` | `BYMONTHDAY=1,15` | both days |
| monthly day 31 | `[31]` | `BYMONTHDAY=31` | **months without a 31st are skipped** (12-31, 1-31, 3-31) |
| last day of month | `daysOfTheMonth [-1]` | `BYMONTHDAY=-1` | 11-30, 12-31, 2-28 ... |
| last day (alternative) | all 7 days + `setPositions [-1]` | `BYDAY=SU..SA;BYSETPOS=-1` | same dates |
| 2nd Tuesday | `EKRecurrenceDayOfWeek(.tuesday, weekNumber: 2)` | `BYDAY=2TU` | 12-08, 1-12, 2-09 ... |
| 2nd Tuesday (alternative) | `[TU]` + `setPositions [2]` | `BYDAY=TU;BYSETPOS=2` | same dates |
| last Friday | `weekNumber: -1` | `BYDAY=-1FR` | 11-27, 12-25 ... |
| 1st and 3rd Monday | two `EKRecurrenceDayOfWeek` with weekNumber 1 and 3 | `BYDAY=1MO,3MO` | 12-07, 12-21, 1-04 ... |
| last weekday | MO-FR + `setPositions [-1]` | `BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1` | 11-30, 12-31, 1-29 ... |
| first weekend day | SA,SU + `setPositions [1]` | `BYDAY=SA,SU;BYSETPOS=1` | 12-05, 1-02 ... |
| monthly interval 3 day 10 | interval 3 | `INTERVAL=3;BYMONTHDAY=10` | 2-10, 5-10 ... |
| yearly | plain | `FREQ=YEARLY;INTERVAL=1` | 2027-11-16 |
| yearly March+Sept day 10 | `monthsOfTheYear [3,9]`, `daysOfTheMonth [10]` | `BYMONTH=3,9;BYMONTHDAY=10` | 3-10, 9-10 |
| yearly 2nd Thursday of Nov | `monthsOfTheYear [11]`, `TH weekNumber 2` | `BYMONTH=11;BYDAY=2TH` | 2027-11-11 |
| count 5 | `EKRecurrenceEnd(occurrenceCount: 5)` | `COUNT=5` | 5 occurrences |
| until, `startOfDay(D+5)` (timed event) | `EKRecurrenceEnd(end:)` | `UNTIL=20261120T050000Z` | **4** (D+5 09:00 excluded) |
| until, D+5 23:59:59 (timed event) | `EKRecurrenceEnd(end:)` | `UNTIL=20261121T045959Z` | **5** (D+5 included) |
| until `startOfDay(D+17)` (all-day weekly event) | `EKRecurrenceEnd(end:)` | rewritten to `UNTIL=20261202T235959Z` | D+17 **included** |

Other observations:

- **DTSTART is always an occurrence, even when it does not match the rule** (monthly day 15 starting
  Mon 11-16 lists 11-16 first; interval-2 TU,TH lists Monday 11-16). Same as RFC 5545 and Stark's ICS.
- EventKit accepts and keeps **two rules on one event** (read back count 2).
- Reminders accept every shape above (read back identical; whether Apple's Reminders app displays the
  positional ones nicely was not checked).

Unsupported: **none** of Stark's `RecurrenceRule` shapes (`byDay`, `byMonthDay` incl. -1,
`byPositionalDay` with `.weekday`/`.anyDay`(last)/`.weekdayOnly`/`.weekendDay`, `byMonth`, `count`,
`until`, `interval`) failed to save or changed on read-back. The only limits are on the descriptor
side, not EventKit's:

- A positional list with *different weekdays at different positions* (e.g. "1st Monday and 3rd
  Wednesday") needs per-day `weekNumber`; it cannot be written as one `weekdays` + one
  `setPositions` list (that would mean "every listed weekday at every listed position"). Task 3's
  descriptor must either carry a week number per weekday or throw `unrepresentable` for such mixed
  lists. A single weekday at one position ("2nd Tuesday", "last Friday") is fine either way; same
  weekday at several positions ("1st and 3rd Monday") maps to `weekdays [MO]` + `setPositions [1,3]`.
- Inbound (Apple -> Stark), `hasUnrepresentableRepeat` should be true for: more than one rule,
  `weeksOfTheYear`/`daysOfTheYear`, `setPositions` combined with `daysOfTheMonth`, frequencies with
  both `daysOfTheMonth` and `daysOfTheWeek`, and anything else `RRuleCodec` cannot express.

**Decisions for Task 3 / Task 6:**

- Last day of month: write `daysOfTheMonth [-1]` (matches Stark's `RRuleCodec` `BYMONTHDAY=-1`);
  read both `[-1]` and "all 7 days + setPositions [-1]" as last day.
- Positional weekday: write `EKRecurrenceDayOfWeek(day, weekNumber: n)` (matches Stark's `BYDAY=2TU`);
  read both forms. Weekday-only / weekend-day positions: weekday set + `setPositions [n]`.
- Until (Stark's is date-only and inclusive): for timed items write `EKRecurrenceEnd(end:)` at
  **23:59:59 local of the until day**; `startOfDay` loses the last day. For all-day events EventKit
  rewrites the end to 23:59:59Z of that date itself, so start-of-day is inclusive there, but using
  end-of-day for both is simpler and also correct. On read, take the end date's calendar day (local
  for timed, UTC for all-day, because of that rewrite).
- Monthly day 29-31 skips short months in EventKit (RFC behaviour). Stark's picker already offers
  "Last day of the month" (`byMonthDay -1`) for the clamp case; whether Stark's own
  `OccurrenceExpander` skips or clamps day 31 was not checked here. After the move, Apple's skip
  semantics are the truth.
- New recurring items: set the start/due to the first matching occurrence, or the item gets an extra
  occurrence on a non-matching day.

## (e) Calendars, writability, invitee-only events

**Calls:** `calendars(for: .event)`, `calendars(for: .reminder)`, `sources`,
`defaultCalendarForNewEvents`, `defaultCalendarForNewReminders()`.

**Observed (fresh simulator store, before and after the scratch ones were added):**

| Entity | Title | `type` | `allowsContentModifications` | `isImmutable` | `isSubscribed` | Source (`sourceType`) |
|---|---|---|---|---|---|---|
| event | Calendar (default) | 0 local | true | false | false | Default (0 local) |
| event | Birthdays | 4 birthday | **false** | true | false | Other (5 birthdays) |
| event | US Holidays | 3 subscription | **false** | false | true | Subscribed Calendars (4 subscribed) |
| event | Spike Calendar (created) | 0 local | true | false | false | Default (0 local) |
| reminder | Reminders (default) | 0 local | true | false | false | Default (0 local) |
| reminder | Spike List (created) | 0 local | true | false | false | Default (0 local) |

Creating a calendar/list on the local source with `EKCalendar(for:eventStore:)`, `source =` the
default calendar's source and `saveCalendar(_:commit: true)` works on the simulator.

**Invitee-only events: could not be tested on the simulator.** `EKEvent.attendees`/`organizer` are
read-only and `EKParticipant` has no public initializer. A private-API attempt (KVC on `EKAttendee`,
`addAttendee:`) failed at save with `EKErrorDomain Code=41 "Attendees cannot be changed."`. The
simulator has no CalDAV/Exchange account, so no event with an organizer other than the user exists.
Whether such an event reports `organizer.isCurrentUser == false`, `attendees`, and
`allowsContentModifications` on its calendar must be checked read-only on the device (the owner's
real calendars contain invitations); this belongs on Task 10's device checklist.

**Decision for Task 6:** `isWritable = calendar.allowsContentModifications`; Birthdays and
subscribed calendars are false and must be excluded from the default-destination pickers. Implement
`isInviteeOnly` as `event.hasAttendees && event.organizer?.isCurrentUser == false` (unverified, see
above), and keep the UI tolerant if the device shows otherwise.

## (f) `EKEventStoreChanged` notifications

**Calls:** `NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main)`
on the writer store and on a second store; each trial waited 4 s; trials repeated (two full runs).

**Observed:**

| Write | Writer store | Other store |
|---|---|---|
| one event `save(commit: true)` (trials 1-3) | 1 | 1 |
| one event `save(commit: true)`, the first write ~5 s after a burst (setup) | **0** (both runs) | **0** |
| 3 event saves `commit: false` before `commit()` | 0 | - |
| ... then one `commit()` | 1 | 1 |
| 3 event saves each `commit: true`, back to back | 1 (coalesced) | 1 |
| reminder save + complete (2 commits back to back) | 2 | 2 |
| mixed batch (1 event + 2 reminders, one `commit()`) | 1 | 1 |
| ~40 commits with no run-loop turn in between | 25 delivered later | - |

- The writer's own store is notified about its own commits (no echo suppression), on the main queue,
  usually within a second.
- Count is **not** one per save: commits close together are coalesced, and a commit can produce **no
  notification at all** (reproduced twice for the first write after a burst of setup writes).
- Nothing is posted for `save(commit: false)` until `commit()`.

**Decision for Task 5/6:** do not rely on the notification to show a Stark write. After a successful
write (or batch commit) the repository/router triggers its own reload; notifications only trigger a
coalesced reload through the existing reload gate (one reload in flight, stale results dropped).
Batches use `save(commit: false)` x N + one `commit()` (one notification, one reload).

## Contradictions with the spec

None that affect the plan's shape: completing a recurring reminder **advances** the series as the
spec requires, and series edits/deletes behave as the spec's "Editing a series" assumes.

One factual correction: "What changes for the owner" says Apple keeps only "the completion date of
the last one". In fact every completion leaves a separate completed reminder (old due date,
`completionDate`), so per-occurrence completion history does exist in Apple's data. The controller
decides whether to use it (it is in Stark's favour; nothing in the plan breaks).

## Verified on the simulator only; recheck on the device (Task 10)

- Recurring reminder completion: daily, weekly, monthly, date-only, COUNT end, UNTIL end (copy +
  advanced master, identifiers kept, next due = first occurrence after old due and now), on an
  iCloud (CalDAV) reminders list, not just the local source; also that Apple's Reminders app shows
  the same result after Stark completes one.
- The same for a reminder whose time today is still ahead (today's occurrence stays open).
- Event series edit/delete on an iCloud calendar (master from `event(withIdentifier:)`, detached
  occurrences surviving title/time edits, split when saving a mid occurrence).
- Identifier shapes on iCloud: `calendarItemIdentifier` vs external identifier for reminders and
  events, `/RID=` for detached occurrences.
- Recurrence round trip on iCloud calendars and lists (especially positional and BYSETPOS rules on
  reminders, and how Apple's apps display them).
- `allowsContentModifications`, `type` and `sourceType` for the owner's real calendars and lists
  (iCloud, Exchange/Google if present, shared and subscribed calendars).
- Invitee-only events: `organizer`, `organizer.isCurrentUser`, `attendees`, `isDetached`, and whether
  saving one fails (read-only check, do not modify the owner's invitations).
- `EKEventStoreChanged` counts and the missing-notification case with iCloud sync traffic.
