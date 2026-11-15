# Apple Write Path (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stark creates, completes, edits and deletes real Apple events and reminders (new items, the Claude Code bridge, the planner and Weekly Review all work on Apple items), while the old local `.ics` items stay visible and editable until phase 2 imports them.

**Architecture:** A Kit-level `ItemRepository` protocol (async, `Sendable`, plain value types) with a fake for tests; the only EventKit code is `AppleItemRepository` in the app target next to `EventKitProvider`. A thin router sends an item to Apple or to the existing `PlannerStore` by its origin (`apple-` id prefix today). Things Apple cannot hold (planner blocks, event outcomes, the bridge ledger) live in one small JSON sidecar keyed by Apple identifiers. Engines (`DayPlanModel`, `WeeklyReview`, `TagAutocomplete`, `SearchResults`, `DayHistory`) learn to take Apple items.

**Tech Stack:** Swift 5.9 package + SwiftUI iOS 17.0, Swift Testing, EventKit, idb on the iOS Simulator (the simulator Calendar/Reminders store accepts writes).

**Spec:** `docs/superpowers/specs/2026-11-15-apple-write-through-design.md` (binding, including "Decisions after the builder check"; builds on `2026-11-15-apple-overlay-design.md`). Phases 2 (import) and 3 (removal) get their own plans after this phase is checked on the owner's iPhone, because the spikes in Task 1 and the device check decide details of both.

## Global Constraints

- Work in a git worktree created with `git worktree add .claude/worktrees/<name> -b <name>` from local main (the harness `EnterWorktree` branches from origin); commit after each green task; do not push, ship or deploy without the controller (the owner approved a TestFlight build for testing: Task 10 only).
- iOS deployment target 17.0; StarkKit `.iOS(.v17)`, `.macOS(.v14)`; StarkKit never imports EventKit. Swift Testing only; tests first, see them fail for the right reason.
- All EventKit work off the main actor (`nonisolated`, `@concurrent` as in `EventKitProvider`); one `EKEventStore` (reuse `EventKitProvider`'s lazy store); no network calls.
- Never save an overlay stand-in `Event`/`Reminder` back whole: they carry no recurrence rule, time zone or write permission. Edits load the real EventKit item and write back only changed fields (spec call 5).
- Never delete or modify the owner's `.ics` files in this phase. Local items keep working exactly as today.
- Theme tokens only (`Theme.swift`); the calendar colour dot is the one data colour. No hardcoded hex, hard edges, one accent.
- Persist only: the on/off/default-destination settings in UserDefaults (ids only) and the sidecar JSON in Library (atomic writes, schema version field). No absolute paths.
- Xcode project: synchronized root groups (no pbxproj edit for new Swift files); no `project.yml`.
- Build checks every UI task: `cd ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` ends in `** BUILD SUCCEEDED **`; the Mac Catalyst build per `docs/superpowers/plans/2026-09-22-mac-catalyst-target.md` also succeeds.
- Deferred review minors from the overlay are in `CLAUDE.md` "Apple overlay log"; do not fix them here unless a task says so.

## Done when

- `cd ios && swift test` passes with new tests for: the repository contract (fake), recurrence/priority/all-day mapping round trips (incl. DST), the sidecar (atomic write, remap, orphans kept), the router (Apple vs local ids), bridge idempotency through the ledger, planner/Weekly Review/tag autocomplete/search on Apple items, "plan block whose occurrence the series moved past reads as done".
- Simulator run with idb screenshots against the simulator's Calendar/Reminders: add an event and a reminder from Stark (they appear in Apple's Calendar and Reminders apps), complete a reminder, edit a repeating event's title (whole series), delete an item, skip one event occurrence, timebox an Apple reminder in the planner and mark it done, run a Claude Code bridge URL (`xcrun simctl openurl`) that lands in Apple, access-denied screen, the "No date" tray pane.
- `cd web && make test-fast` passes (privacy/FAQ copy: Stark now writes to Calendar and Reminders).
- TestFlight build shipped (Task 10) and the device checklist handed to the owner; "confirmed on device" recorded separately from "unit-tested".
- NOT part of done: import of old items (phase 2), removing the local store (phase 3), the Mac tool, deleting `.ics` files.

## Review Focus

- Editing a repeating Apple event or reminder never strips its recurrence rule, alarms, attendees or time zone; an invitee-only or read-only calendar item shows no edit/delete.
- Completing a repeating Apple reminder moves it to its next date and never completes the whole series by accident (per the Task 1 spike).
- A failed EventKit save shows a visible error and leaves the screen consistent; nothing is silently dropped.
- A bridge batch is all-or-nothing and re-sending the same file adds nothing; a batch interrupted halfway does not duplicate on retry.
- Items created in Stark never vanish from view (default calendar/list always shown, overlay forced on).
- Local `.ics` items still behave exactly as before (existing tests stay green untouched).

## File Structure

- Create `ios/Sources/StarkKit/Items/ItemRepository.swift` (protocol, patch types, errors), `FakeItemRepository.swift`, `ItemRouter.swift`, `RecurrenceDescriptor.swift`, `ItemSidecar.swift`.
- Modify engines: `Planner/DayPlanModel.swift`, `DayHistory.swift`, `PlanAgenda.swift`, `WeeklyReview.swift`, `TagAutocomplete.swift`, `SearchResults.swift`, `Apple/AppleMerge.swift` (undated reminders), `Bridge/ClaudeBridge.swift`, `Sources/StarkClaudeCore/TodayCommand.swift`, `.claude/commands/stark.md`.
- Create app files `ios/App/Stark/Stark/AppleItemRepository.swift`, `DefaultDestinationModel.swift`, `AccessRequiredView.swift`; modify `AddItemView.swift`, `EditItemView.swift`, `AgendaView.swift`, `AgendaRow.swift`, `AppleItemDetailView.swift`, `PlannerView.swift`, `WeeklyReviewView.swift`, `SearchView.swift`, `TagSuggestionRow.swift`, `ContentView.swift`, `StarkApp.swift`, `AppleSettingsView.swift`, `SettingsView.swift`.
- Tests under `ios/Tests/StarkKitTests/` per task; findings doc `docs/superpowers/specs/2026-11-15-eventkit-write-spikes.md`.

---

### Task 1: EventKit write spikes (findings, no product code)

**Files:** Create `docs/superpowers/specs/2026-11-15-eventkit-write-spikes.md`. Any harness is throwaway (a DEBUG launch-argument hook or a scratch app); do not commit it.

**Interfaces:** Produces the answers later tasks rely on (stated as plain facts in the doc).

- [ ] **Step 1:** On the iPhone 17 simulator (create a Calendar and a Reminders list there), establish and record with the exact EventKit calls used and the observed result: (a) saving `isCompleted = true` on a recurring `EKReminder` (daily, weekly, monthly): does the series advance to the next due date or end; what `completionDate`/`dueDateComponents` read afterwards; whether `commit` vs per-item save matters; (b) saving a recurring `EKEvent` obtained from `event(withIdentifier:)` with span `.futureEvents` after changing the title and after changing the time: does an occurrence previously edited individually survive; (c) deleting one occurrence with span `.thisEvent`, and the whole series with `.futureEvents`; (d) which recurrence features of Stark's `RecurrenceRule` (weekly with several weekdays, monthly day N, last day of month, positional "2nd Tuesday", until, count, interval) round-trip through `EKRecurrenceRule`; (e) `allowsContentModifications` and `calendar.type` values for the simulator's calendars, and whether an invitee-only event reports `organizer`/`isDetached`; (f) `EKEventStoreChanged` count after one save.
- [ ] **Step 2:** Write the doc: one section per question with the observed behaviour and the decision it implies for Tasks 3 and 6 (if (a) shows the series ends, Task 6's `complete` must move the due date to the next occurrence explicitly; say how). Mark everything verified on the simulator only; the device recheck is in Task 10's checklist.
- [ ] **Step 3:** Commit `docs: EventKit write spike findings`. If a spike result contradicts the spec, stop and report to the controller (the spec is binding).

### Task 2: `ItemRepository` protocol, patch types and fake

**Files:** Create `Items/ItemRepository.swift`, `Items/FakeItemRepository.swift`; test `ItemRepositoryContractTests.swift`.

**Interfaces:**
- Produces:
  - `struct AppleItemRef: Equatable, Hashable, Sendable { kind: Kind (.event/.reminder); identifier: String; externalID: String? }` plus `init?(agendaItemID: String)` and `static func ref(for item: AgendaItem) -> AppleItemRef?` (strips the `apple-` prefix and the occurrence timestamp the way `mergeAppleItems` builds ids).
  - `struct NewEvent`/`NewReminder` (the same fields as `Event`/`Reminder` minus id) and `enum Patch<T> { case keep, set(T), clear }`; `struct EventPatch { title, notes, location, url, start, end, isAllDay, recurrence: Patch<RecurrenceRule>, ... }` and `ReminderPatch { title, notes, due, dueHasTime, priority, recurrence, url }`.
  - `struct ItemDetails: Sendable { event: Event? / reminder: Reminder?` carrying the REAL recurrence and exception dates, `calendarID`, `isWritable: Bool`, `isInviteeOnly: Bool, hasUnrepresentableRepeat: Bool }`.
  - `protocol ItemRepository: Sendable` with async throwing: `addEvent(_:calendarID:) -> AppleItemRef`, `addReminder(_:listID:) -> AppleItemRef`, `details(_ ref) -> ItemDetails`, `update(_ ref, event: EventPatch)`, `update(_ ref, reminder: ReminderPatch)`, `delete(_ ref)` (whole series), `deleteOccurrence(_ ref, on: Date)` (events), `complete(_ ref, on: Date)`, `uncomplete(_ ref)`, `writableCalendars() -> [AppleCalendarInfo]`, `addBatch(events:reminders:) -> [AppleItemRef]` (all-or-nothing). `enum ItemRepositoryError: Error, Equatable { notFound, notWritable, unrepresentable(String), saveFailed(String) }`.
  - `FakeItemRepository` (actor) keeping items in memory with the same semantics the real one must have, including patch-only-changed-fields, all-or-nothing batch, and a `failNext` hook.

- [ ] **Step 1:** Write `ItemRepositoryContractTests`, parameterised so the same suite can later run against any implementation: add/get round trip, patch changes only the patched fields and keeps recurrence when `.keep`, `.clear` removes it, delete whole series, deleteOccurrence leaves other occurrences, complete/uncomplete a one-off, batch failure rolls back every item, not-writable calendar throws `notWritable`.
- [ ] **Step 2:** Run to see compile failure; implement the types and the fake; run the suite and the full `swift test`.
- [ ] **Step 3:** Commit `feat(kit): ItemRepository protocol and fake`.

### Task 3: Recurrence and field mapping (Kit, neutral descriptor)

**Files:** Create `Items/RecurrenceDescriptor.swift`; test `RecurrenceDescriptorTests.swift`.

**Interfaces:**
- Consumes: `RecurrenceRule` (existing), the Task 1 findings.
- Produces: `struct RecurrenceDescriptor: Equatable, Sendable { frequency: Daily/Weekly/Monthly/Yearly; interval: Int; weekdays: [Weekday]; daysOfMonth: [Int] (−1 = last); setPositions: [Int]; end: .never/.until(Date)/.count(Int) }`; `RecurrenceDescriptor.init(_ rule: RecurrenceRule) throws` (throws `unrepresentable` with a reason) and `func rule() -> RecurrenceRule`; `func appleReminderPriority(_ icalPriority: Int?) -> Int` and the inverse (Stark's 1-9 scale vs `EKReminder.priority` 0-9; they match: assert it).

- [ ] **Step 1:** Tests: round trip for every case that Task 1 (d) marked supported (weekly several weekdays, monthly day N, last day of month, 2nd Tuesday, until date-only inclusive, count, interval 2); `unrepresentable` thrown with a readable reason for each case Task 1 marked unsupported; priority mapping both ways including nil/0.
- [ ] **Step 2:** Implement and run; the app-side mapping `RecurrenceDescriptor <-> EKRecurrenceRule` is written in Task 6 as a thin file exercised by the simulator run.
- [ ] **Step 3:** Commit `feat(kit): recurrence descriptor mapping`.

### Task 4: Sidecar (plans, outcomes, bridge ledger)

**Files:** Create `Items/ItemSidecar.swift`; test `ItemSidecarTests.swift`.

**Interfaces:**
- Produces: `struct SidecarData: Codable, Equatable { version: Int; plans: [PlanBlock]; outcomes: [OutcomeKey: EventOutcomeRecord]; bridgeLedger: [String: String] /* bridge item id -> Apple identifier */ }` with `OutcomeKey { identifier: String; externalID: String?; day: String }`; `actor ItemSidecar { init(fileURL: URL); func load() throws -> SidecarData; func update(_ change: (inout SidecarData) -> Void) throws; func plans(on day: Date) -> [PlanBlock]; func replacePlans(on:with:) throws; func outcome(for:on:) ...; func setOutcome(...) throws; func recordBridge(itemID:identifier:) throws; func bridgedIdentifier(for itemID:) -> String? }`. A plan block's `reminderID` holds the Apple identifier (existing `PlanBlock` unchanged); `remap(oldID:newID:)` for phase 2.
- Rules (spec call 9): lookups try `identifier`, then re-match on `externalID`; a missing item never deletes records (no automatic orphan removal); a corrupt or unreadable file throws and is never treated as empty (same rule as `PlannerFile`); atomic write via temp file + replace; unknown future `version` throws.

- [ ] **Step 1:** Tests (temp directory): missing file = empty data; save/load round trip; atomic write leaves the old file intact when the write fails (inject a failing writer); corrupt JSON throws and the file is left untouched; re-match on externalID after the identifier changed; orphan record kept; plans for a day replace only that day; outcome set/clear idempotent by day; ledger record/lookup; future version throws.
- [ ] **Step 2:** Implement; run focused then full suite; commit `feat(kit): item sidecar`.

### Task 5: Router and the write facade

**Files:** Create `Items/ItemRouter.swift`; test `ItemRouterTests.swift`.

**Interfaces:**
- Consumes: `ItemRepository`, `ItemSidecar`, `PlannerStore` (via a small `LocalItemStore` protocol extracted for the methods the views call: add/update/delete/complete/uncomplete/skip/outcome/convert/plans, so the router can be tested with a fake).
- Produces: `@MainActor final class ItemRouter` with the same operation names the views use today (so call sites change mechanically): `add(event:)`, `add(reminder:)` (always Apple, using `DefaultDestinations`), `update`, `delete`, `complete(id:on:)`, `uncomplete(id:)`, `skipEvent(id:on:)` (Apple: `deleteOccurrence`; local: `store.skipEvent`), `skipReminder` (local only; unavailable for Apple), `setEventOutcome` (Apple: sidecar), `convertEvent/convertReminder` (Apple: create the other kind, delete this one, remap sidecar plans), `plans(on:)`, `replacePlans(on:with:)` (sidecar for Apple reminders, store for local), each returning `Result`/throwing a visible `ItemRouterError` the views show in the existing error banner. `enum ItemOrigin { case apple(AppleItemRef), local }` from an id.

- [ ] **Step 1:** Tests with `FakeItemRepository` + a fake local store: routing by id, `add` goes to Apple with the default destination and to local never, errors surface, skipReminder on Apple returns `unsupported`, convert event->reminder creates + deletes and remaps plans, a failing create leaves the original untouched.
- [ ] **Step 2:** Implement; the existing `PlannerStore` tests stay green untouched; commit `feat(kit): ItemRouter`.

### Task 6: `AppleItemRepository`, destinations, access screen (app)

**Files:** Create `AppleItemRepository.swift`, `DefaultDestinationModel.swift`, `AccessRequiredView.swift`; modify `EventKitProvider.swift` (share the lazy store), `AppleSettingsView.swift`, `StarkApp.swift`, `ContentView.swift`.

**Interfaces:**
- Consumes: Tasks 2, 3, 5; Task 1 findings.
- Produces: `final class AppleItemRepository: ItemRepository` (`nonisolated`, `@unchecked Sendable`, EventKit calls `@concurrent`): the EventKit mapping (`RecurrenceDescriptor <-> EKRecurrenceRule`, priority, all-day inclusive last day, date-only reminders via Gregorian `DateComponents` as in `appleReminderDue`), `details` returning the real item with `isWritable` (`allowsContentModifications`), `isInviteeOnly` and `hasUnrepresentableRepeat`, series edits via `event(withIdentifier:)` + span `.futureEvents`, occurrence delete `.thisEvent`, reminder `complete` implemented as the Task 1 spike dictates, batch via `save(commit: false)` then one `commit()` with `reset()` rollback; `@MainActor @Observable DefaultDestinationModel` (default event calendar id and reminder list id in UserDefaults, initial EventKit's `defaultCalendarForNewEvents`/`defaultCalendarForNewReminders`, falls back to the first writable one, publishes a visible error if none); `AccessRequiredView` (plain-words explanation, a button that calls `enable()` while `notAsked`, "Open iOS Settings" while denied/writeOnly).

- [ ] **Step 1:** Add `isWritable: Bool` to `AppleCalendarInfo` (Kit, default true so existing tests compile) and map `EKCalendar.allowsContentModifications` in `EventKitProvider` (test the Kit default and a merge carrying it). Implement the repository, model and screen; add a "Default calendar" and "Default list" pickers (writable ones only) to `AppleSettingsView`.
- [ ] **Step 2:** `StarkApp`/`ContentView`: force the overlay on (`isEnabled` always true; the switch row in Settings is removed or replaced by the access state); when access is not granted, `ContentView` shows `AccessRequiredView` instead of the agenda for Apple data but local items stay visible below it.
- [ ] **Step 3:** Build checks pass; simulator run with idb: first launch asks access from the explained screen, denied state shows the Open Settings row, granted shows the calendar list; read the screenshots. Run the Task 2 contract suite against the real repository on the simulator if feasible (a DEBUG-only runner is fine; do not commit it) and record results in the report.
- [ ] **Step 4:** Commit `feat(app): Apple repository, default destinations, access screen`.

### Task 7: Claude Code bridge writes to Apple

**Files:** Modify `Bridge/ClaudeBridge.swift`, `BridgeBatch.swift`, `StarkApp.swift`, `ContentView.swift`, `Sources/StarkClaudeCore/TodayCommand.swift`, `.claude/commands/stark.md`; tests `ClaudeBridgeTests.swift` (ported), `TodayCommandTests`.

**Interfaces:**
- Consumes: `ItemRepository.addBatch`, `ItemSidecar.recordBridge/bridgedIdentifier`.
- Produces: `ClaudeBridge.handle(_ url: URL) async -> BridgeOutcome` (same outcomes: added(n), alreadyAdded, rejected(reason)); idempotency = every bridge item id already in the ledger is skipped (an item deleted in Apple stays deleted); the replay guard keeps its signature/expiry checks unchanged; a batch is all-or-nothing and writes ledger entries right after the commit succeeds.

- [ ] **Step 1:** Port the 13 `ClaudeBridgeTests` to the async API with `FakeItemRepository` + a temp sidecar; add: re-sending the same file adds nothing; a batch whose save fails adds nothing and records nothing and can be retried; a partial earlier send then a full resend adds only the missing items; signature/replay/size behaviour unchanged (those tests stay as they are).
- [ ] **Step 2:** Implement; `ContentView` awaits `handle` and shows the existing notice banner; `stark-claude today` prints "unavailable until the Mac tool" with exit code 0 and `.claude/commands/stark.md` step 4 says to skip spreading across days until the Mac tool exists (spec call 4).
- [ ] **Step 3:** Simulator check: `xcrun simctl openurl` with a signed URL from `stark-claude add --print-url` lands an event and a reminder in the simulator's Apple Calendar/Reminders; the same URL again shows "Already added"; a tampered URL adds nothing. Commit `feat: bridge writes to Apple`.

### Task 8: Engines learn Apple items (planner, Weekly Review, tags, search, undated)

**Files:** Modify `Apple/AppleMerge.swift`, `Planner/DayPlanModel.swift`, `DayHistory.swift`, `PlanAgenda.swift`, `WeeklyReview.swift`, `TagAutocomplete.swift`, `SearchResults.swift`; tests alongside each.

**Interfaces:**
- Consumes: `AppleSnapshot` (extend `AppleSnapshot.reminders` consumers; add `AppleSnapshot.undatedReminders` and keep dated ones as today), `ItemSidecar` plan blocks keyed by Apple identifier.
- Produces: `mergeAppleItems` unchanged for dated items plus `func undatedAppleReminders(_ snapshot) -> [AgendaItem]` (rows with `displayDate` = distantFuture sorted last, never in the agenda); `DayPlanModel.make(... apple: AppleSnapshot, sidecarPlans:)` listing open Apple reminders in the tray (respecting the selection; undated ones in a new `.noDate` pane of `TrayPane`); `DayHistory.classify`: a plan block whose occurrence is before the series' current due date reads as DONE (series moved past it), an open one before today as MISSED; `WeeklyReview.summary(... apple:)` counting Apple completed one-offs and open items, ignoring repeating-series history (spec call 1); `TagAutocomplete.suggestions` also reads Apple titles/notes; `SearchResults.find` widens Apple coverage to events within two years either side and all reminders, undated included.

- [ ] **Step 1:** Tests first per engine, each with concrete values: planner tray lists an Apple reminder and a "No date" pane lists an undated one; a block for an occurrence earlier than the reminder's current due date is done; Weekly Review counts an Apple completed one-off and does not invent completions for a repeating series; tag suggestions include a tag used only in an Apple title; search finds an undated Apple reminder and an event 18 months ahead.
- [ ] **Step 2:** Implement, keeping every existing test untouched and green; commit per engine (`feat(kit): <engine> reads Apple items`).

### Task 9: Views write through the router

**Files:** Modify `AddItemView.swift`, `EditItemView.swift`, `AgendaView.swift`, `AgendaRow.swift`, `AppleItemDetailView.swift`, `PlannerView.swift`, `WeeklyReviewView.swift`, `SearchView.swift`, `TagSuggestionRow.swift`, `ContentView.swift`, `StarkApp.swift`, `Apple/AppleReadOnly.swift`.

**Interfaces:**
- Consumes: `ItemRouter` (Task 5), `AppleItemRepository.details`, Tasks 7-8.
- Produces: `AgendaItemDetail` gains a third state `.editableApple(AppleItemRef)` (writable item) next to `.edit` (local) and `.readOnly` (non-writable calendar or invitee-only); `isReadOnly` becomes `appleSource != nil && !isWritable` where writability comes from the snapshot (`AppleCalendarInfo.isWritable`, added in Task 6).

- [ ] **Step 1:** `StarkApp` creates the router/sidecar/repository once and injects them; every `store.add*/update*/delete*/complete*/uncomplete*/skip*/setEventOutcome/convert*/replacePlans` call site listed in the research (EditItemView 401-478, AgendaView 277, StarkApp 31, PlannerView 284 and 340, AddItemView 145/157) now calls the router; read sites for planner/review/tags/search pass the Apple snapshot and sidecar plans (Task 8 signatures).
- [ ] **Step 2:** `EditItemView` for an Apple item loads `details(ref)` on open, shows the REAL repeat rule (read-only text when `hasUnrepresentableRepeat`), writes back an `EventPatch`/`ReminderPatch` of only the changed fields, a time change on a series moves only the time of day, hides Delete/Done where `!isWritable`/invitee-only, hides "Skip" for Apple reminders and hides the completion-history sheet for repeating Apple reminders; `AddItemView` shows the destination (calendar/list picker defaulting to the default destination) and no local option; a router error appears in the existing error banner and the sheet stays open.
- [ ] **Step 3:** The agenda checkbox on a writable Apple reminder completes through the router (the `PendingCompletions` undo window is kept; `complete` on a repeating one moves it to its next date; `uncomplete` of a moved series is a no-op with a notice, per the spike); the planner tray/Done/replacePlans work on Apple reminders via the sidecar.
- [ ] **Step 4:** Build checks; simulator run with idb covering the Done-when list (add, complete, edit series title, delete, skip occurrence, timebox + done, bridge URL, "No date" pane); read every screenshot; fix what they show. Commit `feat(app): write Apple items through the router`.

### Task 10: Copy, docs, log, TestFlight

**Files:** Modify `web/public/pages/privacy.html`, `faq.html`, `FAQView.swift`, `web/api/internal/web/web_test.go` (`TestPrivacyDatedAndMentionsData`), `CLAUDE.md`, `docs/ios-feature-notes.md`, the owner's vault notes are not touched here.

- [ ] **Step 1:** Update the privacy test first (Stark now WRITES to Calendar and Reminders when you add, edit, complete or delete in Stark; still no network; bridge items land in Apple; the planner blocks and event outcomes are kept in a small file on the device; `stark-claude today` unavailable), see it fail, then update privacy/FAQ/in-app FAQ; `make test-fast` (Node 24 from `web/.nvmrc`) passes.
- [ ] **Step 2:** `CLAUDE.md`: replace the read-only statements and the "Apple overlay log" opening with the write-through decision; add a dated "Apple write-through log (phase 1)" with Done / Not yet verified on device / Deferred; add the feature-notes paragraph.
- [ ] **Step 3:** Full `swift test`, `make test-fast`, generic iOS Release build for a device; then (controller) merge, push and ship TestFlight with `ios/App/ship.sh` (credentials from `~/.appstoreconnect/env`, never printed) and hand the owner the device checklist: add an event and a reminder in Stark and find them in Apple's apps and on another device; complete a repeating reminder (does it advance); edit a repeating event's title; delete a series; skip one occurrence; timebox and mark done; send a `/stark` batch and resend it; deny access and see the access screen; check Open in Calendar/Reminders; confirm old local items still show.
- [ ] **Step 4:** Commit `docs: Apple write-through phase 1 log`.
