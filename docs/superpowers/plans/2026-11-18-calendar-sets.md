# Calendar sets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Saved named calendar sets, switched from the bottom bar, built on the existing excluded-id selection.

**Architecture:** Pure Kit value types (`CalendarSet`, `CalendarSets`) over `AppleSelection`; a thin app sheet and persistence in UserDefaults.

**Tech Stack:** Swift 6 / SwiftUI, Swift Testing, Go + static HTML for copy.

**Spec:** `docs/superpowers/specs/2026-11-18-calendar-sets-design.md`

## Global Constraints
- Worktree; tests first (red, then green); small commits; never `git add` `ios/.build` or `.superpowers`.
- Kit tests: `cd ios && swift test --scratch-path /private/tmp/claude-501/cs` (new suite also under `TZ=Pacific/Honolulu`, `America/New_York`, `Asia/Tokyo`). Web: `cd web && make test-fast`, `make e2e` (Node 24: `nvm use` inside `web/`, same shell).
- `AppleSelection` stays the single source of what is shown; every existing screen keeps reading it. Sets store included ids; the active set is derived, never stored. Sets live only in UserDefaults on the device (names and calendar ids). No network, no new permission.
- Copy: privacy page unchanged except nothing to add (sets are local like the existing selection; confirm no claim contradicts); every page keeps the `Build @@BUILD_ID@@` footer once; web tests with anchored phrases first.

## Review Focus
- A calendar created after a set was saved is not in it (hidden under that set) and is shown under "All Calendars".
- A set containing a deleted calendar id: ignored, no crash, label still matches.
- Two sets with identical included ids: the active label is deterministic (first in order).
- Empty name, 31-character name, duplicate name differing only by case: rejected with a reason; rename to its own name is allowed.
- A set with no calendars: allowed? Reject it (at least one calendar must be included) so the agenda is never silently empty.
- Corrupt or missing UserDefaults blob: no sets, app launches; a blob from a newer version (unknown version) is ignored without being overwritten until the owner edits.
- Reminder lists are part of sets like calendars (same ids space).
- Deleting the active set leaves the current selection unchanged (label becomes "Custom").

### Task 1: Kit sets logic
**Files:** Create `ios/Sources/StarkKit/Apple/CalendarSets.swift`; Test `ios/Tests/StarkKitTests/CalendarSetsTests.swift`.
**Interfaces (produces):** `public struct CalendarSet: Equatable, Codable, Sendable, Identifiable { id: UUID; name: String; includedIDs: Set<String> }`; `public enum CalendarSetError: Error, Equatable, Sendable { emptyName, nameTooLong, duplicateName, noCalendars, notFound }` with a `message: String`; `public struct CalendarSets: Equatable, Sendable { sets: [CalendarSet]; init(sets:); mutating add(name:includedIDs:id:) throws -> CalendarSet; mutating rename(_ id:to:) throws; mutating updateIncluded(_ id:to:) throws; mutating delete(_ id:); func selection(applying id: UUID, allIDs: Set<String>) -> AppleSelection?; func activeSetID(for: AppleSelection, allIDs: Set<String>) -> UUID?; func label(for: AppleSelection, allIDs: Set<String>) -> String; static func decode(_ data: Data?) -> CalendarSets; func encoded() -> Data }`.
- [ ] **Step 1:** Write failing tests for every Review Focus line that is Kit logic (the later-created calendar, deleted id ignored, identical sets, name rules incl. 30 vs 31 characters and case-insensitive duplicate, rename to own name, empty set rejected, corrupt/missing/unknown-version decode, delete leaves selection untouched, label "All Calendars"/name/"Custom").
- [ ] **Step 2:** Run `swift test --filter CalendarSetsTests`; expect compile failure.
- [ ] **Step 3:** Implement per Interfaces (versioned JSON envelope `{version: 1, sets: [...]}`; unknown version decodes to empty without throwing).
- [ ] **Step 4:** Run the suite under the three zones, then the full `swift test`; commit `feat: calendar sets logic`.

### Task 2: Sheet, persistence, copy
**Files:** Create `ios/App/Stark/Stark/CalendarSetsModel.swift` (`@MainActor @Observable`, UserDefaults key `calendarSets.v1`, applies a set through `AppleOverlayModel.selection`), `CalendarSetsSheet.swift`, `CalendarSetEditor.swift`; modify `FloatingBottomBar.swift` / `ContentView.swift` (the centre button label and action), `StarkApp.swift` (environment), `FAQView.swift`, `web/public/pages/faq.html`, `README.md`, `docs/ios-feature-notes.md`, `CLAUDE.md`; Test `web/api/internal/web/web_test.go` (`TestFAQExplainsCalendarSets`, red first). Keep the existing way to the Apple calendar list reachable from the sheet.
**Interfaces:** Consumes Task 1.
- [ ] **Step 1:** Web test first: `/faq` has a calendar-sets entry (create sets of calendars, switch from the "All Calendars" button, a calendar added later is not in an existing set, kept on this device); `make test-fast` expected FAIL.
- [ ] **Step 2:** Model + sheet + editor + bottom-bar label; VoiceOver: the button reads "Calendars: <label>"; check mark and "selected" trait on the active row; errors from `CalendarSetError.message` shown in the editor, never alerts.
- [ ] **Step 3:** Copy (FAQ web and in-app, README, feature notes, CLAUDE.md "Calendar sets log (2026-11-18)": Done / Not yet verified on device / Deferred); web tests green.
- [ ] **Step 4:** Simulator (iPhone 17, idb): create "Work" and "Home" from two calendars each (seed calendars with a small script if needed), switch, confirm agenda/month/Search follow, the label changes, a calendar created afterwards is hidden under a set and shown under All Calendars, deleting the active set leaves the view as it was and the label says Custom. Screenshots read; record seen / not seen.
- [ ] **Step 5:** Full `swift test`, generic iOS and Mac Catalyst Debug builds (`CODE_SIGNING_ALLOWED=NO`), `make test-fast`, `make e2e`; commit `feat: calendar sets from the bottom bar`.
