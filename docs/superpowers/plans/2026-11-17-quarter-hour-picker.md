# Quarter-hour time pickers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The time pickers in Add, Edit and the planner's Move sheet offer only :00, :15, :30 and :45, and a new item defaults to the next quarter hour.

**Architecture:** SwiftUI's `DatePicker` has no minute step, so the app target gets one small UIKit wrapper (`QuarterHourDatePicker`, a `UIViewRepresentable` over `UIDatePicker` with `minuteInterval = 15`). The one piece of logic (next quarter hour) is a pure StarkKit function with tests. The wrapper writes to its binding ONLY on a user change, so an existing item with odd minutes keeps its exact time until the owner edits the time.

**Tech Stack:** Swift 5.9, StarkKit (Swift Testing), SwiftUI + UIKit (`UIDatePicker`), Mac Catalyst target.

**Spec:** the owner's request 2026-11-17: "for the time picker, only choose from 00,15,30,45, i don't need every minute". Controller calls (owner can override): default start = next quarter hour; existing odd minutes preserved until edited; applies to Add (Starts/Due, Ends), Edit (same) and the planner Move sheet; not the repeat end date (date only).

## Global Constraints

- Logic in StarkKit with Swift Testing (`import Testing`, `@Test`, `#expect`), TDD with RED shown; the app target holds views and the UIKit wrapper only.
- Theme rules (CLAUDE.md "Theme/UI rules"): no hardcoded colours; tint = `Colors.accent`; text colour tokens. The picker must look like today's compact picker (a date pill and a time pill on the right of the row label), light and dark, Dynamic Type safe.
- Time-sensitive tests build dates with a local `Calendar` and must pass under TZ Pacific/Honolulu, America/New_York, Asia/Tokyo, including a DST day (America/New_York 2026-03-08 and 2026-11-01).
- Behaviour that must not change: moving the start moves the end by the same amount (`EventSchedule.shiftedEnd`), the end never precedes the start (`in: date...` becomes the picker's `minimumDate`), the All day toggle (date-only picker when on, `FormFields.normalizedStart`), the repeat end clamp, undated/"Add Date" behaviour, the planner's `PlanLayout.snap`.
- Run Swift tests from the worktree's `ios/`: `swift test --scratch-path /private/tmp/claude-501/sdd-scratch` (tracked `ios/.build` is stale). Never `git add` anything under `ios/.build` or `.superpowers` (`git checkout -- ios/.build; git clean -fdq ios/.build`). Two timing tests (`yearDensity under 2 s`, the `PendingCompletionsTests` live scheduler) are flaky under machine load: check `uptime`, if above 10 run `xcrun simctl shutdown all`, wait, rerun once before judging.
- Commit trailers: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01D4JSV4Qz5xEkCxoor2D9h7`.

## Done when

- `cd ios && swift test` green; simulator (iPhone 17) and generic iOS builds (`CODE_SIGNING_ALLOWED=NO`) succeed; Mac Catalyst Debug build compiles (`CODE_SIGNING_ALLOWED=NO`) if the Catalyst destination is available, else say so.
- Simulator screenshots READ, light and dark: Add Event with the time wheel open showing only 00/15/30/45 in the minute column; Add Event default start is a quarter hour; Edit of an event at an odd minute (create one at 10:07 through a probe or the Edit screen before the change, or seed one) opens, is saved WITHOUT touching the time, and keeps 10:07 (check the saved value, not the display); changing the time via the wheel gives a quarter hour; the planner Move sheet minute wheel shows quarter hours only; the Ends picker cannot go before Starts.
- NOT part of done: shipping (the controller does it), the owner's device check, VoiceOver beyond setting sensible accessibility labels.

## Review Focus

- A silent time change: opening and saving an existing item at 10:07 must not move it (the display may show a snapped time; say what you saw).
- All-day toggle on/off keeps the date; switching to all-day and back restores the picked time as it does today.
- The DST gap hour and a start at 23:45 with the default one-hour end.
- A long-press or scroll in the wheel inside a `Form`/`List` row does not fight the list's scrolling.

---

### Task 1: `QuarterHour` helper (Kit, TDD)

**Files:** Create `ios/Sources/StarkKit/Models/QuarterHour.swift`; Test `ios/Tests/StarkKitTests/QuarterHourTests.swift`.

**Interfaces:**
- Produces: `enum QuarterHour { static let minutes = 15; static func nextAfter(_ date: Date, calendar: Calendar = .current) -> Date }` returning the first :00/:15/:30/:45 STRICTLY after `date`'s minute rounded up (a date exactly on a quarter hour with zero seconds returns that same date; otherwise the next quarter hour, seconds dropped); `static func isOnQuarter(_ date: Date, calendar: Calendar = .current) -> Bool`.

- [ ] **Step 1: Write failing tests:** `onQuarterReturnsSame` (10:15:00 -> 10:15), `justAfterRoundsUp` (10:15:01 -> 10:30; 10:11 -> 10:15; 10:46 -> 11:00), `lateEveningRollsToNextDay` (23:50 -> 00:00 next day), `dstSpringForwardGapHour` and `dstFallBackRepeatedHour` (America/New_York), `isOnQuarterTrueAndFalse`, `ignoresSecondsAndNanoseconds`.
- [ ] **Step 2: Run** `--filter QuarterHour`: FAIL. **Step 3: Implement.** **Step 4: Run** under the three TZs: PASS. **Step 5: Commit** `feat: QuarterHour helper for quarter-hour defaults`.

### Task 2: the wrapper and its use in Add, Edit and Move

**Files:** Create `ios/App/Stark/Stark/QuarterHourDatePicker.swift`; Modify `AddItemView.swift` (~44-46, 59-71: default start/end init, the two `DatePicker`s), `EditItemView.swift` (~102-113), `PlannerSupport.swift` (~97-104, the Move sheet; keep its "Rounded to the nearest 15 minutes." caption and `PlanLayout.snap`).

**Interfaces:**
- Consumes: `QuarterHour.nextAfter` (Task 1); `EventSchedule.defaultDuration`.
- Produces: `struct QuarterHourDatePicker: View` with `init(_ title: String, selection: Binding<Date>, minimumDate: Date? = nil, components: Components, style: Style = .compact)` where `Components` is `.date` / `.time` / `.dateAndTime` and `Style` is `.compact` / `.wheel`. Behaviour: shows the title on the left like today's `DatePicker` row (use `LabeledContent`/`HStack` so the Form row looks unchanged), uses `UIDatePicker.minuteInterval = 15`, tint `Colors.accent`, writes to `selection` ONLY from the picker's `.valueChanged` action (never from `updateUIView`), pushes external changes (the onChange that shifts the end, All day toggles) into the picker without echoing them back, honours `minimumDate`, `accessibilityLabel` = title, Catalyst uses `.compact`.

- [ ] **Step 1 (spike):** on the simulator confirm that with `minuteInterval = 15` an existing 10:07 set on the picker does not call `valueChanged` and the binding stays 10:07 until the user moves the wheel; record what the picker DISPLAYS for 10:07 (snapped or not). If the binding would change on its own, add a guard so it does not.
- [ ] **Step 2:** Implement the wrapper; replace the four `DatePicker`s (Starts/Due and Ends in Add and Edit; the planner Move `Start`) keeping every `onChange`/`shiftedEnd`/`clamped` line; Add's initial `date` = `QuarterHour.nextAfter(now)` and `endDate` = that + `EventSchedule.defaultDuration`; Edit's new-date paths (`addDueDate`) are unchanged.
- [ ] **Step 3:** Run `swift test` (PASS) and the simulator / generic iOS / Catalyst builds.
- [ ] **Step 4: Simulator verification** exactly as in "Done when" (idb: `idb ui tap` works; `idb_companion` prints the shell environment, ALWAYS redirect its output and never paste it). READ every screenshot; report seen / not seen.
- [ ] **Step 5: Commit** `feat: quarter-hour time pickers in Add, Edit and Move`.

### Task 3: docs (controller)

- [ ] CLAUDE.md log (Done / Not yet verified on device / Deferred), `docs/ios-feature-notes.md` add/edit fields paragraph, then merge, full suite on the merged result, TestFlight.
