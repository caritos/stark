# Calendar sets (short design, 2026-11-18, issue #120)

## Why
Fantastical's "calendar sets": show only some calendars/lists at a time (Work, Home) and switch with one tap. Stark already hides calendars one by one in Settings (`AppleSelection`, excluded ids); a set is a saved, named selection. The owner said to keep going on #120 without asking, so the calls below are mine and reversible.

## Done when
- `cd ios && swift test` green with new tests first (red, then green), also under Honolulu, New York and Tokyo.
- Simulator (iPhone 17): create two sets from the bottom bar's "All Calendars" button, switch between them, see the agenda, month grid and Search change; the button's label shows the active set's name; a calendar created later is NOT in an existing set and IS shown under "All Calendars". Screenshots read.
- In-app FAQ, web FAQ and README mention sets (web tests first). No privacy change (sets are names and calendar ids kept in UserDefaults on the device; say so). Website deploy needs no go.
- NOT done: Focus Filters, sets per Focus mode, widgets, set-specific default destinations, sync of sets between devices, App Store review.

## Approaches (picked: 1, my call)
1. **Sets as saved INCLUDED-id lists on top of the existing selection (picked).** Applying a set writes `AppleSelection.excludedIDs = every calendar not in the set`, so every existing screen keeps working unchanged. The active set is derived (the set whose applied exclusion equals the current selection), not stored, so toggling a calendar in Settings simply leaves "Custom".
2. A new selection model replacing `AppleSelection`: cleaner in theory, touches every screen and the persistence; no gain for the user.
3. Per-set stored excluded lists: new calendars would appear in every set by themselves, the opposite of Fantastical and surprising.

## Design
- **Kit:** `CalendarSet { id: UUID, name: String, includedIDs: Set<String> }` (Codable); `CalendarSets` value type holding `[CalendarSet]` with `add/rename/delete/updateIncluded`, name rules (trimmed, 1-30 characters, unique ignoring case; duplicate or empty is rejected with a reason), `selection(applying: CalendarSet, allIDs: Set<String>) -> AppleSelection`, `activeSetID(for: AppleSelection, allIDs:) -> UUID?`, `label(for: AppleSelection, allIDs:) -> String` ("All Calendars" when nothing is excluded, the set's name when one matches, else "Custom"), Codable round trip with a version field, a missing or corrupt blob decodes to no sets (never crashes).
- **App:** sets persisted as JSON in UserDefaults (key `calendarSets.v1`; names and ids only); the bottom bar's centre button shows `label(...)`; tapping it opens a sheet: "All Calendars" (clears exclusions), each set with a check on the active one, "New Set..." (name + calendar toggles reusing the Settings toggle label), swipe or Edit to rename/delete; a "Settings" row keeps the existing calendar list reachable. Deleting a set never changes the current selection.
- A calendar that no longer exists is simply ignored in a set.

## Non-goals
No Focus Filters, no per-set destination, no automatic set switching, no iCloud sync, no change to the writing path.

## Left to the builder
Exact sheet layout, accessibility labels, how Search treats the active selection (it already uses the shown calendars).
