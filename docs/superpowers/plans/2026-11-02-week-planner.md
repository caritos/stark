# Week Planner (day chevrons in the planner) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The planner steps to any day with header chevrons; today and future days are editable, past days are view-only (the old History numbers), and the separate History screen is gone.

**Architecture:** New pure StarkKit pieces (`PlannerDays`, `PlanSession`, a `plannedElsewhere` input to `DayPlanModel.make`, a `Bool` result from `PlannerStore.replacePlans`) carry all the logic and are tested first. In the app, `PlannerView` keeps its single-day editor but its `day` becomes state; the current draft is stashed into a `PlanSession` when leaving a day and restored on return. The read-only body for past days is the history drawing extracted from `DayHistoryView` into `PastDayView`.

**Tech Stack:** Swift 5.9 / SwiftUI, StarkKit SwiftPM package (Swift Testing: `import Testing`, `@Test`, `#expect`), XcodeGen, `xcodebuild`/`devicectl`, `idb` for simulator taps.

**Spec:** `docs/superpowers/specs/2026-11-02-week-planner-design.md`

## Global Constraints

- Work in a git worktree off `main` (branch `week-planner`); commit after each green task. Commit messages end with the two attribution lines the session gives (`Co-Authored-By: ...`, `Claude-Session: ...`).
- Test first for all logic (Red, Green, Refactor). Views (layout, header, styling) are verified by building and by simulator screenshots instead.
- Logic lives in `ios/Sources/StarkKit`; views hold no logic. Views never call `Date()`: `today` is passed down from `ContentView`.
- Swift Testing only. Fast tier: `cd ios && swift test`. Baseline before this work: 590 tests, all passing.
- After adding or deleting any Swift file run `cd ios/App && xcodegen generate` (use the dir that holds `project.yml`) and commit the regenerated `.xcodeproj`.
- `xcodebuild` calls pass `-skipPackagePluginValidation`; never `CODE_SIGNING_ALLOWED=NO`.
- Dark Braun look, one accent (`Colors.accent`), hard edges, `Fonts.mono`; no hard-coded hex. Header/dismiss buttons use the `SquareToolbarButton` family.
- Calendars: `Calendar(identifier: .gregorian)`; step days with `Calendar.date(byAdding: .day,...)`, never `+ 86_400` (DST days have 23 or 25 hours).
- A plan never changes a task's due date, recurrence or completion. Past days are never written.

## Review Focus

- A DST change day (23 or 25 hours): stepping lands on the next calendar day's midnight (`PlannerDaysTests.stepAcrossDSTEnd`).
- Stepping to a day whose month file is not loaded: the planner loads the month first and never shows an empty day silently (`PlannerDaysTests.loadRangeCoversWeekAndLookback`); a failed write is reported, not swallowed (`PlannerStorePlansTests.replacePlansReturnsFalseWhenMonthUnreadable`, `PlanSessionTests.saveAllReportsFailedDays`).
- Midnight passes while the planner is open: an unsaved draft for a day that became past is dropped and never written (`PlanSessionTests.dropLapsedRemovesPastDraftsOnly`, `saveAllSkipsPastDays`).
- The same task occurrence planned on two days in one sitting is prevented, and a recurring series' other occurrence date is not blocked (`DayPlanModelElsewhereTests`).
- Unsaved edits on a day you stepped away from survive stepping back (`PlanSessionTests.stashAndRestore`).

---

### Task 1: `PlannerDays` day helpers

**Files:**
- Create: `ios/Sources/StarkKit/Planner/PlannerDays.swift`
- Test: `ios/Tests/StarkKitTests/PlannerDaysTests.swift`

**Interfaces:**
- Produces:
  - `public enum PlannerDays`
  - `public static func isEditable(_ day: Date, today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool` (true when `startOfDay(day) >= startOfDay(today)`)
  - `public static func step(_ day: Date, by days: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date` (start of the day `days` away)
  - `public static func loadRange(for day: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> ClosedRange<Date>` (lower bound = the earlier of `AgendaWindow.loadRange(around: sunday).lowerBound` and `AgendaWindow.loadRange(around: day).lowerBound`; upper bound = the later of `AgendaWindow.loadRange(around: saturday).upperBound` and `AgendaWindow.loadRange(around: day).upperBound`, where sunday/saturday bound `day`'s week; this is what `DayHistoryView.loadMonths()` computes today, widened to include the day's own range)

- [ ] **Step 1: Write the failing tests** in `PlannerDaysTests` (today = Wed 2026-11-04 10:00, helper `at(y,m,d,h)` like `DayHistoryTests`):
  - `editableFromTodayOn`: Nov 4 (any time) and Nov 5 are editable; Nov 3 23:59 is not.
  - `stepAcrossDSTEnd`: with a calendar whose `timeZone` is `America/Los_Angeles`, `step(at(2026,11,1), by: 1)` equals midnight Nov 2, and `step(at(2026,11,2), by: -1)` equals midnight Nov 1 (a 25-hour day).
  - `stepKeepsStartOfDay`: `step(at(2026,11,4,15), by: 0)` equals midnight Nov 4.
  - `loadRangeCoversWeekAndLookback`: for day Nov 4 the range's `lowerBound == AgendaWindow.loadRange(around: Sunday Nov 1).lowerBound` (or lower) and `upperBound >= AgendaWindow.loadRange(around: Saturday Nov 7).upperBound`; it contains all of `AgendaWindow.loadRange(around: day)`; for a day in Dec 2027 it also contains that day.
- [ ] **Step 2: Run** `cd ios && swift test --filter PlannerDaysTests`. Expected: FAIL (`PlannerDays` not defined).
- [ ] **Step 3: Implement** the three functions in `PlannerDays.swift`. Move the week math from `DayHistoryView.loadMonths()` (Sunday = weekday 1) into `loadRange`; take min lower / max upper with `AgendaWindow.loadRange(around: day)`.
- [ ] **Step 4: Run** the filter again. Expected: PASS.
- [ ] **Step 5: Commit** `git add ios/Sources/StarkKit/Planner/PlannerDays.swift ios/Tests/StarkKitTests/PlannerDaysTests.swift && git commit -m "feat: PlannerDays helpers (editable, step, load range)"` (with attribution lines).

---

### Task 2: One plan per occurrence across days (`DayPlanModel`)

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/DayPlanModel.swift` (`make`, around lines 84-160)
- Test: `ios/Tests/StarkKitTests/DayPlanModelElsewhereTests.swift`

**Interfaces:**
- Produces: `DayPlanModel.make(day:events:reminders:plans:today:plannedElsewhere: [PlanBlock] = [], calendar:)`. Existing call sites compile unchanged (default `[]`).
- Rule: a `plannedElsewhere` block hides the open row it matches (same `matches(plan, item)`: reminder id and same calendar day of `occurrence`) from `tray` and `timed`. Blocks whose `start` day is before `today`'s day are ignored (lapsed). Blocks starting on `day` itself are not "elsewhere" and are ignored here (they come through `plans`).

- [ ] **Step 1: Write the failing tests** (reuse the `at`/`Reminder` helpers from `DayPlanModelTests`):
  - `plannedOnAnotherDayLeavesTray`: open one-off due Nov 5, `plannedElsewhere = [PlanBlock on Nov 6]`; `make(day: Nov 5, ...).tray` has no row for it; with `plannedElsewhere: []` it has one.
  - `lapsedElsewhereBlockDoesNotHide`: the block starts Nov 2 (today Nov 4): the row stays in the tray.
  - `recurringOtherOccurrenceNotHidden`: a daily series' open row has occurrence Nov 4; a block for the same series id with `occurrence` Nov 5 does not hide it, a block with `occurrence` Nov 4 does.
  - `timedTaskPlannedElsewhereLeavesTimeline`: a task due Nov 5 14:00 and planned on Nov 6 is absent from `timed`.
- [ ] **Step 2: Run** `swift test --filter DayPlanModelElsewhereTests`. Expected: FAIL (extra argument).
- [ ] **Step 3: Implement** by filtering `unplanned` through the elsewhere blocks (after the `blocks` match, before `timed`/`tray` are derived).
- [ ] **Step 4: Run** the new tests and `swift test --filter DayPlanModelTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: hide tasks planned on another day from the tray`.

---

### Task 3: `PlanSession` (per-day drafts, save-all) and `replacePlans` result

**Files:**
- Create: `ios/Sources/StarkKit/Planner/PlanSession.swift`
- Modify: `ios/Sources/StarkKit/Planner/PlannerStore.swift` (`replacePlans`, line ~187)
- Test: `ios/Tests/StarkKitTests/PlanSessionTests.swift`, `ios/Tests/StarkKitTests/PlannerStorePlansTests.swift`

**Interfaces:**
- Consumes: `PlanDraft` (`hasChanges`, `blocksToSave`), `PlannerDays.isEditable`.
- Produces:
  - `PlannerStore.replacePlans(on:with:) -> Bool` marked `@discardableResult`; `false` exactly when the month failed to load (the existing silent `guard ... else { return }`), `true` otherwise.
  - `public struct PlanSession` with
    - `init(calendar: Calendar = Calendar(identifier: .gregorian))`
    - `mutating func stash(_ draft: PlanDraft, for day: Date)` (keyed by start of day, replaces)
    - `func draft(for day: Date) -> PlanDraft?`
    - `var changedDays: [Date]` (start-of-day keys whose draft `hasChanges`, ascending) and `var hasChanges: Bool`
    - `mutating func dropLapsed(today: Date)` (removes drafts whose day is not editable)
    - `func plannedElsewhere(of day: Date, saved: [PlanBlock], today: Date) -> [PlanBlock]` (blocks on editable days other than `day`: each stashed draft's `blocksToSave`, plus `saved` blocks on days that have no stashed draft)
    - `func saveAll(today: Date, write: (Date, [PlanBlock]) -> Bool) -> [Date]` (calls `write(day, draft.blocksToSave)` for each changed, editable day in ascending order; returns the days whose `write` returned `false`)

- [ ] **Step 1: Write the failing tests.** Build drafts the way `PlanDraftTests` does (a `DayPlanModel` plus `place`). `PlanSessionTests`:
  - `stashAndRestore`: stash a draft with one placed block for Nov 6 10:00 (time of day in the key ignored); `draft(for: Nov 6 00:00)?.blocks` equals the stashed blocks; `draft(for: Nov 7)` is nil.
  - `changedDaysAscending`: drafts for Nov 7 (changed), Nov 5 (unchanged), Nov 6 (changed) give `changedDays == [Nov 6, Nov 7]`; `hasChanges` true; with none changed false.
  - `dropLapsedRemovesPastDraftsOnly`: drafts for Nov 3 and Nov 5, `dropLapsed(today: Nov 4)` leaves only Nov 5.
  - `plannedElsewhereUsesDraftOverSaved`: saved blocks on Nov 6 and Nov 7, draft stashed for Nov 7 with that block removed; `plannedElsewhere(of: Nov 5, ...)` contains the Nov 6 saved block and the draft's Nov 7 blocks (none) but not the saved Nov 7 block; `plannedElsewhere(of: Nov 6, ...)` does not contain the Nov 6 saved block; a saved block on Nov 2 (past) is never returned.
  - `saveAllWritesOnlyChangedEditableDays`: the writer records `(day, blocks)`; only changed days at or after today are written, in ascending order; an unchanged day and a past day are not.
  - `saveAllReportsFailedDays`: writer returns `false` for Nov 6 only; the result is `[Nov 6]` and Nov 7 was still written.
  - In `PlannerStorePlansTests`, `replacePlansReturnsFalseWhenMonthUnreadable`: copy the setup of the existing test that proves an unreadable month is left untouched; assert the return value is `false` there and `true` for a normal save.
- [ ] **Step 2: Run** `swift test --filter PlanSessionTests` and `--filter PlannerStorePlansTests`. Expected: FAIL (`PlanSession` undefined, result unused / not Bool).
- [ ] **Step 3: Implement** `PlanSession` (a dictionary `[Date: PlanDraft]`) and change `replacePlans` to return the Bool.
- [ ] **Step 4: Run** both filters, then the whole `swift test`. Expected: all PASS.
- [ ] **Step 5: Commit** `feat: PlanSession and replacePlans result`.

---

### Task 4: Extract the past-day drawing into `PastDayView`

**Files:**
- Create: `ios/App/Stark/Stark/PastDayView.swift`
- Modify: `ios/App/Stark/Stark/DayHistoryView.swift` (use the new view; this file is deleted in Task 5)
- Regenerate: the Xcode project (`xcodegen generate`)

**Interfaces:**
- Produces: `struct PastDayView: View { let day: Date; let history: DayHistory }` drawing the banner (`history.allDayEvents`), the hour grid, events, done blocks and open blocks (labelled MISSED; `DayHistoryView`'s `timeline`, `content`, `hourRow`, `eventBlock`, `doneBlock`, `openBlock` and their geometry helpers move here unchanged). It has no header, no toolbar, no store access, and no gestures that edit anything.

- [ ] **Step 1: Move** those pieces from `DayHistoryView.swift` into `PastDayView.swift`; `DayHistoryView.body` renders its own header then `PastDayView(day: day, history: history)`.
- [ ] **Step 2: Run** `xcodegen generate`, then build for the simulator: `xcodebuild -scheme Stark -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -skipPackagePluginValidation build`. Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Verify unchanged look:** run the app in the simulator, open the planner, open History, step back two days, take a screenshot and compare with how it rendered before (done blocks dimmed and checked, MISSED outlined).
- [ ] **Step 4: Commit** `refactor: extract PastDayView from DayHistoryView`.

---

### Task 5: Chevrons, stepping and view-only past days in `PlannerView`

**Files:**
- Modify: `ios/App/Stark/Stark/PlannerView.swift` (`day` property line ~34, `body` toolbar lines ~95-120, `.task` line ~141, `makeModel` line ~167, `dayWord` line ~195, save/close lines ~214-228)
- Delete: `ios/App/Stark/Stark/DayHistoryView.swift`
- Modify: `ios/App/Stark/Stark/ContentView.swift` only if its `PlannerView(day:today:)` call needs a change (it should not)
- Regenerate: the Xcode project (`xcodegen generate`)

**Interfaces:**
- Consumes: `PlannerDays`, `PlanSession`, `DayPlanModel.make(... plannedElsewhere:)`, `DayHistory.make/weekStats/summaryLine/weekLine/minutesText`, `PastDayView`.
- Behavior:
  - `day` becomes `@State private var day: Date` (initialised from the `day:` argument at start of day); add `@State private var session = PlanSession()`.
  - Header (principal toolbar item): `‹` button, the existing title block, `›` button, as flat square buttons in the `SquareToolbarButton` family with accessibility labels "Previous day" and "Next day". Title word: TODAY / TOMORROW as today, else the weekday name. On a past day the date line reads `SUN NOV 1 - VIEW ONLY`.
  - Stepping (`step(_ days: Int)`): stash the current `draft` into `session` (when `PlannerDays.isEditable(day...)`), set `day = PlannerDays.step(day, by: days)`, reset transient state (`lift`, `resize`, `actionBlock`, `timePick`, `autoScroll`, `pane = .today`), then the `.task(id: day)` loads `store.loadMonths(covering: PlannerDays.loadRange(for: day))` and builds the draft from `session.draft(for: day)` or a fresh `PlanDraft(model:saved:)`.
  - `makeModel` passes `plannedElsewhere: session.plannedElsewhere(of: day, saved: store.plans, today: today)`.
  - Past day (`!PlannerDays.isEditable(day, today: today)`): body shows the numbers block (`DayHistory.summaryLine(stats:isToday: false)`, `numbers`, `DayHistory.weekLine(weekStats)` as `DayHistoryView.header` did) above `PastDayView`; no tray, no ✓ toolbar item, no gestures.
  - Remove the History toolbar button, `showHistory` and its `fullScreenCover`.
- [ ] **Step 1: Delete** `DayHistoryView.swift` after moving its `numbers(_:)` helper and header text lines into `PlannerView` (or a small `PastDayHeader` view in `PastDayView.swift`); run `xcodegen generate`.
- [ ] **Step 2: Implement** the behavior above. Keep the work small: no restructuring of the drag code.
- [ ] **Step 3: Build** (same command as Task 4). Expected: BUILD SUCCEEDED.
- [ ] **Step 4: Simulator check with idb screenshots** (iPhone 17 Pro Max): open the planner from Today; tap `›` twice (Wed, then Thu): tray and timeline editable, title shows weekday; place a block on Thursday, step `‹` `‹` back to today and `›` `›` again: the Thursday block is still there (unsaved draft kept); tap `‹` three times to a past day: no tray, no ✓, "VIEW ONLY", numbers or `NO PLAN` shown, done blocks dimmed, no History button anywhere.
- [ ] **Step 5: Commit** `feat: planner steps to any day; past days are view-only; remove History screen` (include the regenerated project).

---

### Task 6: Save, close and midnight across days

**Files:**
- Modify: `ios/App/Stark/Stark/PlannerView.swift` (`save()`, `close()`, `rebuildModel`, scene/today handling)

**Interfaces:**
- Consumes: `PlanSession.stash/changedDays/hasChanges/saveAll/dropLapsed`, `PlannerStore.replacePlans -> Bool`.
- Behavior:
  - ✓ (`save()`): stash the current draft, call `session.saveAll(today: today) { store.replacePlans(on: $0, with: $1) }`; no failures: `dismiss()`; failures: stay open, keep drafts, show an `ErrorBanner` (existing component) naming the failed days ("Could not save the plan for Wed Nov 4"). Each retry rewrites the same blocks (idempotent).
  - ✕ (`close()`): stash the current draft; if `session.hasChanges` show the existing "Discard changes?" dialog (message names how many days have unsaved changes when more than one), else dismiss.
  - The ✓ button is disabled while nothing changed in any day (`session.hasChanges` after stashing the current draft) and hidden on past days.
  - `today` is a constant of the view's input: when `ContentView` passes a new `today` after midnight, call `session.dropLapsed(today:)`, and if the viewed `day` is now past, drop its `draft` and show the view-only body.
- [ ] **Step 1: Implement** the behavior above.
- [ ] **Step 2: Build** for the simulator. Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Simulator check:** edit Wed and Thu, press ✓: both saved (reopen the planner on each day to confirm), planner closed; edit two days and press ✕: dialog appears, Discard closes and nothing was saved; the task placed on Wed is absent from Thu's tray until removed from Wed.
- [ ] **Step 4: Commit** `feat: save and discard across planned days`.

---

### Task 7: Docs, full verification and device build

**Files:**
- Modify: `CLAUDE.md` (repo root: the "Plan history" paragraph and the Timeboxing log), `web/public/pages/faq.html` and `web/public/pages/index.html` only if they describe a History screen or say plans exist only for today and tomorrow (search `grep -n -i 'history\|tomorrow' web/public/pages/*.html`), `docs/superpowers/specs/2026-11-02-week-planner-design.md` (nothing to change unless the build diverged)

- [ ] **Step 1:** Update `CLAUDE.md`: replace the "Plan history" paragraph with how past days work in the planner (`DayHistory`, `PastDayView`, `PlannerDays`, `PlanSession`), change "Plans exist only for today and tomorrow" to the new rule, and add a dated "Week planner (2026-11-02)" entry to the Timeboxing log with Done, Not yet verified on device (real touch, VoiceOver for the chevrons and "view only", Mac Catalyst runtime) and Deferred (themed days, remembering the last pane).
- [ ] **Step 2:** If the website pages mention the History screen or the two-day limit, correct the copy (plain ASCII, keep the Braun look) and run `cd web && make test-fast`. Expected: PASS.
- [ ] **Step 3: Full suite on a clean rebuild:** `cd ios && swift package clean && swift test`. Expected: all tests PASS (590 plus the new ones).
- [ ] **Step 4: Build for a physical device:** `xcodebuild -scheme Stark -destination 'generic/platform=iOS' -skipPackagePluginValidation build`. Expected: BUILD SUCCEEDED. Install with `ios/App/deploy.sh` only when the iPhone is connected, and record "confirmed on device" separately from "unit-tested".
- [ ] **Step 5: Commit** `docs: week planner log and copy`; then use superpowers:finishing-a-development-branch (merge `week-planner` into `main` locally after the full suite passes on the merged result, then push `main` and say so in a line).
