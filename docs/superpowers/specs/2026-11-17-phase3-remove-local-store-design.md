# Phase 3: remove the local `.ics` store

Date: 2026-11-17. Parent: `2026-11-15-apple-write-through-design.md` ("Removal"). Phase 1 (write path) and phase 2 (import) are shipped. Detailed inventory of every file and call site: `2026-11-17-phase3-removal-inventory.md` (read-only reconnaissance, committed as reference).

## Intent

Stark's own files (`recurring.ics`, `YYYY-MM.ics`) are dead weight: every item in them is now in Apple Calendar and Reminders. Remove the code that reads, writes, shows and imports them so Stark reads and writes ONLY Apple data (plus its small sidecar for plan blocks and attended/skipped marks). The `.ics` files stay on the phone untouched as a backup; the app just stops opening them.

## Gate (verified 2026-11-17 on the owner's phone, read-only)

Running the real `ImportPlanner` over the phone's files with the ledger applied: 0 steps remaining, 0 unrepresentable, 0 finished series, 0 short-month repeats, no load errors; 152 month files and `recurring.ics`; 3372 events and 5149 reminders in the import ledger (8521 entries), plus 199 completed copies of repeating reminders (history, never imported by design); `Library/PendingWrites` absent; sidecar `importedAt` set.

## Goals

- The app compiles, launches and runs with no `PlannerStore`, `PlannerFile`, ICS parser/serializer, month loading, import feature or "not imported" marks.
- Every screen (agenda, month grid, year, quarter, week, day, planner, search, weekly review, tag suggestions, day export) reads the Apple snapshot plus the sidecar's plans/outcomes only.
- Apple write failures, plan-cache failures and pending-commit failures still reach the owner through an error banner (replacement for `PlannerStore.error`).
- The `.ics` files in Documents are never read, written, moved or deleted by the new build (prove with checksums).
- Older TestFlight builds (2.0.33 to 2.0.36) that read the same sidecar must not re-offer the import: the sidecar keeps `importLedger` and `importedAt` decoded and re-encoded unchanged.

## Non-goals

- Deleting any file on the phone. Importing the 199 completed repeating-reminder copies. Slimming the engines' `events:`/`reminders:` parameters and rewriting ~250 engine tests (inventory Task 5: becomes a separate GitHub issue). The website deploy (needs the owner's go).

## Decisions (controller rulings while the owner is away; each can be reversed)

1. **History left behind is accepted.** The 199 completed copies of repeating reminders (and any plan blocks tied to them) disappear from every screen. This is parent spec decision 1 ("Stark keeps no completion history for repeating reminders"). Cost if wrong: the owner loses those 199 history rows; the files still hold them.
2. **Sidecar import keys are preserved.** `SidecarData` keeps `importLedger` and `importedAt` (decode and re-encode unchanged), but loses all APIs that use them. Cost if wrong: two unused fields.
3. **Weekly Review's "Events attended" line is removed** because it becomes permanently 0 for Apple events (attended marks live in the sidecar and are shown in the editor only). The editor's Attended/Didn't attend buttons and the sidecar outcomes stay. Cost if wrong: one stat line, easy to bring back.
4. **Search and tag suggestions keep their current Apple-only scope** (events +-2 years, all reminders); a wider Search fetch is a later idea.
5. **Error surface:** a small `@Observable` error center replaces `PlannerStore.error` for the main banner (tap to dismiss, as today).
6. Only the owner's phone was gated; the owner is the only TestFlight tester (parent spec). Never submit phase 3 for App Store review.

## Approaches considered

- **A (chosen): staged removal in four tasks (router Apple-only; app stops reading the store and the import UI goes; delete Kit code; copy and docs).** Each task leaves `swift test` green and the app building; the import hiding is removed only after the app stops reading the store.
- B: one big deletion commit. Rejected: unreviewable, and a mid-way build break hides regressions.
- C: keep the local store read-only "just in case". Rejected: it is exactly the duplicate-source problem the whole rewrite removed, and the files remain on the phone anyway.

## Done when

- `cd ios && swift test` green after each task and at the end; simulator, generic iOS Release and Mac Catalyst Debug builds succeed (`CODE_SIGNING_ALLOWED=NO` where unsigned).
- Simulator (iPhone 17) with `.ics` files left in the app's Documents: launch shows only Apple items, no crash, the `.ics` files have identical checksums before and after, light and dark screenshots of each screen read; the error banner appears for a forced sidecar failure.
- A grep of `ios/` finds no reference to a deleted symbol outside history docs.
- `cd web && make test-fast` and `make e2e` green after the copy changes; the website is NOT deployed.
- Not part of done: owner device verification, website deploy, App Store review, engine slimming.
