# Focus Filter plan

## Global Constraints
- Kit holds logic (`ios/Sources/StarkKit/Apple/FocusFilter.swift`), app holds the intent and glue. Swift Testing. Tests under Honolulu/Tokyo not needed (no dates).
- Tests with `swift test --scratch-path /private/tmp/claude-501/<name>`; `ios/.build` is tracked by an old mistake: `git checkout -- ios/.build` before committing, never commit deletions.
- Folder-synced Xcode project: new files under `ios/App/Stark/Stark/` are picked up; no XcodeGen.
- Web: `cd web && nvm use` in the same shell, `bash scripts/sync-public.sh` once in a fresh worktree.

## Done when
As the spec.

## Task 1: Kit `FocusFilter` (TDD)
`FocusFilterState: Codable, Equatable {before: Set<String>, applied: Set<String>}` with tolerant `decode(Data?) -> FocusFilterState?` and `encoded()`; pure `FocusFilter.turnOn(setID:current:state:sets:allIDs:alwaysShown:) -> (selection: Set<String>, state: FocusFilterState)?` (nil = change nothing) and `FocusFilter.turnOff(current:state:) -> (selection: Set<String>?, state: nil)` (selection nil = leave as is). Tests first: first on remembers before; second on keeps original before; deleted set / empty allIDs -> nil; off restores when current == applied; off leaves a hand-changed selection; off with no state does nothing; corrupt state decodes to nil.
Check: `swift test --filter FocusFilter`.

## Task 2: app intent
`FocusFilterStore` (UserDefaults, reads/writes excluded key, `focusFilter.v1`, mirrors to App Group via `SelectionMirror`, `WidgetCenter.reloadAllTimelines()`), `CalendarSetEntity: AppEntity` + `EntityQuery` (reads `calendarSets.v1` with `CalendarSets.decode`), `StarkFocusFilter: SetFocusFilterIntent` calling the Kit functions; calendar ids from `EventKitProvider().calendars()` only when `accessState() == .granted`. `AppleOverlayModel` re-reads `Key.excluded` from defaults on scene `.active` (new method `reloadStoredSelection()`, assigns only when different). Check: generic iOS Debug build; simulator run.

## Task 3: copy
Web FAQ test first (`TestFAQExplainsFocusFilter`: "can a focus", "calendar set", "turns off", "stays on this device"), then web and in-app FAQ, README, feature notes, CLAUDE.md log.

## Task 4: whole-branch review, one fix wave, ff merge, full suite on main, push, ship.sh (TestFlight only), website deploy, vault session note.
