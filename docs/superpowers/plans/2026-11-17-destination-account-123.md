# Destination picker shows the account (issue #123) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make it visible where a new item goes: calendar/list rows show their account, a local-only (non-syncing) destination is flagged, and "Added" confirmations name the destination.

**Architecture:** A pure `DestinationLabel` in StarkKit builds all strings (subtitle, local-only warning, "Added to ..." text) from `AppleCalendarInfo`, which gains `isLocalOnly`. The app maps `EKSourceType.local` into it and renders the strings; no logic in views.

**Tech Stack:** Swift 5.9, StarkKit (Swift Testing), SwiftUI, EventKit (app target only).

**Spec:** GitHub issue caritos/stark#123 (the design; approved by the owner 2026-11-17). Origin: an event created in Stark landed in a local calendar titled "Calendar" and never reached the owner's Mac.

## Global Constraints

- Logic in StarkKit with Swift Testing (`import Testing`, `@Test`, `#expect`); the app target only renders. TDD, show RED first.
- Run tests from the worktree's `ios/`: `swift test --scratch-path /private/tmp/claude-501/sdd-scratch` (tracked `ios/.build` has a stale module cache). Never `git add` anything under `ios/.build` or `.superpowers`; if `ios/.build` shows modified run `git checkout -- ios/.build; git clean -fdq ios/.build`.
- Theme rules (CLAUDE.md "Theme/UI rules"): no hardcoded colours, `Colors.textSecondary` for secondary text, grouped lists.
- Local-only means `EKSourceType.local` ("On My iPhone"); subscribed and birthday sources are not writable and never offered.
- Copy: the warning reads exactly "Stays on this iPhone; it won't sync to your other devices." Account line is `accountName`, falling back to "Unknown account" when empty. Items in two calendars with the same title must be distinguishable in every picker row.
- Commit trailers: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01D4JSV4Qz5xEkCxoor2D9h7`.

## Done when

- `cd ios && swift test` green; generic iOS build compiles (`CODE_SIGNING_ALLOWED=NO`).
- Simulator screenshots (light and dark) read and checked: Settings > Apple Calendar and Reminders pickers show two same-titled calendars from different accounts apart, a local-only calendar shows the warning, adding an event shows "Added to <calendar> · <account>" and the Claude Code bridge banner names the calendar and list.
- TestFlight upload after merge. NOT part of done: owner device check, website deploy.

## Review Focus

- Two calendars with the same title in one picker: rows must differ (Task 1 test).
- An empty `accountName` and a very long calendar title: no crash, no empty subtitle (Task 1 tests).
- A bridge batch that adds to a destination whose info is missing from the loaded list: banner falls back to the plain text (Task 2 test).

---

### Task 1: `isLocalOnly` and `DestinationLabel` (Kit, plus provider mapping)

**Files:**
- Modify: `ios/Sources/StarkKit/Apple/AppleModels.swift` (`AppleCalendarInfo`), `ios/App/Stark/Stark/EventKitProvider.swift` (`info(_:isReminderList:)`)
- Create: `ios/Sources/StarkKit/Items/DestinationLabel.swift`
- Test: `ios/Tests/StarkKitTests/DestinationLabelTests.swift`

**Interfaces:**
- Produces: `AppleCalendarInfo.isLocalOnly: Bool` (init parameter `isLocalOnly: Bool = false`, last); `enum DestinationLabel` with `static func subtitle(_ info: AppleCalendarInfo) -> String` (account name, "Unknown account" if empty, with " · Stays on this iPhone" NOT included), `static let localOnlyWarning = "Stays on this iPhone; it won't sync to your other devices."`, `static func warning(for info: AppleCalendarInfo?) -> String?` (non-nil only when `isLocalOnly`), `static func addedNotice(calendar: AppleCalendarInfo?, noun: String) -> String` ("Added to Home · iCloud" style: `"Added to \(title) · \(account)"`; when `calendar` is nil: "Added"; `noun` unused unless you need plural wording, drop it if not).

- [ ] **Step 1: Write failing tests** in `DestinationLabelTests`: `subtitleIsAccountName`; `subtitleFallsBackWhenAccountEmpty` ("Unknown account"); `twoSameTitledCalendarsGetDifferentSubtitles` (iCloud vs On My iPhone); `warningOnlyForLocalOnly`; `warningTextIsExact`; `addedNoticeNamesCalendarAndAccount`; `addedNoticeFallsBackToPlainAddedWhenCalendarMissing`; `veryLongTitleIsNotTruncatedByTheKit` (view truncates).
- [ ] **Step 2: Run** `swift test --scratch-path /private/tmp/claude-501/sdd-scratch --filter DestinationLabel` and see FAIL.
- [ ] **Step 3: Implement** the model field and `DestinationLabel`; in `EventKitProvider.info` set `isLocalOnly: calendar.source?.sourceType == .local` (also for reminder lists).
- [ ] **Step 4: Run** the filter then the full suite: PASS.
- [ ] **Step 5: Commit** `feat: DestinationLabel and AppleCalendarInfo.isLocalOnly (#123)`.

### Task 2: Render it (Settings pickers, Add notice, bridge banner)

**Files:**
- Modify: `ios/App/Stark/Stark/AppleSettingsView.swift` (pickers ~41-50), `ios/App/Stark/Stark/AddItemView.swift` (after a successful add, ~253-259), `ios/Sources/StarkKit/Bridge/ClaudeBridge.swift` (banner text ~31-34) and its caller wiring in `StarkApp.swift`/`ContentView.swift`
- Test: `ios/Tests/StarkKitTests/ClaudeBridgeTests.swift` (existing; add cases), `DestinationLabelTests` if a helper is added

**Interfaces:**
- Consumes: `DestinationLabel` and `AppleCalendarInfo.isLocalOnly` (Task 1); `DefaultDestinationModel.calendarChoices/listChoices` and the chosen ids; `NoticeCenter` (look at how `AgendaView` posts a notice).
- Produces: bridge banner text "Added N items to <calendar title>" (events) / "... to <list title>" — a batch with both kinds names both ("Added 2 items: Home calendar, Groceries list" style; pick one clear wording and test it); falls back to the existing text when a destination's info is not available.

- [ ] **Step 1: Write failing tests** in `ClaudeBridgeTests`: banner names the calendar for an events-only batch, names the list for a reminders-only batch, names both for a mixed batch, falls back to "Added N items" when infos are missing, and "Already added" is unchanged.
- [ ] **Step 2: Run** `--filter ClaudeBridge` FAIL.
- [ ] **Step 3: Implement** bridge text (names passed in, not looked up inside the bridge); Settings picker rows as a two-line label (title, then `DestinationLabel.subtitle` in `Colors.textSecondary` footnote), a footer line under the pickers showing `DestinationLabel.warning(for:)` for the CURRENT default calendar and list (in `Colors.accent`) when local-only; Add screen: after a successful save post a notice `DestinationLabel.addedNotice(calendar:)` through `NoticeCenter` before `dismiss()` (check it survives the sheet closing; if the notice would sit under the sheet, post it from where the sheet is presented instead and say so).
- [ ] **Step 4: Run** the full suite PASS; simulator + generic iOS builds compile.
- [ ] **Step 5: Simulator check** on the iPhone 17 (see CLAUDE.md for idb notes; never paste `idb_companion` output): create a second calendar with the same title "Calendar" in another source if the simulator allows (or use the fake provider path your earlier tests used), screenshot Settings in light and dark, add an event and screenshot the notice, send a signed bridge URL as in the Claude Code bridge log (`add --print-url` then `simctl openurl`) and screenshot the banner. READ every screenshot; report seen / not seen.
- [ ] **Step 6: Commit** `feat: show destination account, local-only warning and named confirmations (#123)`.

### Task 3: Docs and ship (controller)

- [ ] Update `CLAUDE.md` log (Done / Not yet verified on device / Deferred; the owner's report and issue #123 closed by this), `docs/ios-feature-notes.md` (Settings paragraph), in-app FAQ only if wording about the default calendar changes.
- [ ] Merge to main (fast-forward), full suite on the merged result, `ship.sh` to TestFlight, push main, close issue #123 with a comment.
