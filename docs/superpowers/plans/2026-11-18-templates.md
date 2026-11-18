# Templates plan (2026-11-18)

## Global Constraints
Swift tools 5.9, iOS 17; logic in StarkKit, views in the app target; Swift Testing; tests first; run `swift test --scratch-path /private/tmp/claude-501/<name>`; timing tests flaky under load. Work in a worktree. Model `ItemTemplates` on `ios/Sources/StarkKit/Apple/CalendarSets.swift`, persistence on `ios/App/Stark/Stark/CalendarSetsModel.swift`. Run `xcodegen generate` after adding Swift files and commit the pbxproj.

## Done when
See the spec. Each task ends with its own check.

## Task 1: Kit (red first)
`ios/Sources/StarkKit/Items/ItemTemplates.swift` + `ios/Tests/StarkKitTests/ItemTemplatesTests.swift`: `ItemTemplate`, `ItemTemplates` (add from form values, rename, delete, per-kind list, name rules and errors with messages, decode/encode incl. corrupt and newer version), `TemplateFormValues` (duration to end, all-day has no duration, destination fallback). Check: suite green under the three time zones.

## Task 2: App
`TemplatesModel`, Add's Templates menu and Save as Template alert, swipe delete (a small management sheet or menu items with delete), injected like `CalendarSetsModel` in `StarkApp`. Check: generic iOS build, simulator walk with idb and screenshots read (save, apply, relaunch, delete).

## Task 3: Copy
In-app FAQ, web FAQ (`TestFAQExplainsTemplates` red first), README, `docs/ios-feature-notes.md`. Check: `make test-fast`, `make e2e`.

## Task 4: Review and ship
Whole-branch review, one fix wave, ff merge, full suite on main, CLAUDE.md log, TestFlight (ship.sh), website deploy, vault session note.
