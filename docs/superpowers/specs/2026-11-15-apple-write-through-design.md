# Apple write-through and retiring the local store: design

Date: 2026-11-15. Status: draft, awaiting approval. Pieces 2 and 3 of 4 from
`2026-11-15-apple-overlay-design.md`, merged by decision on 2026-11-15 ("everything from now goes to
Apple; we are deprecating the local file store with ics"). Piece 1 (read-only overlay) shipped as
TestFlight 2.0.23 (build 25) and works on the owner's real calendar and reminders. Piece 4 (Mac
command-line tool for Claude Code) stays last.

## Intent and why

Apple Calendar and Reminders are the one source of truth; Stark is a better view of them (Fantastical
model). After piece 1 Stark reads Apple's data but still creates and edits only its own `.ics` items,
so the owner has two worlds. This piece makes Apple the only world: Stark creates, completes, edits
and deletes real Apple events and reminders, existing local items are moved into Apple once, and the
`.ics` store is removed. Claude Code (the `stark://` bridge now, the Mac tool later) then writes to the
same data the owner's other devices see.

Facts decided in conversation (2026-11-15): the owner is the only user of the native build (no
first-run migration flow for other people); new items go to Apple; the plan is a one-time import of
existing items with a preview, the `.ics` files left on the phone as a backup; approach A below.

## Approaches considered

- **A (chosen): replace the store behind one interface.** Views call a single `ItemRepository`
  (add, update, delete, complete, uncomplete, skip-occurrence, outcome, plans). Pieces of the app keep
  working on plain `Event`/`Reminder`/`AgendaItem` values. During the transition there are two
  implementations (local `.ics`, Apple) and a router by item origin; at the end only Apple remains.
- B: two stores side by side permanently. Rejected: two copies, against "Apple is the source".
- C: rewrite the agenda layer to read only Apple data in one step. Rejected: touches every screen at
  once, nothing shippable until done.

## Goals

- New items (Add screen, Claude Code bridge) are created in Apple, in a default calendar (events) and
  list (reminders) chosen in Settings (initial value: EventKit's defaults).
- Apple items can be completed/uncompleted, edited and deleted from Stark with the same screens Stark
  items use today; the read-only gate from piece 1 is lifted for items Stark can now write.
- One-time import of existing local items into Apple with a preview, idempotent (running it twice
  adds nothing), reversible only by the owner deleting the items in Apple's apps (the preview says so).
- The `.ics` store, parser/serializer, `PlannerFile`, month-file loading, `OccurrenceExpander` use for
  agenda and the local-load window logic are deleted once nothing uses them.
- A small local sidecar keeps what Apple cannot hold, keyed by Apple item identifier: planner/timeboxing
  blocks and event attended/skipped outcomes.
- Apple access is required: denied or not asked shows a clear "Stark needs access" screen with a
  button to iOS Settings, never an empty calendar.

## Non-goals

- Mac command-line tool (piece 4). Calendar sets, natural-language quick add, widgets, other ideas from
  GitHub issue #120. Shared calendars' permission edge cases beyond showing an error.
- Preserving Stark-only recurring-reminder semantics (see "What changes").
- Undo of a batch import. Syncing Stark's sidecar between devices.

## Anti-goals

- Silently losing the owner's existing items or planner blocks during the import.
- Two copies of any item after the import (Stark's `.ics` copy must stop being displayed once
  imported).
- Saving to the wrong calendar/list, or to a read-only calendar, without a visible error.
- Persisting EventKit identifiers or absolute paths anywhere except the sidecar (identifiers are
  needed there; document it).
- Any network call; any permission prompt at launch before the owner has seen what it is for (the
  access screen explains first).

## What changes for the owner (stated so nothing is a surprise)

- Recurring reminders behave as in Apple's Reminders app: completing one moves it to its next
  occurrence. "Skip this occurrence" is removed for reminders. Completion history for recurring
  reminders is no longer recorded by Stark (Apple keeps the completion date of the last one; see the
  correction below). The
  overdue carry of several misses becomes Apple's single open occurrence (already how the overlay shows
  it). The Weekly Review and the history views show what Apple's data supports.
- **Correction (2026-11-15, after the Task 1 spikes, `2026-11-15-eventkit-write-spikes.md` (a)):**
  "Apple keeps the completion date of the last one" is wrong. Completing a repeating `EKReminder`
  leaves a separate completed copy (its own identifier, due date and completion date) for every
  completion while the open reminder moves to its next date, so Apple keeps a completed copy per
  completion. Stark still keeps no history of its own for repeating reminders; Weekly Review counts
  those copies like completed one-offs.
- Converting an event to a reminder and back becomes "create the other, delete this one".
- Events: "skip one occurrence" maps to deleting that occurrence (span this event); attended/skipped
  outcomes stay in the sidecar.
- Editing or deleting a recurring item changes the whole series (as Stark does today); deleting one
  occurrence of an event is available via skip.

## Design

**Interface.** `ItemRepository` (StarkKit, protocol, `Sendable`, async) with operations mirroring the
`PlannerStore` public methods the views use today: add event/reminder, update, delete, complete,
uncomplete, skip event occurrence, set event outcome, plans(on:)/replacePlans, import batch. A
`FakeItemRepository` for tests. `AppleItemRepository` (app target, the only code besides
`EventKitProvider` that imports EventKit) implements it with EKEventStore saves/removals; it runs
EventKit writes off the main actor and publishes the changed range back to the overlay model so the
agenda refreshes (EventKit also posts `EKEventStoreChanged`, which the model already observes).

**Mapping.** Pure Kit functions with tests, both directions: `RecurrenceRule` <-> `EKRecurrenceRule`
(frequency, interval, weekdays, day of month incl. last day and positional days, until/count,
exception dates become single-occurrence deletions on events); priority 1-9 <-> `EKReminder.priority`;
all-day and date-only handling (the inclusive-last-day rule from piece 1); alarms are not created
(Stark has none today). A mapping that cannot be represented in EventKit surfaces an error to the
caller; it never silently drops a field.

**Editing a series.** EventKit fetches return occurrences. To change a whole series the repository
resolves the master via `event(withIdentifier:)` and saves with the span for the future from the first
occurrence; deleting one occurrence uses span "this event". Reminders are saved directly.

**Recurring reminder completion.** Behaviour of `isCompleted = true` on a recurring `EKReminder` via
EventKit (does the series advance to its next occurrence the way Apple's app does, or does it end?)
must be established first by a short spike on the simulator and the device before building on it
(first task of the plan). If EventKit does not advance the series, the repository does it explicitly
(complete the occurrence and move the due date to the next occurrence) and the spec's "What changes"
stays true.

**Local sidecar.** One JSON file (atomic write, Library, not Documents) holding plan blocks and event
outcomes keyed by Apple item identifier plus occurrence date, and the import ledger (Stark UUID ->
Apple identifier, so the import is idempotent and plan blocks/outcomes can be remapped). Orphans (item
deleted in Apple) are dropped lazily. Chosen over SQLite because it holds a few hundred small records;
the owner's usual SQLite default is for primary data, which now lives in Apple (my call).

**Claude Code bridge.** The signed `stark://add` batch is verified exactly as today; accepted items go to
`ItemRepository.addEvent/addReminder` (Apple). "Already added" idempotency uses the import ledger
(batch id -> created identifiers) instead of scanning loaded months. The `stark-claude today` command
reads a temporary copy of the Documents folder today; once the store is gone it needs a new source (the
Mac tool in piece 4 replaces it); until then `today` is documented as unavailable (Done when says what
is shown).

**Migration (one-time import).** Settings > "Import Stark's own items": reads the `.ics` months,
shows a preview (counts of events, open reminders, completed one-off reminders, recurring masters,
plan blocks; the destination calendar and list; items that cannot be represented, listed by title),
and on confirm creates them in Apple, records the ledger, remaps plan blocks and outcomes, and marks
the local store as imported. Recurring completion copies (history) are not imported. The `.ics` files
are never modified or deleted by the app; the sidecar notes "imported on <date>". After the import
the local items stop being displayed (the ledger hides them), so there are never two copies on screen.

**Removal.** After the import is confirmed on the owner's device, a final task deletes the `.ics`
store code (`PlannerFile`, `ICS/*`, month loading, `PlannerStore` local paths, the local branch of the
router, `OccurrenceExpander` and `buildAgendaItems` if nothing else uses them, and the read-only gate)
with their tests, and updates privacy/FAQ copy, CLAUDE.md and the feature notes. The overlay
on/off switch goes away (access is required); the per-calendar selection stays.

## Constraints

- TDD, Swift Testing in StarkKit with `FakeItemRepository`/a fake store seam; EventKit calls behind
  the protocol; one `EKEventStore`; writes off the main actor; deployment target 17.0.
- Phases ship separately as TestFlight builds (the owner approved TestFlight for testing):
  P1 write path (Add, complete, edit, delete go to Apple; local items still shown and editable until
  imported), P2 import, P3 removal. The owner checks each on the phone before the next starts.
- **Phase 2 built (2026-11-17)**: the import is implemented as designed in `2026-11-17-apple-import-phase2-design.md` (see the "Apple import phase 2 log" in `CLAUDE.md`); awaiting the owner's run on real data. Phase 3 is not started.
- Never delete the owner's `.ics` files; the import never runs without the preview and a confirm.

## Done when (whole design; each phase has its own list in the plan)

- `cd ios && swift test` passes including mapping round-trip tests (recurrence, priority, all-day, date
  only, DST), router tests, import idempotency, sidecar remapping, bridge idempotency via the ledger.
- Simulator run with screenshots using a seeded simulator Calendar/Reminders store (writes work on
  the simulator): add event and reminder from Stark and see them in Apple's apps, complete, edit,
  delete a series, skip an occurrence, import preview and result, access-denied screen.
- On the iPhone: items created in Stark appear in Apple Calendar/Reminders and on another device;
  completing a recurring reminder behaves as described; the import preview matches the real counts
  and a second run adds nothing; a bridge `/stark` batch lands in Apple; plan blocks survive the import.
- Copy updated (privacy: Stark now writes to Calendar and Reminders; FAQ), `make test-fast` passes.
- NOT part of done: Mac tool, calendar sets, widgets; deleting the owner's `.ics` files.

## Risks and open items for the builder

- Recurring reminder completion semantics and recurrence-rule representability (spike first).
- Reminders in EventKit can have a different default list per account; the default list/calendar must
  be writable (`allowsContentModifications`), else show a visible error and let Settings change it.
- Event time zones: events created in Stark use the device time zone; floating all-day events.
- Performance: a write triggers `EKEventStoreChanged` and a reload; coalesce so the agenda does not
  flicker (the existing reload gate already drops stale results).
- `stark-claude today` has no source after P3 until piece 4 (documented, accepted).

## Left to the builder

Protocol method names and file layout, sidecar file name and schema version, how the router chooses
an implementation during the transition (by item id prefix or origin field), the exact preview and
access-screen layouts within the Braun/Bauhaus theme, error banner wording, task split.

## Decisions after the builder check (2026-11-15)

Owner decisions:
1. **Recurring reminders do what Apple does.** Completing one moves it to its next date; Stark keeps no
   completion history for repeating reminders and no sidecar completion log. The old completed copies
   (`seriesID` records) are not imported. Planner day history treats a plan block whose occurrence the
   series has already moved past as done (derived from the series' current due date), never as missed.
   The completion-history sheet is removed for repeating reminders; Weekly Review shows one-off
   completions and what is still open.
2. **Planner, Weekly Review, tag autocomplete and convert work on Apple items from phase 1**, using the
   same calendar/list selection (hide a list such as groceries to keep it out of the planner tray).
   Phase 1 is therefore larger than first drawn.
3. **Undated Apple reminders** appear in Search and in a "No date" pane of the planner tray, not in the
   agenda. (Owner: "go with your pick".)

My calls (the owner can override):
4. `stark-claude today` prints "unavailable until the Mac tool" from phase 1 (it reads the old files
   and would silently omit Apple items); step 4 of `.claude/commands/stark.md` is skipped until piece 4.
5. Editing an Apple item loads the real EventKit item when the edit sheet opens and writes back only
   the fields the user changed (the overlay's stand-in values carry no recurrence rule, time zone or
   write permission and must never be saved back whole). A time change on a series moves only the
   time of day. A repeat rule Stark cannot represent is shown read-only. Edit and delete are hidden for
   calendars that cannot be written to and for events where the owner is an invitee.
6. Bridge idempotency: the ledger maps each bridge item id (derived from content) to its Apple
   identifier and skips ids already recorded (an item deleted in Apple stays deleted). `ClaudeBridge.handle`
   becomes async; a batch saves without commit and commits once, rolling back on failure.
7. Import of repeating reminders: the due date is set to the occurrence the agenda shows today (the
   oldest unresolved miss inside the 90-day lookback, else the next one), and a fixed occurrence count is
   reduced by the occurrences already used. A repeating event's skip dates become deleted occurrences.
8. The import writes its ledger entry right after each successful save (a crash cannot cause
   duplicates on a second run). Items that cannot be represented stay local and visible with a "not
   imported" mark, and phase 3 cannot start while any remain.
9. Sidecar keys store the event/calendar-item identifier plus the external identifier; on a miss the
   sidecar tries to re-match on the external identifier and never drops an orphan automatically.
10. Search and tag autocomplete read events within two years either side of today and all reminders.
11. Phase 1 forces the overlay on and always shows the default calendar and list (items created in
    Stark must never vanish from view).
12. Spikes before building on them (first tasks of the plan): completing a recurring `EKReminder`;
    whether saving a series from its first occurrence wipes occurrences changed individually in Apple
    Calendar; recurrence-rule representability.
