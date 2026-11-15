# Apple Calendar and Reminders overlay (read-only): design

Date: 2026-11-15. Status: draft, awaiting approval. This is piece 1 of 4 (see "Roadmap").

## Intent and why

Eladio likes Fantastical because it is a better view of the Apple Calendar and Reminders he already
has, synced everywhere by iCloud. Stark instead keeps its own `.ics` store, so it is never the
place his real day lives, and Claude Code cannot reach it except through a one-way URL bridge.

Decided 2026-11-15: **Apple Calendar and Reminders become the one source of truth; Stark becomes a
better view of them.** This supersedes "no EventKit" in `2026-09-17-stark-native-rewrite-design.md`.
The move is incremental (approach C below). This document covers only piece 1: show Apple's data
in Stark, read-only, next to Stark's own data. The hypothesis it tests: with his real calendar and
reminders inside it, Stark feels like Fantastical enough to justify pieces 2 and 3.

## Roadmap (each piece gets its own design and plan)

1. **Read-only overlay (this document).**
2. Write-through: add, edit, complete go to EventKit.
3. Retire the local `.ics` store; planner blocks stay local, keyed by EventKit identifier.
4. Mac command-line tool so Claude Code reads and writes Apple Calendar/Reminders (replaces the
   URL bridge). Last, by decision.

Fantastical ideas for later are in GitHub issue #120.

## Approaches considered

- A. Swap `PlannerStore`'s storage to EventKit in one go. Cleanest end state; nothing ships until
  all of it works; loses Stark's recurring-reminder semantics at once.
- B. Keep `.ics` and two-way sync with EventKit. Rejected: two copies means identity mapping and
  conflict handling, against "Apple is the source of truth".
- **C. Steps (chosen by Eladio):** overlay, then write-through, then retire local store.

## Goals

- Apple Calendar events and Apple Reminders appear in the agenda, the month grid density and
  Search, alongside Stark's own items.
- Choose which calendars and reminder lists show (all on by default).
- Each Apple row carries a small marker (calendar colour dot and calendar/list name).
- Nothing about Stark's own data, storage, planner or bridge changes.

## Non-goals (this piece)

- Any write to EventKit (no add, edit, complete, skip, delete on Apple items).
- Planner/timeboxing trays, Weekly Review and the Claude Code bridge do not include Apple items.
- De-duplicating against Stark's own items (see risks), calendar sets, Focus filters.
- Mac Catalyst runtime verification of the new screen.

## Anti-goals

- Apple items that look editable but silently do nothing.
- Stark's recurrence engine re-expanding Apple recurrences (EventKit's expansion is authoritative).
- Storing Apple items in Stark's files, or EventKit identifiers/paths in `.ics`.
- Asking for permission at launch.

## Design

**Access.** `NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription` in
the app's Info.plist (iOS 17 deployment target; full access is required to read). The request is
made when the user turns the overlay on in Settings > "Apple Calendar and Reminders", never at
launch. States handled and shown: not asked, granted, denied/restricted (with a row that opens
iOS Settings), and write-only (treated as denied). The overlay is off by default.

**Seam.** StarkKit (testable on the Mac, no EventKit import) gets:
- `AppleSource` (calendar id, calendar title, colour hex, kind event/reminder) and an optional
  `appleSource` on `AgendaItem` (nil for Stark's own rows). Not on `Event`/`Reminder`, which are
  persisted.
- `AppleItemProvider` protocol: `items(in: ClosedRange<Date>, calendars: Set<String>) async throws
  -> (events: [AppleCalendarEvent], reminders: [AppleReminder])` with plain value types.
- `mergeAppleItems(_ stark: [AgendaItem], apple: ..., today:) -> [AgendaItem]`: builds one
  `AgendaItem` per concrete Apple occurrence and re-sorts with the existing `sortAgendaItems`.
  Apple events are already expanded by EventKit, so they enter with `recurrence == nil` and are
  never passed through `OccurrenceExpander`. Row id is `apple-<eventIdentifier>-<start timestamp>`
  (reminders: `calendarItemIdentifier`), so it can never collide with a Stark UUID row.
- App layer only: `EventKitProvider` (the one file that imports EventKit; one shared `EKEventStore`,
  fetches with `predicateForEvents`, `predicateForIncompleteReminders` and
  `predicateForCompletedReminders`), and a `AppleOverlayModel` (`@MainActor @Observable`) holding
  access state, selected calendar ids (UserDefaults, ids only) and the current result. It reloads
  on `EKEventStoreChanged`, on foreground, and when the agenda window moves.

**Window.** The overlay fetches the same display range and the same load range as the agenda
(`AgendaWindow`), so "anything that moves the window loads first" holds for Apple items too.

**Reminders.** EventKit gives one open occurrence per recurring reminder (the due date advances
when completed in Apple's app). So an Apple reminder is one row at its due date, overdue-pinned by
the existing day-granular rule (`OverdueLabel` text works). Undated reminders are not shown in
this piece (decision for the builder to confirm: they have no day to sit on). Completed Apple
reminders show on their due date like Stark's completed ones.

**Rows and detail.** Apple rows render with the existing row visuals plus the source marker. The
checkbox strip is disabled (visibly inert), swipe actions, edit, plan, convert and skip are hidden.
Tapping opens a read-only detail (title, time, notes, location, URL, calendar name) with an
"Open in Calendar" / "Open in Reminders" link (`calshow:` / `x-apple-reminderkit://`, builder to
verify these work on a device).

**Month grid and Search.** `AgendaDensity` counts Apple items (two 1 pt lines rule unchanged);
`SearchResults` includes them, read-only, marked.

**Settings.** New "Apple Calendar and Reminders" screen: on/off, access state, a list of
calendars and lists grouped by account with a toggle each.

**Copy.** In-app FAQ, web FAQ and web privacy text updated: Stark reads (does not copy or send)
calendar and reminder data on the device when the user turns the overlay on; no network call is
added. `PrivacyInfo.xcprivacy` checked. `TestPrivacyDatedAndMentionsData` updated.

## Constraints

- TDD, Swift Testing in StarkKit; fake `AppleItemProvider` in tests. XcodeGen: run `xcodegen
  generate` if `project.yml` changes (this project uses a committed `Stark.xcodeproj`; follow its
  existing flow, builder to check).
- Only one `EKEventStore`; no EventKit calls on the main actor beyond access requests.
- Deploy target stays 17.0.

## Done when

- `cd ios && swift test` passes, including new tests for `mergeAppleItems` (ordering, ids never
  colliding, overdue pin for an Apple reminder, completed reminder, all-day and multi-day event,
  deselected calendar excluded) and density/search inclusion.
- Generic iOS build and Mac Catalyst build compile.
- Simulator run with idb screenshots: access prompt flow, calendars toggled, Apple and Stark rows
  mixed in the agenda, month dots, a search hit, read-only detail. (Simulator calendars seeded
  with made-up items.)
- On the iPhone (`ios/App/deploy.sh`): the real calendar and reminders show; deselecting a calendar
  hides it; an edit made in Apple Calendar appears in Stark within a foreground. Recorded
  separately as "confirmed on device".
- NOT part of done: any write to Apple data, planner/review/bridge inclusion, ship to TestFlight
  (asks first).

## Risks and open items for the builder

- Duplicates: items he already created in Stark appear twice if the same thing exists in Apple.
  Accepted for this piece; the overlay is off by default and per-calendar.
- Stark's overdue/carry rules and Apple's one-open-occurrence behaviour differ; only the overdue
  pin is applied to Apple reminders.
- Large calendars (thousands of events): fetch is bounded by the window; measure on device.
- Time zones and floating all-day events: use EventKit's own start/end and `isAllDay`; test a
  DST day and a timezone-shifted all-day event.
- Calendar subscriptions, birthdays calendar and holiday calendars are included if selected
  (default: all on); revisit if noisy.

## Left to the builder

File layout inside `ios/`, naming, the exact marker design within the Braun/Bauhaus theme
(hard edges, one accent, no hardcoded hex; calendar colours are data, shown only as the small dot),
test fixtures, and how the plan is split into tasks.

## Calls made after the builder check (2026-11-15, mine; Eladio to confirm)

1. **Representation.** `mergeAppleItems` maps each Apple occurrence to a synthetic, non-persisted
   `Event`/`Reminder` (`id` is a `String`, so `apple-...` ids fit) wrapped in an `AgendaItem` with
   `appleSource` set. No new `Kind` case (it would touch every exhaustive switch). Synthetic values are
   never passed to `PlannerStore`.
2. **Read-only enforcement.** One gate, `appleSource != nil`, at every entry point that acts on a row:
   row tap, checkbox strip, swipe/context actions, Search tap-through, detail and edit sheets. A test
   per entry point asserts an Apple row cannot reach `PlannerStore`. Making Apple items
   unrepresentable in the edit path is not worth the cost for a read-only piece.
3. **Overdue.** EventKit already expands recurrences, so carry/fold/hide-later rules do not apply to
   Apple items. An open Apple reminder is overdue-pinned only within the same 90-day lookback as Stark's
   (older ones are not shown), so a two-year-old open reminder does not sit on today forever.
4. **Reminder times.** A due date without an hour is shown as date-only (like Stark's date-only
   reminders). **Undated reminders are not shown in this piece**; revisit in piece 2 (they have no
   day to sit on and would need a new "no date" section).
5. **Fetch ranges.** Events use the display range only. Incomplete reminders use the load range
   (display + 90-day lookback). Event fetches are chunked (EventKit limits long ranges).
6. **Multi-day and all-day.** One row per day like Stark's, using the existing span logic. The known
   "ends exactly at midnight" bug is not copied: Apple events ending at midnight stop on the
   previous day.
7. **Mac Catalyst.** Add the calendar and reminders entitlements the Catalyst target needs; this
   piece only requires that it compiles (no runtime check).
8. **Loading.** `AppleOverlayModel` is created at the root and reloads from the same hook as
   `store.loadMonths(covering:)`, so the window never shows a range before its Apple data is
   fetched (stale rows are kept until the new fetch lands).
9. **Selection.** Stored as a set of excluded calendar ids (nil/empty = all on, so new calendars
   appear on their own); ids that no longer exist are ignored.
10. **"Open in" links.** If neither `calshow:` nor the Reminders scheme works on the device, omit
    the link.
