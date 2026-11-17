# Phase 3: remove the local store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Stark reads and writes only Apple Calendar/Reminders plus its sidecar; the local `.ics` store, its import feature and "not imported" marks are gone; the `.ics` files on the phone are never touched.

**Architecture:** Four staged tasks, each leaving `swift test` green and the app building: (1) `ItemRouter` becomes Apple-only; (2) the app stops reading the local store, the import UI goes and a new error center replaces `PlannerStore.error`; (3) delete the now-unused Kit code and tests; (4) copy and docs. The engines keep their `events:`/`reminders:` parameters and are passed empty local arrays until a later refactor (separate issue).

**Tech Stack:** Swift 5.9, StarkKit (Swift Testing), SwiftUI, EventKit; Go + static HTML website tests (Task 4).

**Spec:** `docs/superpowers/specs/2026-11-17-phase3-remove-local-store-design.md` (decisions 1 to 6 are the rulings) and the reference inventory `docs/superpowers/specs/2026-11-17-phase3-removal-inventory.md`. READ BOTH FULLY before starting; the inventory's section 1 (classification), 2 (behaviour changes), 3 (dead-code hazards), 4 (this task breakdown in detail), 5 (false copy) and 6 (risks) are binding detail. If you deviate from the inventory, say why in your report.

## Global Constraints

- The `.ics` files and `Library/PendingWrites` on any device are never read, written, moved or deleted by the new code; the folder stays untouched. No code may delete anything under Documents.
- `SidecarData` keeps `importLedger` and `importedAt` decoded and RE-ENCODED UNCHANGED (older TestFlight builds 2.0.33 to 2.0.36 must not re-offer the import). Test it: a file with both keys round-trips them and `bridgeLedger` is still ignored.
- Keep (they look local but the Apple path uses them): `OccurrenceExpander`, `AgendaItem`, `sortAgendaItems`, `spanDays`, `YearMonth`, `AgendaWindow.loadRange`/`PlannerDays.loadRange` (Apple fetch windows), `CompletionNote`, `ItemConversion`, `PendingCompletions`, `DayExport`, `PlanBlock`, `RecurrenceRule` and `RecurrenceDescriptor`, `FormFields`, `EventSchedule`. Grep every symbol across Sources, App and Tests before deleting it.
- `DefaultDestinations` lives in `LocalItemStore.swift` and must move to `Items/DefaultDestination.swift` before that file is deleted.
- Apple write failures, plan-cache failures and pending-commit failures must still show in the main error banner (tap to dismiss, same look as today). A forced sidecar read failure must show it (test on the simulator).
- Never `git add` anything under `ios/.build` or `.superpowers` (`git checkout -- ios/.build; git clean -fdq ios/.build`). Run Swift tests from the worktree's `ios/` with `swift test --scratch-path /private/tmp/claude-501/sdd-scratch`. Two timing tests (`yearDensity under 2 s`, the `PendingCompletionsTests` live scheduler) are flaky under machine load: check `uptime`; above 10, run `xcrun simctl shutdown all`, wait, rerun once before judging.
- Test first for every behaviour change (RED shown); pure deletions are verified by the compiler, `swift test` and a grep. Theme rules (CLAUDE.md): no hardcoded colours.
- Web (Task 4): Node 24 on PATH (`N=$(ls -d $HOME/.nvm/versions/node/v24*/bin | tail -1); export PATH="$N:$PATH"`), `cd web && make test-fast && make e2e`. Do NOT deploy the website or touch the VPS. Do not touch the owner's phone (`devicectl` only for reading, and only if a task says so).
- Commit trailers: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01D4JSV4Qz5xEkCxoor2D9h7`. Small commits.

## Done when

See the spec's "Done when". Per task: `swift test` green, simulator + generic iOS builds, the task's own verification below.

## Review Focus

- Anything that wrote to or read from Documents after Task 2 (grep `Documents`, `FileManager`, `PlannerFile`, `PendingWrites`).
- Errors that became silent (the `store.error` call sites; inventory section 2/H1).
- Rows that show twice or vanish: the import hiding is removed only after the app stops reading the store (Task 2 before Task 3).
- The three behaviour edges in the inventory: attended/skipped never dims rows, no carried-miss rows, Search scope.

---

### Task 1: ItemRouter is Apple-only

Follow inventory section 4 "Task 1" exactly. Files: `ios/Sources/StarkKit/Items/ItemRouter.swift`, `LocalItemStore.swift` (delete after moving `DefaultDestinations`), `DefaultDestination.swift`, `StarkApp.swift` (drop `local: store`), `EditItemView.swift` (drop the reminder skip branch and `showsSkip`), `PlannerView.swift` (`completeBlock` drops `today:`), `ItemRouterTests`.

- [ ] **Step 1: Write the failing tests first** (`ItemRouterTests`): a non-Apple id is refused with a clear `ItemRouterError`; `replacePlans` ignores a non-Apple block; `plans(on:)` is sidecar-only; no local origin remains. See them FAIL.
- [ ] **Step 2: Implement** the Apple-only router (no `local`, no `.local` error, no `skipReminder`, `complete` without `today:`); move `DefaultDestinations`; delete `LocalItemStore.swift`; fix the app call sites.
- [ ] **Step 3: Run** `swift test` and the simulator build; idb check per the inventory (complete an Apple reminder from the agenda and from a planner block, edit/delete an event, plan and save a block, Remove This Occurrence). READ the screenshots.
- [ ] **Step 4: Commit** `refactor: ItemRouter is Apple-only`.

### Task 2: the app stops reading the local store; the import UI goes

Follow inventory section 4 "Task 2" and sections 1b, 2 and 3. Create the error center FIRST (test its Kit part if it has logic; the view is `ContentView`'s existing banner reading it), then remove `PlannerStore` from `StarkApp` and the environment, make every view in 1b read Apple + `planCache.applePlans` only (pass `[]` for local events/reminders/plans), remove `loadMonths`/`loadAllMonths`/`start`/`retryPendingWrites`, delete `ImportStarkItemsView`, the Settings row, `ImportModel` wiring, the not-imported marks (AgendaRow, Tray, Search, Agenda, EditItemView) and the History section, make `EditItemView.details` non-optional and drop its `isApple` branches, remove the Weekly Review "Events attended" line (spec decision 3), and change `AgendaItemDetail` to have no `.edit`/`editable` (update `AppleReadOnlyTests`: red first, "a row without appleSource opens read-only").

- [ ] **Step 1: Failing tests first** for the Kit-side changes (`AgendaItemDetail`, the error center if it has logic, Weekly Review without the attended line).
- [ ] **Step 2: Implement.** The Kit still contains `PlannerStore`/ICS/Import (unused by the app, still tested) after this task.
- [ ] **Step 3: Verify on the simulator (iPhone 17) with `.ics` files left in the app's Documents:** copy a few month files and a `recurring.ics` into the app container (`xcrun simctl get_app_container <udid> com.caritos.todo-txt data`), record SHA-256 checksums before and after launching: they must be identical. Launch shows only Apple items, no crash. Walk the agenda, month grid dots, Year, Month, Quarter, Week, Day, planner (tray, NO DATE, save, past day), Search, Weekly Review, Add with tag suggestions, the edit sheet (no History, no Skip, convert both ways), Settings without the import row; force a sidecar read failure (make `sidecar.json` a directory) and confirm the error banner shows and can be dismissed; denied access shows the access screen. Light and dark screenshots of each; READ every one. Generic iOS Release build and Mac Catalyst Debug build (`CODE_SIGNING_ALLOWED=NO`).
- [ ] **Step 4: Commit** `feat: Stark reads only Apple data; the local store and import screen are no longer used`.

### Task 3: delete the Kit code (pure deletion)

Follow inventory section 4 "Task 3". Delete `PlannerStore`, `PlannerFile`, `ICS/*` (including `RRuleCodec`: only the ICS code uses it, confirm with grep), `Import/*`, `CompletionHistory`, `isNotImported` and `marked(notImported:)`, `WeeklyReview.loadRange`, `YearMonth.fileName` (fix its `description`), the sidecar import API (KEEP the two ledger keys), and the dead local branch in `PlanAgenda`; delete/modify the tests listed in inventory 1c; move the sidecar compatibility tests; add a test that a sidecar with `importLedger` and `importedAt` round-trips them unchanged.

- [ ] **Step 1:** Add the round-trip test first (it should pass already or fail for the right reason). **Step 2:** Delete and fix until `swift build` and `swift test` are green; report test and suite counts before and after and the deleted suites. **Step 3:** grep every deleted symbol across `ios/`, `web/`, `docs/ios-feature-notes.md`, `README.md` (zero hits outside history docs), simulator smoke (launch, agenda, planner save), generic iOS Release build. **Step 4: Commit** `refactor: delete the local .ics store code`.

### Task 4: copy and docs

Follow inventory sections 5 and 4 "Task 4". Web test first: rewrite `TestPrivacyDatedAndMentionsData` (drop the import wants; forbid "Import Stark's own items", "still shows", "Not imported") and see it fail; then `privacy.html`, `faq.html`, the in-app `FAQView`, README, CLAUDE.md (a short "Phase 3: local store removed (2026-11-17)" log: what was removed, the gate result, rulings, Done / Not yet verified on device / Deferred including engine slimming as a separate issue, the Next line, and remove or reword every sentence that presents the local store or import as live), `docs/ios-feature-notes.md`, Settings/AccessRequired doc comments. State plainly in the pages: the old `.ics` files remain on the phone, are no longer read, and are deleted only when the app is deleted. Keep the privacy page's "LAST UPDATED: NOVEMBER 2026".

- [ ] **Step 1: Test first (FAIL). Step 2: Edit copy. Step 3:** `make test-fast` and `make e2e` PASS. **Step 4: Commit** `docs: phase 3, Stark no longer reads its own files`.

### Controller steps (not for the implementers)

- [ ] After each task: independent review, fix loop as needed. After Task 4: whole-branch review, merge to main, full suite on the merged result, `ship.sh` to TestFlight, push, open a GitHub issue for the deferred engine slimming (inventory Task 5) and fold #122 into it, vault session note. NO website deploy.
