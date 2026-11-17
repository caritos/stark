# Apple import, phase 2: move Stark's own items into Apple

Date: 2026-11-17. Parent spec: `2026-11-15-apple-write-through-design.md` (decisions 1, 7, 8, 9 and the
"Migration" paragraph still stand; this document makes them concrete). Phase 1 shipped as v2.0.24.

## Intent

The owner is the only user of the native build. Items created before 2026-11-15 still live in Stark's
own `.ics` files (`recurring.ics`, `YYYY-MM.ics`) and are shown next to Apple's. Phase 2 copies them into
Apple Calendar and Reminders once, so Apple is the single source of truth, the duplicates on screen go
away, and phase 3 can delete the local store. Why now: every later piece (phase 3, the Mac tool, the
Fantastical-parity work in #120) assumes one store.

## Goals

- Settings > "Import Stark's own items": scan, preview, confirm, import.
- Preview shows: counts (events, open reminders, completed one-off reminders, recurring masters, plan
  blocks, attended/skipped marks), the destination calendar and list (the Settings defaults), items that
  cannot be represented (listed by title), and a read-only "N look already in Apple" count (title plus
  start/due time match against Apple data already loaded for Search). The count never blocks or skips.
- Idempotent: a second run adds nothing. A ledger entry is written right after each successful save, so
  a crash or kill mid-run cannot cause duplicates on the next run.
- Imported local items stop being displayed (hidden by the ledger), so no item shows twice.
- Plan blocks and attended/skipped marks follow their item to its new Apple identifier.
- Nothing is lost: items that cannot be represented stay local, visible, with a "not imported" mark.

## Non-goals

- Per-item opt-out or automatic duplicate skipping (rejected: a wrong fuzzy match would silently drop a
  real item). No undo of an import (the preview says to delete in Apple's apps to reverse).
- Importing completion history: completed copies of repeating reminders (`seriesID` records) are not
  imported (parent decision 1). Completed one-off reminders ARE imported, as completed.
- Deleting or editing the `.ics` files. Phase 3 removes the code; the files stay on the phone as a backup.
- Syncing the ledger between devices (the sidecar is per device, as before).

## Anti-goals

- Two copies of an item on screen after the import. Silent loss of an item, plan block or mark.
- Writing to a read-only calendar, or into a calendar other than the shown destination, without an error.

## Constraints

- StarkKit holds all logic (`swift test`, Swift Testing, fakes behind `ItemRepository`); the app target
  gets a thin screen. TDD; migration tests use a real previous-version sidecar file.
- Sidecar is the only place Apple identifiers are stored (parent spec). Never persist absolute paths.
- Access to Calendar and Reminders is already required, so the import never runs without it.
- A device Release build and the full suite on the merged result before shipping; TestFlight only.

## Approaches considered

- **A (chosen): preview with an informational duplicate count, confirm, import.** Matches the parent
  spec; the count answers "did some of this already reach Apple?" without adding state.
- B: A plus per-item toggles, probable duplicates off by default. Rejected: bigger screen and state for a
  one-time action by one person.
- C: A plus silent skipping of probable duplicates. Rejected: loses items on a wrong match.

## Design

**Kit, new `Import/` folder.**
- `ImportPlanner` (pure): input = all local events and reminders, local plan blocks, the Apple items
  loaded for matching, the default destinations. Output `ImportPlan`: ordered `ImportStep`s (one per
  item: local id, `NewEvent`/`NewReminder`, kind, linked plan blocks and outcomes), `unrepresentable`
  (title plus reason), `skippedHistory` count, `probableDuplicates` count, and the preview counts.
  Conversion reuses `RecurrenceDescriptor` and `ItemRouter`'s existing `NewEvent`/`NewReminder`
  builders. Rules: an item already in the import ledger is omitted; a repeating reminder's due date is
  the occurrence the agenda shows today (oldest unresolved miss inside the 90-day lookback, else the
  next; parent decision 7) and a fixed `COUNT` is reduced by occurrences already used; a repeating event's
  exception dates become deleted occurrences after creation; a repeat Apple cannot hold
  (`RecurrenceDescriptor` throws) makes the item unrepresentable; items on read-only destinations make
  the whole run refuse before starting.
- `ImportRunner` (actor): executes steps sequentially through `ItemRepository` (not `addBatch`, because
  the ledger must be written per item), then writes that item's import-ledger entry via the sidecar,
  remaps its plan blocks and outcomes (`ItemSidecar.remap`), then continues. A failed step is recorded
  and the run continues with the next (a failure never leaves a half-ledgered item); the result lists
  imported, failed (with message) and unrepresentable. Cancellable between steps. Progress is published
  as a count for the UI.
- `ItemSidecar`: add `importLedger: [String: String]` (local id -> Apple identifier) and an
  `importedAt` date; bump `SidecarData.currentVersion` to 2 with a migration that decodes version 1 files
  (missing keys default to empty). Test: load a real version-1 file, upgrade, round-trip, keep every
  existing field.
- Hiding: the local-store read path used by the agenda, search, planner tray, density and weekly review
  excludes ids present in `importLedger`, applied in one place (a filter at the `ItemRouter` / store
  read boundary, not in each view). Items listed unrepresentable are not in the ledger and stay visible,
  with a "not imported" mark on their row and detail.
- Bridge ids: bridge items added locally before 2026-11-15 get their bridge-ledger entry written with the
  same save, so re-sending an old file adds nothing (this is the case the parent spec flagged).

**App.** `ImportStarkItemsView` (Settings row visible while local items exist and not all are imported):
scan on open, preview, "Import N items" button, progress, result with any failures and a "Done" that
leaves the list of unrepresentable items readable. A second tap after a partial failure retries only what
is not ledgered. Copy states plainly that the `.ics` files are kept and that undoing means deleting in
Apple's apps. No analytics, no network.

**Docs.** Update the in-app FAQ, web FAQ and privacy page if wording changes (the import adds nothing new
that leaves the phone), `docs/ios-feature-notes.md` and the CLAUDE.md log (Done / Not yet verified on
device / Deferred), and the phase 3 prerequisite: removal cannot start while any "not imported" item remains.

## Done when

- `cd ios && swift test` green; new suites cover: planner conversion for every item kind (event, all-day,
  multi-day, repeating with exceptions, one-off and repeating reminders incl. overdue carry and COUNT
  reduction, completed one-off, undated reminder, unrepresentable repeat); duplicate-count matching;
  runner idempotency (run twice adds nothing; kill after N steps then rerun adds only the rest; ledger
  written before the next item starts); a failing step; plan block and outcome remap; sidecar v1 to v2
  migration; hiding in agenda/search/planner/density; bridge-id ledgering. Contract cases also run on the
  real `AppleItemRepository` in the simulator harness for the repeat-with-exceptions path.
- `cd web && make test-fast` green (Node 24 from `web/.nvmrc`, same shell) if any web copy changed.
- Simulator, seen with idb and screenshots in light and dark: preview with sample local data (including an
  unrepresentable item and a probable duplicate), import, Apple items present, local copies gone, second
  run says nothing to import, "not imported" mark visible.
- Release device build ok; TestFlight upload via `ship.sh`.
- NOT part of done: the import run on the owner's real data (their action, reported as not verified until
  they confirm), iCloud sync of imported items, VoiceOver, iOS 17, phase 3, website deploy.

## Left to the builder

Exact preview layout and wording (follow the Fantastical grouped-list style), the file split inside
`Import/`, the "probable duplicate" tolerance (start within one minute, case-insensitive trimmed title),
progress presentation, and where the "not imported" mark sits on a row.

## Decisions after the builder check (2026-11-17)

My calls (the owner can override):
1. **Plan blocks and marks.** Local plan blocks (`PlanBlockICS` in the month files) and event
   outcomes (`X-STARK-*` lines) are read from the local store, not the sidecar, so there is no
   `remap` to call. After an item is created in Apple, ONE sidecar `update` writes the import-ledger
   entry, the copied plan blocks (re-keyed to the Apple identifier, occurrence dates unchanged) and
   the copied outcomes together; only then does the item count as imported and hide. A repeating
   reminder's blocks whose occurrence is before its new due date are kept; they read DONE through
   the planner's derived rule (parent behaviour change 8). If the sidecar write fails after the Apple
   save the run STOPS at once and reports it (the item exists in Apple, unledgered; a rerun shows it in
   the probable-duplicate count).
2. **Fields.** Local `Reminder` and `Event` carry only title, notes, dates, all-day, location, URL
   (events), priority (reminders), repeat, exception dates, outcomes and completion; they have no
   alarms or tags, so nothing else exists to lose. A completed one-off reminder is created with its
   original completion date (`NewReminder` gains `completedAt: Date?`, the repository sets
   `isCompleted` and `completionDate`; contract-tested, spike on the real store first) so Weekly Review
   counts it in the right week. All local reminders are dated (the local agenda shows no others).
3. **Repeating reminders.** The used-up count for a fixed `COUNT` = exception dates + completed
   copies (`seriesID` records) in the local store, both read at scan time (history itself is not
   imported). If the reduced count is 0 or the series has ended, it is not imported and is counted in
   the preview as "finished series (kept in the .ics backup)"; it does not block phase 3. A monthly
   day 29-31 or yearly Feb 29 repeat is imported and listed in the preview as "skips short months in
   Apple" (parent behaviour change 1), not silently.
4. **Event exception dates.** The ledger entry is written right after the event is created; then each
   exception date is deleted as an occurrence. A failure there leaves the item ledgered and hidden
   (never duplicated) and puts its title in the result under "check these: occurrences you removed may
   reappear". No cleanup or retry for that case.
5. **Hiding.** `PlannerStore` gets an injected set of imported ids (loaded from the sidecar's import
   ledger) and excludes them in `rebuild()`, the one place the agenda, search, planner tray, densities
   and weekly review read from; the builder confirms that is true before relying on it. A not-imported
   item stays fully editable and deletable locally; the "not imported" mark needs a new `AgendaItem`
   flag. Nothing in phase 2 deletes local items; resolving the leftovers is phase 3's business.
6. **Scan.** The scan calls `loadAllMonths()` first so every `YYYY-MM.ics` is read; any unreadable
   month aborts the scan with the error shown (never treated as empty).
7. **Destinations.** One default calendar takes timed and all-day events. The preview names the default
   calendar and list with their source (iCloud or On My iPhone) and refuses, before starting, if either
   is not writable.

Owner decision (2026-11-17): **import everything, no cutoff.** Every event and every open or completed one-off reminder is imported however old, and every repeating series that still has occurrences left. Only completed copies of repeating reminders (history) and finished series are left behind, as above. The preview shows the counts so the size is visible before confirming.

Correction after Task 3 review (2026-11-17): decision 3's COUNT rule is superseded. A completion in the local store writes BOTH an exception date and a copy, so "exceptions + copies" double counts. The imported COUNT is the original COUNT minus the rule's occurrences before the shown date (exception dates included, as `OccurrenceExpander` counts them), so the series ends on the same last occurrence as in Stark. A clamped day-31 series pins `byMonthDay` to the original day. Skipped occurrences after the shown date cannot be carried (reminders hold no exception dates) and reappear in Apple.
