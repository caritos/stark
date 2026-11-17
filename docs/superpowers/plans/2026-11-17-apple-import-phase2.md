# Apple Import Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One-time, previewed, idempotent import of Stark's local `.ics` items (plus their plan blocks and attended/skipped marks) into Apple Calendar and Reminders, hiding imported items from the local store.

**Architecture:** A pure `ImportPlanner` in StarkKit turns the local store into an `ImportPlan` (preview plus ordered steps). An `ImportRunner` actor executes the steps one at a time through `ItemRepository`, writing one sidecar update per item (import ledger, plan blocks, outcomes, bridge ledger). `PlannerStore` hides ledgered ids in `rebuild()`. A thin SwiftUI screen drives it from Settings.

**Tech Stack:** Swift 5.9, StarkKit SwiftPM (Swift Testing, `cd ios && swift test`), SwiftUI app target, EventKit (app target only), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-17-apple-import-phase2-design.md` (parent: `2026-11-15-apple-write-through-design.md`, decisions 1, 7, 8, 9). Read both.

## Global Constraints

- All logic in StarkKit with Swift Testing (`import Testing`, `@Test`, `#expect`), never XCTest; the app target holds views and EventKit glue only.
- Test first (red, green, refactor); one commit per green step on a feature branch in a worktree (`git worktree add .claude/worktrees/apple-import-phase2 -b apple-import-phase2`, absolute paths). Merge locally only after the full suite is green on the merged result.
- `ios/.build` is tracked: never `git add` it; run `git checkout -- ios/.build; git clean -fdq ios/.build` before every commit. Stale module cache: `rm -rf ios/.build/arm64-apple-macosx/debug/ModuleCache`.
- Run `xcodegen generate` (in `ios/App/Stark`, where `project.yml` is) after adding or deleting Swift files and commit the regenerated pbxproj.
- Time-sensitive tests build dates with a local `Calendar` and must pass under TZ Honolulu, New York and Tokyo.
- Sidecar is the only place Apple identifiers are stored; never persist absolute paths. The `.ics` files are never modified or deleted.
- Local models carry only title, notes, dates, all-day, location, URL, priority, repeat, exception dates, outcomes, completion. Completed copies of repeating reminders (`seriesID != nil`) are never imported. No cutoff: everything else is imported however old.
- Web copy changes need `cd web && make test-fast` (Node 24: `nvm use` in the same shell, no pipe).
- Commit trailers: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01D4JSV4Qz5xEkCxoor2D9h7`.

## Done when

- `cd ios && swift test` green (1183 today plus the new suites), also with `TZ=Pacific/Honolulu`, `America/New_York`, `Asia/Tokyo` for the new suites.
- The contract case for completed one-offs and the exception-date path pass on the real `AppleItemRepository` in the simulator harness (`.superpowers/contract-harness`).
- `cd web && make test-fast` green if any web page changed.
- Simulator, seen with idb screenshots in light and dark: preview with seeded local data (an unrepresentable item, a probable duplicate, a monthly day-31 repeat, a finished series), import, items present in Apple, local copies gone, second open says nothing to import, "not imported" mark visible.
- Release device build compiles; `ios/App/ship.sh` uploads to TestFlight.
- NOT part of done (report as "not verified"): the import on the owner's real data, iCloud sync of imported items, VoiceOver, iOS 17, phase 3, website deploy.

## Review Focus

- A completed one-off imported with the wrong completion week (Weekly Review): Task 1 and Task 3 tests pin `completedAt`.
- Killing the run after the Apple save but before the sidecar write, or after N items: Task 4 tests rerun and assert no duplicate in the fake repository.
- An unreadable month file or unreadable sidecar mid-scan: scan aborts with the error, never an empty plan (Task 3, Task 4).
- A local event or reminder with an empty title or an end before its start: imported as-is without crashing (Task 3).
- Hidden items still reachable through search, planner tray, density or weekly review: Task 5 asserts every read goes through `rebuild()`.

---

### Task 1: `NewReminder.completedAt` (create a completed one-off)

**Files:**
- Modify: `ios/Sources/StarkKit/Items/ItemRepository.swift` (`NewReminder`)
- Modify: `ios/Sources/StarkKit/Items/FakeItemRepository.swift`, `ios/App/Stark/Stark/AppleItemRepository.swift` (`addReminder`, `addBatch`)
- Test: the shared contract suite (find it with `grep -rn "contract" ios/Tests | head`) and `ios/Tests/.../ItemRepositoryContractTests`

**Interfaces:**
- Produces: `NewReminder.completedAt: Date?` (default nil, last init parameter `completedAt: Date? = nil`). When non-nil the created reminder is completed with that completion date, not a recurring one (a recurring `NewReminder` with `completedAt` throws `ItemRepositoryError.unrepresentable("completed repeating reminder")`).

- [ ] **Step 1: Spike on the simulator** with the contract harness: create an `EKReminder` with `isCompleted = true` and `completionDate = <a date 40 days ago>`, save, refetch; record in a comment in the test whether EventKit keeps the date. If it does not, stop and report (the plan changes).
- [ ] **Step 2: Write failing contract cases** `addReminderCompletedKeepsCompletionDate` (add with `completedAt`, `details(ref).reminder?.isCompleted == true`, `completedAt` equal within 1 s) and `addRecurringCompletedThrows`; run against the fake: expect FAIL (no such property).
- [ ] **Step 3: Implement** the field, the fake behaviour, and the EventKit behaviour (`isCompleted = true`, `completionDate = completedAt`).
- [ ] **Step 4: Run** `cd ios && swift test --filter ItemRepositoryContract` PASS; run the harness for the real repository PASS.
- [ ] **Step 5: Commit** `feat: NewReminder.completedAt for importing completed one-offs`.

### Task 2: Sidecar v2 with the import ledger

**Files:**
- Modify: `ios/Sources/StarkKit/Items/ItemSidecar.swift`
- Test: `ios/Tests/StarkKitTests/ItemSidecarImportLedgerTests.swift` (create), plus a fixture `ios/Tests/StarkKitTests/Fixtures/sidecar-v1.json` copied from a sidecar written by the current code.

**Interfaces:**
- Produces: `SidecarData.importLedger: [String: String]` (local id -> Apple identifier) and `SidecarData.importedAt: Date?`; `SidecarData.currentVersion = 2`; `ItemSidecar.importedIDs() throws -> Set<String>`; `ItemSidecar.recordImport(_ item: ImportRecord) throws` where `struct ImportRecord { localID: String; identifier: String; externalID: String?; plans: [PlanBlock]; outcomes: [EventOutcomeRecord] }` writes ledger entry, bridge ledger entry (`bridgeLedger[localID] = identifier`), `externalIDs`, plan blocks (re-keyed `reminderID = identifier`) and outcomes (as `OutcomeEntry`) in ONE `update`; `ItemSidecar.markImportFinished(at: Date)`.

- [ ] **Step 1: Write failing tests:** `loadsVersion1FileAndUpgrades` (load the fixture, `recordImport`, reload: version 2, every v1 field unchanged, `importLedger` has the entry); `recordImportWritesAllPartsInOneWrite` (inject a counting `SidecarWriter`: exactly one write per `recordImport`); `failedWriteChangesNothing` (writer throws; reload equals before); `version3FileIsRefused` (`unsupportedVersion(3)`); `corruptFileThrowsNotEmpty`.
- [ ] **Step 2: Run** `swift test --filter ItemSidecarImportLedger` FAIL.
- [ ] **Step 3: Implement.** Decode missing keys with `decodeIfPresent` defaults (custom `init(from:)`); outcomes sorted as today.
- [ ] **Step 4: Run** PASS, then the whole existing `ItemSidecar*` suites PASS.
- [ ] **Step 5: Commit** `feat: sidecar v2 with import ledger and single-write recordImport`.

### Task 3: `ImportPlanner` (pure)

**Files:**
- Create: `ios/Sources/StarkKit/Import/ImportPlan.swift` (types), `ios/Sources/StarkKit/Import/ImportPlanner.swift`
- Test: `ios/Tests/StarkKitTests/ImportPlannerTests.swift`

**Interfaces:**
- Consumes: `Event`, `Reminder`, `PlanBlock`, `ItemRouter.newEvent/newReminder` (make them `internal` -> `package`/public static if needed), `RecurrenceDescriptor(_:)` (throws when unrepresentable), `buildAgendaItems` (`Planner/AgendaBuilder.swift`), `AppleItemProvider` data already loaded for Search (`[AgendaItem]` with `appleSource`).
- Produces: 
  - `struct ImportStep { localID: String; kind: AppleItemRef.Kind; event: NewEvent?; reminder: NewReminder?; exceptionDates: [Date]; plans: [PlanBlock]; outcomes: [EventOutcomeRecord]; title: String }`
  - `struct ImportPlan { steps: [ImportStep]; unrepresentable: [(localID: String, title: String, reason: String)]; finishedSeries: [String]; skippedHistoryCount: Int; probableDuplicates: Int; shortMonthRepeats: [String]; counts: ImportCounts }` and `ImportCounts { events, openReminders, completedReminders, recurringMasters, planBlocks, outcomes }`
  - `ImportPlanner.plan(events: [Event], reminders: [Reminder], plans: [PlanBlock], alreadyImported: Set<String>, apple: [AgendaItem], today: Date, calendar: Calendar) -> ImportPlan`

- [ ] **Step 1: Write failing tests** (local `Calendar`, fixed `today`), one per rule:
  - `plainEventConvertsAllFields`; `allDayAndMultiDayEventKeepShape`; `eventWithExceptionDatesListsThem` (`steps[0].exceptionDates` equals the event's, `event.recurrence` kept).
  - `openOneOffReminderKeepsDueAndPriority`; `completedOneOffGetsCompletedAt` (`reminder.completedAt == completedDate ?? completedAt`, per `Reminder` fields); `completedCopiesWithSeriesIDAreCountedNotImported` (`skippedHistoryCount == 3`).
  - `repeatingReminderDueIsShownOccurrence` (oldest unresolved miss inside the 90-day lookback, else the next one: assert both cases against `buildAgendaItems`' row for the series; `dueHasTime` follows `FormFields.dueHasTime`).
  - `fixedCountIsReducedByExceptionsAndCompletedCopies` (COUNT 10, 2 exdates, 3 copies -> 5); `countReducedToZeroIsFinishedSeries`; `endedUntilIsFinishedSeries` (neither is in `steps`, both in `finishedSeries`).
  - `unrepresentableRepeatIsListedWithReason` (a rule `RecurrenceDescriptor` throws on, e.g. a yearly positional the spec lists) and never in `steps`.
  - `monthlyDay31AndYearlyFeb29AreListedAsShortMonthRepeats` and still in `steps`; "last day of the month" is NOT listed.
  - `alreadyImportedIdsAreOmitted`; `emptyTitleAndEndBeforeStartDoNotCrash`.
  - `planBlocksAndOutcomesFollowTheirItem` (blocks matched by `reminderID`, outcomes from `Event.outcomes`; counts match).
  - `probableDuplicateMatchesTitleCaseInsensitiveStartWithinOneMinute` and `doesNotMatchDifferentDay`; duplicates never remove a step.
  - `stepsAreOrderedEventsFirstThenRemindersByDate` (deterministic so reruns are stable).
- [ ] **Step 2: Run** `swift test --filter ImportPlanner` FAIL.
- [ ] **Step 3: Implement** the types and `plan`. One line of approach: derive a repeating reminder's shown occurrence by running `buildAgendaItems` on that single reminder (its exceptions and copies included) so there is one source of truth; reduce COUNT by `exceptionDates.count + copies.count`.
- [ ] **Step 4: Run** PASS under the three TZs (`TZ=... swift test --filter ImportPlanner`).
- [ ] **Step 5: Commit** `feat: ImportPlanner turns local items into a preview and steps`.

### Task 4: `ImportRunner`

**Files:**
- Create: `ios/Sources/StarkKit/Import/ImportRunner.swift`
- Test: `ios/Tests/StarkKitTests/ImportRunnerTests.swift` (uses `FakeItemRepository`, a temp-file `ItemSidecar`, a failing/“killing” `SidecarWriter`)

**Interfaces:**
- Consumes: `ImportPlan`/`ImportStep` (Task 3), `ItemRepository.addEvent/addReminder/deleteOccurrence`, `ItemSidecar.recordImport` (Task 2), `NewReminder.completedAt` (Task 1).
- Produces: `actor ImportRunner { init(repository: ItemRepository, sidecar: ItemSidecar, calendarID: String, listID: String); func run(_ plan: ImportPlan, progress: @Sendable (Int, Int) -> Void) async -> ImportResult }` with `struct ImportResult { imported: [String]; failed: [(title: String, message: String)]; needsCheck: [String]; stoppedBecauseSidecar: String?; cancelled: Bool }`. Runner checks `Task.isCancelled` between steps. Preflight: `DefaultDestination.problem(calendarID:listID:)` non-nil -> result with every step failed and nothing created.

- [ ] **Step 1: Write failing tests:** `importsEveryStepAndLedgersEachBeforeTheNext` (after step k's save, a sidecar read shows entry k before step k+1 starts: assert with a repository that reads the sidecar inside `addEvent`); `secondRunAddsNothing` (plan again with `alreadyImported` from the sidecar: empty plan, repository count unchanged); `killAfterNStepsThenRerunAddsOnlyTheRest` (cancel via a progress callback at step 3); `failedStepIsReportedAndRunContinues` (repository throws on item 2 only; items 1 and 3 ledgered, 2 not, retry later imports only 2); `sidecarWriteFailureStopsRunAtOnce` (`stoppedBecauseSidecar` non-nil, later steps not created); `exceptionDeleteFailureStillLedgersAndReportsNeedsCheck`; `planBlocksAndOutcomesLandUnderTheAppleIdentifier`; `completedOneOffIsCreatedCompleted`; `unwritableDestinationRefusesBeforeCreatingAnything`.
- [ ] **Step 2: Run** `swift test --filter ImportRunner` FAIL.
- [ ] **Step 3: Implement** `run` sequentially: create (completed one-off via `completedAt`) -> `sidecar.recordImport` -> for each exception date `deleteOccurrence` (failure appends to `needsCheck`, never throws) -> progress. After the last step call `sidecar.markImportFinished(at:)` only if no step failed and nothing is unrepresentable-pending is irrelevant (finished = every step imported).
- [ ] **Step 4: Run** PASS.
- [ ] **Step 5: Commit** `feat: ImportRunner with per-item ledger writes`.

### Task 5: Hide imported items; "not imported" mark

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/PlannerStore.swift` (`rebuild()`, new accessors), `ios/Sources/StarkKit/Planner/AgendaBuilder.swift` (`AgendaItem`)
- Test: `ios/Tests/StarkKitTests/PlannerStoreImportHidingTests.swift`

**Interfaces:**
- Consumes: `ItemSidecar.importedIDs()` (Task 2).
- Produces: `PlannerStore.setImportedIDs(_ ids: Set<String>)` (calls `rebuild()`); `PlannerStore.allEvents: [Event]`, `allReminders: [Reminder]`, `allPlans: [PlanBlock]` (unfiltered, for the planner scan); `events`, `reminders`, `plans` exclude imported ids and plans of imported reminders; `PlannerStore.notImportedIDs: Set<String>` (set by the app from the last plan's `unrepresentable` local ids) and `AgendaItem.isNotImported: Bool` (default false, set by the agenda builder callers via an `AgendaBuilder` parameter `notImported: Set<String> = []`).

- [ ] **Step 1: Write failing tests:** `importedEventAndReminderDisappearFromAgendaSearchDensityTrayAndReview` (assert through each of `buildAgendaItems`, `SearchResults`, `gridDensity`, `yearDensity`, the planner tray model and `WeeklyReview` using `store.events/reminders/plans`), `importedReminderPlansAreHidden`, `unimportedItemStaysEditableAndDeletable`, `allEventsStillContainHiddenItems`, `rowCarriesNotImportedFlag`, `settingIdsBackToEmptyShowsThemAgain`.
- [ ] **Step 2: Run** `swift test --filter PlannerStoreImportHiding` FAIL.
- [ ] **Step 3: Implement** by keeping unfiltered arrays private and filtering in `rebuild()`; confirm by grep that no consumer reads `monthEvents`/`recurringEvents` directly.
- [ ] **Step 4: Run** PASS, then the full `swift test`.
- [ ] **Step 5: Commit** `feat: hide ledgered local items and mark unimported ones`.

### Task 6: App screen and wiring

**Files:**
- Create: `ios/App/Stark/Stark/ImportStarkItemsView.swift`, `ios/Sources/StarkKit/Import/ImportModel.swift` (`@MainActor @Observable`, holds the state machine so the view stays thin)
- Modify: `ios/App/Stark/Stark/SettingsView.swift` (row, visible while any local item is un-ledgered), `StarkApp.swift` (load `importedIDs` into `PlannerStore` at launch and after a run), `ios/App/Stark/Stark/FAQView.swift`
- Test: `ios/Tests/StarkKitTests/ImportModelTests.swift`

**Interfaces:**
- Consumes: Tasks 2 to 5; `DefaultDestinationModel` for calendar/list ids and names and their source titles.
- Produces: `ImportModel` states `idle -> scanning -> preview(ImportPlan, destinations) -> running(done, total) -> finished(ImportResult)`; methods `scan()`, `confirm()`, `cancel()`. Scan calls `store.loadAllMonths()` first and fails with the error shown if `store.error` is set or the sidecar is unreadable; never a plan from partial data.

- [ ] **Step 1: Write failing tests:** `scanLoadsAllMonthsFirst`, `unreadableMonthAbortsScan`, `unreadableSidecarAbortsScan`, `confirmRunsAndPublishesProgress`, `nothingToImportState`, `retryAfterFailureOnlyPlansTheRest`.
- [ ] **Step 2: Run** FAIL.
- [ ] **Step 3: Implement** `ImportModel`, then the view (grouped list: destination rows with names and source, count rows, "N look already in Apple" row, "Skips short months in Apple" and "Finished series, kept in the backup" and "Can't be imported" sections listing titles, a confirm button "Import N items", progress, result with `failed` and `needsCheck` titles; copy: the .ics files are kept; to undo, delete in Apple's apps; toolbar and colors from `Theme.swift`, no hardcoded colors). Add the Settings row and the launch wiring; run `xcodegen generate`.
- [ ] **Step 4: Run** `swift test` PASS; build for the simulator (`xcodebuild -scheme Stark -destination 'generic/platform=iOS Simulator' build`) and generic iOS Release build compile.
- [ ] **Step 5: Seed and verify on the iPhone 17 simulator** with idb: put test month files with the cases from "Done when" into the app's Documents, open Settings > Import, screenshot light and dark (preview, progress, result), import, check Apple's Calendar and Reminders data and that the local copies are gone, reopen: nothing to import, "not imported" mark visible. Read each screenshot.
- [ ] **Step 6: Commit** `feat: Import Stark's own items screen`.

### Task 7: Docs, log, ship

**Files:**
- Modify: `CLAUDE.md` (log: Done / Not yet verified on device / Deferred; "Next" line), `docs/ios-feature-notes.md` (Apple overlay and write-through paragraph), `docs/superpowers/specs/2026-11-15-apple-write-through-design.md` (mark phase 2 built), in-app FAQ, `web/public/pages/faq.html` and `privacy.html` only if wording about local items changes.

- [ ] **Step 1:** Update docs; if a web page changed run `cd web && make test-fast` (Node 24) PASS.
- [ ] **Step 2:** Full `cd ios && swift test` PASS on the branch, merge to main locally, full suite on the merged result PASS, `xcodebuild` Release build for a device compiles.
- [ ] **Step 3:** `(set -a; . ~/.appstoreconnect/env; set +a; ios/App/ship.sh)` in a subshell, never printing values; log the TestFlight version in `CLAUDE.md`, push main and say so in one line.
- [ ] **Step 4:** Report each Done-when item as met, unmet or not verified; the owner runs the real import and reports back.
