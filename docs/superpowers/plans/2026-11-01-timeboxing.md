# Timeboxing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A full-screen "Plan" view (for today or tomorrow) where open tasks are dragged from a tray onto a day timeline as resizable blocks, saved as plan entries that never change a task's due date.

**Architecture:** A new `PlanBlock` value type is persisted as an `X-STARK-PLAN` component in the month `.ics` file of the planned day, owned by `PlannerStore`. All rules (snapping, overlap, tray membership, merging plans into agenda rows) are pure StarkKit functions tested with Swift Testing; the SwiftUI app target only draws the planner and handles gestures.

**Tech Stack:** Swift 5.9 / SwiftUI, StarkKit SwiftPM package (`swift test` in `ios/`), Swift Testing (`@Test`, `#expect`), `xcodebuild` for the app (app files are in a file-system-synchronized group: no project edits for new Swift files).

**Spec:** `docs/superpowers/specs/2026-11-01-timeboxing-design.md`

## Global Constraints

- Work in a git worktree on a feature branch (`git worktree add .claude/worktrees/timeboxing -b timeboxing`), absolute paths, one small commit per green step. Merge to `main` locally only after the full suite passes on the merged result.
- TDD: failing test first for every StarkKit change; UI-only layout changes are verified visually / on device.
- Every `xcodebuild` call passes `-skipPackagePluginValidation`. Tests: `cd ios && swift test`.
- Default block length **30 minutes**; snap **15 minutes**; blocks stay inside one calendar day and cannot cross midnight; blocks cannot overlap each other (they may overlap events).
- A plan entry never changes a reminder's `dueDate`, `recurrence` or `exceptionDates`.
- Month files with no plan entries must serialize **byte-identically** to today's output (existing fixtures must still pass untouched).
- A missing file means no plans; a real read failure throws and is never treated as empty. Never persist absolute paths.
- Use `Calendar(identifier: .gregorian)` for day math; never build day bounds from `DateMath.date(from:)` (it is local noon).
- Theme: `Colors`, `Spacing`, `Fonts.mono` only; hard edges, one accent, no hardcoded hex. Sheets force `.preferredColorScheme(.dark)`; dismiss/commit buttons are `SquareToolbarButton`.
- Anything that moves a window or reads plans calls `store.loadMonths(covering:)` first.
- Mac Catalyst target must still build; drag must work with a pointer.

## Review Focus

- A task is planned, then deleted: the plan entry is dropped, no crash, no phantom row.
- A recurring task's carried miss is planned, then completed: the miss and the planned copy are both gone (nothing resurfaces).
- A plan whose day has passed: ignored, task back on its normal row only.
- Planning a task already due that day at a set time: one row, planned time shown, original due time as secondary text, never two rows.
- A drop that would overlap another block or cross midnight: refused or clamped, never produces overlapping/corrupt blocks.
- A month file holding only plan entries (its last reminder moved or deleted): not deleted, not left unreadable.

---

### Task 1: `PlanBlock` model and ICS round trip

**Files:**
- Create: `ios/Sources/StarkKit/Models/PlanBlock.swift`
- Modify: `ios/Sources/StarkKit/ICS/ICSParser.swift`, `ios/Sources/StarkKit/ICS/ICSSerializer.swift`
- Test: `ios/Tests/StarkKitTests/PlanBlockICSTests.swift`

**Interfaces:**
- Produces: `public struct PlanBlock: Equatable, Codable, Identifiable, Sendable { id: String; reminderID: String; occurrence: Date; start: Date; minutes: Int; init(id: String = UUID().uuidString, reminderID: String, occurrence: Date, start: Date, minutes: Int) ; var end: Date }`; `ICSParseResult.plans: [PlanBlock]` (init gains `plans: [PlanBlock] = []` as the last parameter); `ICSSerializer.serialize(events:reminders:plans:)` with `plans: [PlanBlock] = []`.

- [ ] **Step 1: Write failing tests** in `PlanBlockICSTests`: `roundTrip` (serialize one reminder + one block, parse, `#expect(parsed.plans == [block])`); `noPlansIsByteIdentical` (serialize with `plans: []` equals `serialize(events:reminders:)` of an existing fixture string); `malformedPlanWarns` (an `X-STARK-PLAN` block missing `X-STARK-PLAN-REMINDER` yields `plans.isEmpty` and one warning containing `"X-STARK-PLAN"`); `unknownComponentIgnored` (a file with an unrelated `BEGIN:X-OTHER` block still parses its events).
- [ ] **Step 2: Run** `cd ios && swift test --filter PlanBlockICSTests` — expect compile failure (`PlanBlock` undefined).
- [ ] **Step 3: Implement** `PlanBlock` and the codec. Component shape: `BEGIN:X-STARK-PLAN`, `UID:<id>`, `X-STARK-PLAN-REMINDER:<reminderID>`, `X-STARK-PLAN-OCCURRENCE:<ICSDateFormat date-time>`, `DTSTART:<start>`, `X-STARK-PLAN-MINUTES:<n>`, `END:X-STARK-PLAN`, written after all VTODOs. Reuse `ICSDateFormat` and the existing `properties(_:)` helper; strip newlines from ids as `X-STARK-SERIES` does. Parser: add the new BEGIN/END pair to the same block loop; a malformed block appends the warning `"skipped malformed X-STARK-PLAN block"`.
- [ ] **Step 4: Run** the filter, then full `swift test` — expect all pass (existing fixtures untouched).
- [ ] **Step 5: Commit** `feat(ios): PlanBlock model and X-STARK-PLAN ICS codec`.

### Task 2: Store and file persistence of plans

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/PlannerFile.swift`, `ios/Sources/StarkKit/Planner/PlannerStore.swift`
- Test: `ios/Tests/StarkKitTests/PlannerStorePlansTests.swift`

**Interfaces:**
- Consumes: Task 1's `PlanBlock`, `ICSParseResult.plans`, `serialize(events:reminders:plans:)`.
- Produces: `PlannerFile.saveMonth(_:events:reminders:plans:)` (`plans` defaults `[]`); `PlannerStore.plans: [PlanBlock]` (`@Published private(set)`); `PlannerStore.replacePlans(on day: Date, with blocks: [PlanBlock])` replacing every block whose `start` falls on `day` and persisting that day's month; `PlannerStore.plans(on day: Date) -> [PlanBlock]`.

- [ ] **Step 1: Write failing tests** (use the existing in-memory/temporary-directory pattern from `PlannerStore` tests): `replaceThenReload` (replace, build a new store on the same directory, `loadMonths`, plans equal); `replaceOnlyAffectsThatDay`; `deleteReminderDropsItsPlans` (add a reminder, plan it, `deleteReminder`, `#expect(store.plans.isEmpty)`); `monthWithOnlyPlansKeepsFile` (month has a plan and no events/reminders: file still exists after a save and reloads the plan — Review Focus); `emptyPlansLeavesFileUntouched` (a month with no plans is byte-identical on disk to before).
- [ ] **Step 2: Run** the filter — expect FAIL.
- [ ] **Step 3: Implement.** `PlannerFile.save` passes `plans` through. `PlannerStore` keeps `monthPlans: [YearMonth: [PlanBlock]]` filled in `loadMonth`, flattened in `rebuild()` the same deterministic way as reminders; `persistMonth` deletes the file only when events, reminders **and** plans are all empty. `deleteReminder(id:)` also removes blocks with that `reminderID` and persists their months.
- [ ] **Step 4: Run** filter then full suite — pass.
- [ ] **Step 5: Commit** `feat(ios): PlannerStore persists plan blocks per month`.

### Task 3: Placement rules (`PlanLayout`)

**Files:**
- Create: `ios/Sources/StarkKit/Planner/PlanLayout.swift`
- Test: `ios/Tests/StarkKitTests/PlanLayoutTests.swift`

**Interfaces:**
- Produces (all `public enum PlanLayout` statics, `calendar` defaults gregorian): `snap(_ date: Date) -> Date` (nearest 15 min); `defaultMinutes = 30`; `minMinutes = 15`; `place(_ block: PlanBlock, among others: [PlanBlock], day: Date) -> PlanBlock?` returns the block clamped inside `day`, snapped, and moved to the nearest free slot, or `nil` if no room; `resized(_ block: PlanBlock, toMinutes: Int, among others: [PlanBlock], day: Date) -> PlanBlock` (snap, at least `minMinutes`, shrinks/grows only until the next block or midnight).

- [ ] **Step 1: Write failing tests**: `snapsToQuarterHour` (9:07 → 9:00, 9:08 → 9:15); `clampsAtMidnight` (a 30 min block dropped at 23:50 starts 23:30); `overlapMovesToNearestFreeSlot` (blocks 9:00–9:30 and 9:30–10:00 exist, drop at 9:15 → 10:00; drop at 9:15 when 8:30–9:00 is free and 10:00 is nearer-equal prefers later — assert the exact result you implement and keep it); `refusedWhenDayFull` (returns nil); `resizeStopsAtNextBlock`; `resizeNeverBelowFifteen`; `eventsDoNotBlockPlacement` (only `PlanBlock`s are inputs).
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** by scanning free intervals between sorted blocks; tie-break equal distance toward the earlier slot (document it in the doc comment and pin it in a test).
- [ ] **Step 4: Run** — pass. **Step 5: Commit** `feat(ios): PlanLayout snapping, overlap and resize rules`.

### Task 4: Tray and timeline membership (`DayPlanModel`)

**Files:**
- Create: `ios/Sources/StarkKit/Planner/DayPlanModel.swift`
- Test: `ios/Tests/StarkKitTests/DayPlanModelTests.swift`

**Interfaces:**
- Consumes: `buildAgendaItems`, `AgendaItem`, `PlanBlock`, `AgendaWindow`.
- Produces: `public struct DayPlanModel { public let day: Date; public let tray: [AgendaItem]; public let timed: [AgendaItem]; public let allDayEvents: [AgendaItem]; public let events: [AgendaItem]; public let blocks: [PlanBlock] }` and `public static func make(day: Date, events: [Event], reminders: [Reminder], plans: [PlanBlock], today: Date, calendar: Calendar = gregorian) -> DayPlanModel`.

Rules: build items with `buildAgendaItems` over `AgendaWindow.loadRange(around: day)`, then add every open **one-off** reminder from `reminders` whose date lies outside that range (past or future, undated excluded). `tray` = open (not completed) reminder items not already planned for `day` and not in `timed`. `timed` = open reminder items whose `displayDate` is on `day`, is not overdue, and has a time of day other than 00:00. `events`/`allDayEvents` = event items on `day` split by `isAllDay`. `blocks` = plans whose `start` is on `day` and whose reminder still has an open matching item (same `reminderID`, same occurrence day); others are dropped from the result (not deleted from the store).

- [ ] **Step 1: Write failing tests**: `trayHoldsOverdueFutureAndUndated…` (overdue one-off, due-in-three-weeks one-off, all-day one-off due on `day` are in `tray`); `timedTaskDueThatDayIsOnTimelineNotTray`; `recurringMissIsInTrayOnce` (a daily reminder with three misses yields exactly one tray item, the oldest, `isOverdue`); `recurringTimedOccurrenceDueThatDayIsTimed`; `plannedTaskLeavesTray`; `completedTaskNeverShown`; `orphanPlanIgnored` (plan for a reminder no longer present, and plan whose carried miss was completed, yield no block — Review Focus); `lapsedPlanIgnored` (`day` before `today`).
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** per the rules above. **Step 4: Run** — pass. **Step 5: Commit** `feat(ios): DayPlanModel tray and timeline membership`.

### Task 5: Editing a plan (`PlanDraft`)

**Files:**
- Create: `ios/Sources/StarkKit/Planner/PlanDraft.swift`
- Test: `ios/Tests/StarkKitTests/PlanDraftTests.swift`

**Interfaces:**
- Consumes: `DayPlanModel`, `PlanLayout`.
- Produces: `public struct PlanDraft { public private(set) var blocks: [PlanBlock]; public var hasChanges: Bool; init(model: DayPlanModel) ; public mutating func place(_ item: AgendaItem, at start: Date) -> Bool; public mutating func move(id: String, to start: Date) -> Bool; public mutating func resize(id: String, toMinutes: Int); public mutating func remove(id: String) }`. `place` builds a `PlanBlock(reminderID, occurrence: item.occurrence, start, minutes: PlanLayout.defaultMinutes)` for reminder items only and returns `false` if refused or the item is an event. Moving a task that is already `timed` creates a block for it (its due time is not touched).

- [ ] **Step 1: Write failing tests**: `placeUsesDefaultThirty`; `placeEventIsRefused`; `movingTimedTaskCreatesBlockAndLeavesReminder` (reminder value unchanged); `removeReturnsToTray` (apply `DayPlanModel.make` to blocks after remove); `hasChangesFalseUntilEdited`; `overlappingMoveIsRefusedOrShifted` consistent with Task 3.
- [ ] **Step 2–5:** fail, implement, pass, commit `feat(ios): PlanDraft editing operations`.

### Task 6: Merge plans into agenda rows

**Files:**
- Create: `ios/Sources/StarkKit/Planner/PlanAgenda.swift`
- Modify: `ios/Sources/StarkKit/Planner/AgendaBuilder.swift` (`AgendaItem`)
- Test: `ios/Tests/StarkKitTests/PlanAgendaTests.swift`

**Interfaces:**
- Produces: `AgendaItem.plan: PlanBlock?` (init parameter `plan: PlanBlock? = nil`, last); `AgendaItem.id` gains the suffix `"-plan-\(plan.id)"` when `plan != nil`; `AgendaItem.plannedRange: ClosedRange<Date>?` (`plan.start...plan.end`); `public func applyPlans(_ items: [AgendaItem], plans: [PlanBlock], today: Date, calendar: Calendar = gregorian) -> [AgendaItem]`.

Rules: for each open reminder item with a matching plan (`reminderID`, same occurrence day) whose plan day is on or after `today`: if the item's `displayDate` is on the plan's day, **replace** it (displayDate = plan start, `plan` set); otherwise **keep the original and add** a copy on the plan's day (displayDate = plan start, `plan` set, `isOverdue` kept so the "due Sep 19" label survives). Completed items and plans before `today` are untouched. Result stays sorted by displayDate then existing group order (planned rows sort by planned time among that day's incomplete rows).

- [ ] **Step 1: Write failing tests**: `overdueTaskPlannedTomorrowAppearsOnBothDays` (today row still overdue; tomorrow row at planned time, `isOverdue` true, distinct `id`s); `timedTaskPlannedSameDayReplacesNotDuplicates` (one row, planned time); `lapsedPlanIgnored`; `completedTaskHasNoPlannedCopy`; `existingFixturesUnchangedWithoutPlans` (output equals input when `plans` is empty).
- [ ] **Step 2–5:** fail, implement, pass (run full suite — `AgendaItem` is widely used), commit `feat(ios): planned tasks appear at their planned time in the agenda`.

### Task 7: Planner screen

**Files:**
- Create: `ios/App/Stark/Stark/PlannerView.swift`
- Modify: `ios/App/Stark/Stark/AgendaView.swift` (header buttons; run `applyPlans` in `makeSections`; `loadMonths` already covered by the window), `ios/App/Stark/Stark/AgendaRow.swift` (time range line), `ios/App/Stark/Stark/ContentView.swift` (present the sheet).

**Interfaces:**
- Consumes: Tasks 2–6 (`store.plans`, `store.replacePlans(on:with:)`, `DayPlanModel.make`, `PlanDraft`, `applyPlans`, `AgendaItem.plannedRange`).

- [ ] **Step 1:** In `AgendaView.makeSections`, pass items through `applyPlans(_:plans: store.plans, today: now)`. In `headerRow`, add a plan button (SF Symbol `calendar.badge.clock`, same 44×32 style and `.buttonStyle(.plain)` as the export button) on the Today and Tomorrow headers, accessibility label "Plan today"/"Plan tomorrow", calling a new `onPlan: (Date) -> Void`. In `AgendaRow`, show `plannedRange` as "9:00–9:30" in the time line, with "due Sep 19" as secondary text when the item `isOverdue` or its due time differs.
- [ ] **Step 2:** Build `PlannerView(day:)`: full screen, `.preferredColorScheme(.dark)`, close (`xmark`) and save (`checkmark`) `SquareToolbarButton`s; close with unsaved changes asks to discard. It calls `store.loadMonths(covering: AgendaWindow.loadRange(around: day))` on appear, builds `DayPlanModel` and a `@State PlanDraft`. Timeline: `ScrollView` of 24 hour rows, 60 pt per hour, opening scrolled near 08:00; all-day events in a banner above; events as dimmed `Colors.eventDot` blocks; blocks in `Colors.accent` with a resize grip on the bottom edge; `timed` tasks drawn at their time. Tray: bottom area of tray chips; a chip is dragged with `.draggable` and the timeline accepts with `.dropDestination`, converting the drop y-offset to a start time and calling `draft.place`; existing blocks move by `DragGesture` calling `draft.move`; grip drag calls `draft.resize`; dragging a block back over the tray or a context action removes it; edge-proximity during a drag auto-scrolls. Each block and tray chip also has an accessibility action "Add to plan" / "Move" that opens a time picker and calls `place`/`move` (VoiceOver cannot drag). Save calls `store.replacePlans(on: day, with: draft.blocks)`.
- [ ] **Step 3: Verify.** `xcodebuild -project ios/App/Stark/Stark.xcodeproj -scheme Stark -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation build` → `BUILD SUCCEEDED`; also build for Mac Catalyst (`-destination 'platform=macOS,variant=Mac Catalyst'`). Run the app in a simulator with `idb`, screenshot the planner, header and agenda row, and read the screenshots.
- [ ] **Step 4: Commit** `feat(ios): Plan view with tray and draggable timeline`.

### Task 8: Verify on device, document, ship

**Files:**
- Modify: `CLAUDE.md` (Native iOS section: planner rules, entry points, Done / Not yet verified log), `web/` FAQ copy if the site's FAQ lists features; `ios/App/Stark/Stark/FAQView.swift` with one entry.

- [ ] **Step 1:** Full suite on a clean rebuild: `cd ios && swift test` (expect all pass) and a build for a physical device (`ios/App/deploy.sh`).
- [ ] **Step 2: On device** (record "confirmed on device" separately from "unit-tested"): plan tomorrow with three tasks; drag, resize near the screen edge with auto-scroll, remove; reopen and rework; complete a planned task from the agenda; plan an overdue recurring task and confirm today's row remains; relaunch and confirm plans persist.
- [ ] **Step 3:** Update `CLAUDE.md` and the FAQ entry; commit `docs: timeboxing`.
- [ ] **Step 4:** Merge to `main` locally, rerun the full suite on the merged result, push `main` (say so in a line), then `ios/App/ship.sh` after sourcing `~/.appstoreconnect/env` and commit the version bump.

## Self-review

- Spec coverage: entry points (T7), timeline/tray/events banner (T4, T7), default length/snap/overlap/clamp (T3, T5), due dates untouched (T1–T2 constraints, T5 test), recurring carried miss and timed occurrences (T4, T6), rework after saving (T7 loads blocks via `DayPlanModel`), lapsed/orphan plans (T4, T6), storage and byte-identical output (T1–T2), VoiceOver (T7), docs/device/ship (T8).
- Deviation from the spec, decided during planning: a planned task's extra row exists only while the task is open (completing it shows only the normal completed row); the plan entry stays stored but is not shown.
