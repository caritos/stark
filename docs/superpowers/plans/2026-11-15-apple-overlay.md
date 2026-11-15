# Apple Calendar and Reminders Overlay (read-only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Apple Calendar events and Apple Reminders, read-only, in Stark's agenda, month/year density and Search, with a Settings screen to turn it on and pick calendars.

**Architecture:** StarkKit (no EventKit import, tested with `swift test`) gets plain value types, a pure `mergeAppleItems`, density/search inclusion and a selection type. One app-layer file imports EventKit (`EventKitProvider`); an `@MainActor @Observable AppleOverlayModel` holds access state, selection and the latest snapshot. Apple rows are synthetic, non-persisted `Event`/`Reminder` values inside `AgendaItem`s carrying `appleSource`, and one gate (`appleSource != nil`) keeps them away from `PlannerStore`.

**Tech Stack:** Swift 5.9 package + SwiftUI iOS 17.0, Swift Testing, EventKit, idb for simulator runs.

**Spec:** `docs/superpowers/specs/2026-11-15-apple-overlay-design.md` (includes the "Calls made after the builder check" section; both are binding).

## Global Constraints

- Work in a git worktree (`EnterWorktree`); commit after each green task. Do not push or ship to TestFlight without asking (push of the merged, green main is fine per the global rules).
- iOS deployment target stays 17.0; StarkKit keeps `.iOS(.v17)`, `.macOS(.v14)`; StarkKit must not `import EventKit`.
- Swift Testing only (`import Testing`, `@Test`, `#expect`). Tests first, see them fail for the right reason.
- The Xcode project has no `project.yml`; it uses synchronized root groups (3 in `project.pbxproj`), so new Swift files in `ios/App/Stark/Stark/` need no pbxproj edit. Info.plist keys go in the seed `ios/App/Stark/Info.plist` (see `~/.claude/docs/ios-infoplist-keys.md`); confirm they exist in the built product.
- Theme: `Theme.swift` tokens only (hard edges, one accent, no hardcoded hex). A calendar colour is data and appears only as the small dot.
- Never persist EventKit identifiers in `.ics` or absolute paths. UserDefaults holds only the on/off flag and the excluded calendar ids.
- Overlay is off by default; the permission request happens only from Settings, never at launch.
- Read the real device with `ios/App/deploy.sh`; never print secrets.

## Done when

- `cd ios && swift test` passes (new tests included); Mac Catalyst and generic-iOS `xcodebuild` builds compile.
- Simulator run with idb screenshots (seeded made-up Apple events and reminders): permission flow, calendar toggles, Apple + Stark rows mixed in the agenda, month dots, a Search hit, read-only detail.
- On the iPhone: real Apple items show, deselecting a calendar hides it, an edit made in Apple Calendar appears after returning to Stark. Logged as "confirmed on device", separate from "unit-tested".
- Copy updated (in-app FAQ, `web/public/pages/faq.html`, `privacy.html`, `TestPrivacyDatedAndMentionsData`); `cd web && make test-fast` passes.
- NOT part of done: writes to Apple data, planner/Weekly Review/bridge inclusion, undated reminders, TestFlight.

## Review Focus

- A recurring Apple event shows once per occurrence (EventKit expansion), never expanded again by Stark.
- An Apple event ending exactly at midnight does not spawn a row on the next day; a multi-day all-day event gets one row per day.
- An open Apple reminder due 2 years ago is not shown; one due 40 days ago is pinned to today with "40 days overdue".
- Tapping, swiping, long-pressing, or opening from Search an Apple row never reaches `PlannerStore`.
- Permission denied or write-only: Settings shows a clear state, the agenda shows only Stark items, no crash.
- A calendar removed after being excluded: its id is ignored; a newly created calendar appears by itself.

## File Structure

- Create `ios/Sources/StarkKit/Apple/AppleModels.swift`: `AppleCalendarInfo`, `AppleCalendarEvent`, `AppleReminder`, `AppleSource`, `AppleAccess`, `AppleSnapshot`.
- Create `ios/Sources/StarkKit/Apple/AppleMerge.swift`: `mergeAppleItems`.
- Create `ios/Sources/StarkKit/Apple/AppleSelection.swift`: excluded-ids rule.
- Modify `ios/Sources/StarkKit/Planner/AgendaBuilder.swift` (`AgendaItem.appleSource`), `AgendaDensity.swift`, `SearchResults.swift`.
- Create `ios/App/Stark/Stark/EventKitProvider.swift`, `AppleOverlayModel.swift`, `AppleSettingsView.swift`, `AppleItemDetailView.swift`.
- Modify `AgendaView.swift`, `AgendaRow.swift`, `MonthGridView.swift`, `YearView.swift`, `SearchView.swift`, `ContentView.swift`, `SettingsView.swift`, `StarkApp.swift`, `FAQView.swift`, `ios/App/Stark/Info.plist`, the Catalyst entitlements (create the file if none and wire it in `project.pbxproj`).
- Tests: `ios/Tests/StarkKitTests/AppleMergeTests.swift`, `AppleDensitySearchTests.swift`, `AppleSelectionTests.swift`.

---

### Task 1: Value types and `AgendaItem.appleSource`

**Files:** Create `Apple/AppleModels.swift`; modify `AgendaBuilder.swift`; test `AppleMergeTests.swift` (first cases).

**Interfaces:**
- Produces:
  - `struct AppleCalendarInfo: Equatable, Identifiable, Sendable { id: String; title: String; accountName: String; colorHex: String?; isReminderList: Bool }`
  - `struct AppleSource: Equatable, Sendable { calendarID: String; calendarTitle: String; colorHex: String?; isReminder: Bool }`
  - `struct AppleCalendarEvent: Equatable, Sendable { id: String; title: String; notes: String?; location: String?; url: String?; start: Date; end: Date?; isAllDay: Bool; calendar: AppleCalendarInfo }`
  - `struct AppleReminder: Equatable, Sendable { id: String; title: String; notes: String?; due: Date?; dueHasTime: Bool; isCompleted: Bool; completedAt: Date?; priority: Int?; calendar: AppleCalendarInfo }`
  - `enum AppleAccess: Equatable, Sendable { case notAsked, granted, denied, writeOnly }`
  - `struct AppleSnapshot: Equatable, Sendable { events: [AppleCalendarEvent]; reminders: [AppleReminder] }`
  - `AgendaItem.appleSource: AppleSource?` (stored, default nil in `init`, not part of `id`).

- [ ] **Step 1:** Write `appleSourceDefaultsToNil` (an `AgendaItem` built with the existing init has `appleSource == nil`) and `appleSourceKeptByInit`. Run `cd ios && swift test --filter AppleMergeTests`; expect compile failure (types missing).
- [ ] **Step 2:** Add the types and the `appleSource` property with an `init` parameter defaulting to nil.
- [ ] **Step 3:** Run the filter and then the full `swift test`; all pass (existing call sites must compile unchanged).
- [ ] **Step 4:** Commit `feat(kit): Apple overlay value types`.

### Task 2: `mergeAppleItems`

**Files:** Create `Apple/AppleMerge.swift`; test `AppleMergeTests.swift`.

**Interfaces:**
- Consumes: Task 1 types; `sortAgendaItems(_:calendar:)`, `spanDays(of:calendar:)` (internal, same module), `AgendaWindow.overdueLookbackDays`.
- Produces: `public func mergeAppleItems(_ items: [AgendaItem], snapshot: AppleSnapshot, in range: ClosedRange<Date>, today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> [AgendaItem]`. `range` is the display range; reminders are additionally considered back `overdueLookbackDays` from today.

Behavior to implement (write each as its own test first, with fixed dates and a fixed `Calendar`):
- Each `AppleCalendarEvent` becomes `.event(Event(id: "apple-<id>", ... recurrence: nil))`, `occurrence == displayDate ==` that day's occurrence start, `isOverdue == false`, `appleSource` set, `AgendaItem.id` starts with `apple-`. Tests: `timedEventKeepsStartAndEnd`, `idNeverCollidesWithStarkUUID`, `eventOutsideRangeDropped`.
- Multi-day and all-day: one row per day via `spanDays`; test `threeDayAllDayEventGivesThreeRows`; `eventEndingAtMidnightDoesNotSpillToNextDay` (end exactly next 00:00 -> rows only on the start day).
- Reminder with `due` in range, not completed: `.reminder(Reminder(id: "apple-<id>", dueDate: due, ... recurrence: nil))`; `dueHasTime == false` means date-only like Stark's date-only reminders (reuse however Stark marks a date-only due date; read `Reminder` usage in `AgendaRow`). Tests: `reminderOnItsDueDay`, `dateOnlyReminderHasNoTimeOfDay`.
- Overdue: due before today and within lookback -> `isOverdue`, `displayDate` = start of today, `occurrence` = due; due before the lookback -> dropped; test names `overdueReminderPinnedToToday`, `reminderOlderThanLookbackNotShown`.
- Completed reminder shows on its due day when in range, never overdue: `completedReminderOnDueDay`.
- Undated reminder (`due == nil`) is dropped: `undatedReminderNotShown`.
- Result is the input items plus Apple rows, re-sorted with `sortAgendaItems`; Stark items untouched: `starkItemsUnchangedAndOrdered`.
- [ ] Steps: failing tests -> run (fail) -> implement -> run (pass) -> commit `feat(kit): mergeAppleItems`.

### Task 3: Density and Search include Apple items

**Files:** Modify `AgendaDensity.swift`, `SearchResults.swift`; test `AppleDensitySearchTests.swift`.

**Interfaces:**
- Consumes: `mergeAppleItems`.
- Produces: an optional `apple: AppleSnapshot = AppleSnapshot(events: [], reminders: [])` parameter on `dayDensity`, `gridDensity`, `yearDensity` and `densityCounts` (merged after `buildAgendaItems`, before counting); `SearchResults.find(events:reminders:apple:query:today:)` with `apple` defaulting to empty, matching title, notes and location case-insensitively like Stark items and returning rows with `appleSource` set and `displayDate` = the item's own date.

- [ ] **Step 1:** Tests: `gridDensityCountsAppleEventsAndReminders` (one Apple event on the 10th adds one to `events` for that ISO date), `yearDensityCountsApple`, `existingCallsUnchangedWithEmptySnapshot` (all existing density tests pass untouched), `searchFindsAppleEventByTitle`, `searchFindsAppleReminderByNotes`, `searchResultsSortedNewestFirstWithStarkItems`.
- [ ] **Step 2:** Run (fail), implement, run full `swift test` (pass), commit `feat(kit): density and search include Apple items`.

### Task 4: Calendar selection

**Files:** Create `Apple/AppleSelection.swift`; test `AppleSelectionTests.swift`.

**Interfaces:**
- Produces: `struct AppleSelection: Equatable, Sendable { var excludedIDs: Set<String>; func isShown(_ calendarID: String) -> Bool; func pruned(toExisting ids: Set<String>) -> AppleSelection; func filtered(_ snapshot: AppleSnapshot) -> AppleSnapshot }`.

- [ ] **Step 1:** Tests: `emptySelectionShowsEverythingIncludingNewCalendars`, `excludedCalendarHidden`, `prunedDropsRemovedCalendarIDs`, `filteredRemovesItemsOfExcludedCalendars`.
- [ ] **Step 2:** Run (fail), implement, run (pass), commit `feat(kit): AppleSelection`.

### Task 5: EventKit provider and overlay model (app layer)

**Files:** Create `EventKitProvider.swift`, `AppleOverlayModel.swift`.

**Interfaces:**
- Consumes: Tasks 1 and 4.
- Produces:
  - `protocol AppleItemProvider: Sendable { func accessState() -> AppleAccess; func requestAccess() async -> AppleAccess; func calendars() -> [AppleCalendarInfo]; func fetch(events: ClosedRange<Date>, reminders: ClosedRange<Date>) async throws -> AppleSnapshot }`
  - `final class EventKitProvider: AppleItemProvider` (the only file importing EventKit; one shared `EKEventStore`; `requestFullAccessToEvents`/`requestFullAccessToReminders`; event fetch chunked in windows of at most 4 years; reminders via `predicateForIncompleteReminders` plus `predicateForCompletedReminders`, mapped to `AppleReminder` with `dueHasTime` from `dueDateComponents.hour != nil`; colour via `cgColor` to hex).
  - `@MainActor @Observable final class AppleOverlayModel { var isEnabled: Bool; var access: AppleAccess; var calendars: [AppleCalendarInfo]; var selection: AppleSelection; private(set) var snapshot: AppleSnapshot; init(provider: AppleItemProvider, defaults: UserDefaults = .standard); func enable() async; func disable(); func setShown(_ id: String, _ shown: Bool); func reload(display: ClosedRange<Date>, today: Date) async }`
- Behavior: `reload` fetches events over `display` and reminders over `display.lowerBound - overdueLookbackDays ... display.upperBound`, applies `selection.filtered`, and keeps the previous snapshot until the new one lands. It observes `.EKEventStoreChanged` and triggers a reload of the last requested range. When `access != .granted` the snapshot is empty. `isEnabled` and `excludedIDs` persist in UserDefaults.

- [ ] **Step 1:** `AppleOverlayModel` stays in the app target (it holds no logic the Kit tests above do not cover: merging, selection and filtering are Kit code), so it is verified by build plus the simulator run in Task 9.
- [ ] **Step 2:** Implement both files; add `NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription` to `ios/App/Stark/Info.plist` (copy: "Stark shows your Apple Calendar events and Reminders in its agenda. They are read on this device and never copied or sent anywhere.").
- [ ] **Step 3:** `xcodebuild` for the generic iOS Simulator destination compiles; commit `feat(app): EventKit provider and overlay model`.

### Task 6: Wire the overlay into agenda, grid, year, search

**Files:** Modify `ContentView.swift`, `StarkApp.swift`, `AgendaView.swift`, `MonthGridView.swift`, `YearView.swift`, `SearchView.swift`.

- [ ] **Step 1:** Create the model in `StarkApp`, inject with `.environment(...)`.
- [ ] **Step 2:** Beside every `store.loadMonths(covering:)` call that moves the window (`ContentView` lines ~293 and ~327, `MonthGridView` ~170, `YearView` ~82) also `await model.reload(display:today:)` for the same range, so the window never shows a range before its Apple data is fetched. Reload on `scenePhase == .active`.
- [ ] **Step 3:** `AgendaView.makeSections`: after `applyPlans`, `mergeAppleItems(planned, snapshot: model.snapshot, in: range, today: now)`, then `groupAgendaByDay`. `MonthGridView` and `YearView` pass `apple: model.snapshot` to `gridDensity`/`yearDensity`. `SearchView` passes it to `SearchResults.find`.
- [ ] **Step 4:** Build for generic iOS Simulator; `swift test` still green; commit `feat(app): show Apple items in agenda, grid, year, search`.

### Task 7: Read-only rows, gate and detail

**Files:** Modify `AgendaRow.swift`, `AgendaView.swift`, `SearchView.swift`; create `AppleItemDetailView.swift`.

**Interfaces:**
- Produces: `extension AgendaItem { var isReadOnly: Bool { appleSource != nil } }` in the Kit (with a test `appleItemIsReadOnlyStarkItemIsNot` added to `AppleMergeTests`).

- [ ] **Step 1:** In `AgendaRowView`, an Apple row shows a source marker (a 6 pt calendar-colour dot and the calendar title in the secondary style) and a disabled-looking marker column (no checkbox tap: render the marker but `AgendaRowTargets` omits the checkbox button for read-only rows).
- [ ] **Step 2:** One gate in `AgendaView` and `SearchView`: row tap on a read-only item presents `AppleItemDetailView` (title, time, location, URL, notes, calendar name; no edit or complete controls) instead of the Stark detail/edit sheet; swipe actions, context menu, plan, convert and skip are not attached when `item.isReadOnly`. Never pass a read-only item to any `store.*` call.
- [ ] **Step 3:** "Open in Calendar"/"Open in Reminders" link using `calshow:<timeIntervalSinceReferenceDate>` and the Reminders scheme; verify on the device in Task 9; if neither opens the app, remove the link.
- [ ] **Step 4:** Build; simulator check via idb that tapping an Apple row opens the read-only detail and the checkbox does nothing; commit `feat(app): read-only Apple rows and detail`.

### Task 8: Settings screen, Catalyst entitlements

**Files:** Create `AppleSettingsView.swift`; modify `SettingsView.swift`, the Catalyst entitlements and `project.pbxproj` (only if no entitlements file exists).

- [ ] **Step 1:** Settings row "Apple Calendar and Reminders" opens `AppleSettingsView`: an on/off toggle (turning on calls `model.enable()`, which requests access); when `denied`/`writeOnly`, a row that opens `UIApplication.openSettingsURLString`; when granted, calendars and lists grouped by `accountName`, a toggle each calling `model.setShown`.
- [ ] **Step 2:** Add `com.apple.security.personal-information.calendars` and the reminders equivalent to the Catalyst sandbox entitlements; verify with the Mac Catalyst build command from `docs/superpowers/plans/2026-09-22-mac-catalyst-target.md` (Global Constraints) that it compiles.
- [ ] **Step 3:** Both builds succeed; commit `feat(app): Apple overlay settings and Catalyst entitlements`.

### Task 9: Verify in the simulator and on the iPhone

- [ ] **Step 1:** Seed the iPhone 17 Pro Max simulator's Calendar and Reminders with made-up items (a timed event today, an all-day multi-day event, a recurring event, a reminder due today, one due 10 days ago, one due 2 years ago, an undated one); run the app and capture idb screenshots of: Settings flow with the permission prompt, calendars toggled, the agenda mixing Apple and Stark rows, month dots, Search for an Apple title, the read-only detail. Read each screenshot and confirm against Review Focus (the 2-year-old and undated reminders absent, the recurring event once per occurrence).
- [ ] **Step 2:** `ios/App/deploy.sh`; on the phone confirm the real items show, deselecting a calendar hides it, and an edit in Apple Calendar appears after returning to Stark. Record results in the log (Task 10) as "confirmed on device" only for what was actually seen.

### Task 10: Copy, docs and log

**Files:** Modify `FAQView.swift`, `web/public/pages/faq.html`, `web/public/pages/privacy.html`, `web/api/internal/web/web_test.go` (`TestPrivacyDatedAndMentionsData`), `CLAUDE.md`, `docs/ios-feature-notes.md`.

- [ ] **Step 1:** Update `TestPrivacyDatedAndMentionsData` first for a new privacy date (NOVEMBER 2026) and a heading/phrase about Apple Calendar and Reminders; run `cd web && make test-fast` (Node 24), see it fail.
- [ ] **Step 2:** Update the privacy page (reads calendar and reminder data on the device when turned on; no network call; nothing copied), the web FAQ and the in-app FAQ; run `make test-fast` (pass). Check `PrivacyInfo.xcprivacy` needs no new declaration; if it does, add it.
- [ ] **Step 3:** In `CLAUDE.md`: replace the "no EventKit" statements (Storage paragraph and the note at the top) with the 2026-11-15 decision, link the spec and plan, add a dated "Apple overlay log" with Done / Not yet verified on device / Deferred (undated reminders, write-through, retire local store, Mac CLI, calendar sets from #120). Add a paragraph to `docs/ios-feature-notes.md`.
- [ ] **Step 4:** Run the full `cd ios && swift test` and `cd web && make test-fast`; commit `docs: Apple overlay copy and log`.
