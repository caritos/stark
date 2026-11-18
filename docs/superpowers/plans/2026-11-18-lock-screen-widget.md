# Lock Screen widget plan

## Global Constraints
Kit holds logic, widget target views (`ios/App/Stark/StarkWidget/StarkAgendaWidget.swift`). Swift Testing. `swift test --scratch-path /private/tmp/claude-501/<name>`. `git checkout -- ios/.build` before committing. Web: `cd web && nvm use`, `bash scripts/sync-public.sh` in a fresh worktree.

## Done when
As the spec.

## Task 1: Kit
`WidgetAgenda.remainingToday(items:)`-style pure helper (or a `WidgetRowText` function) for the circular count and its "9+" text, plus an inline/rectangular text function (`WidgetRowText.lockLine(_:)`: "9:00 AM Standup", all day = title, overdue = title). Tests first, seen red.

## Task 2: widget views
Add `.accessoryRectangular/.accessoryInline/.accessoryCircular` to `supportedFamilies`, extend `AgendaState.items` with the per-family lists (rows(3) for rectangular, rows(1) inline, count from rows(5) filtered to non-tomorrow), `containerBackground` for accessory families uses `.clear`/default, use `AccessoryWidgetBackground` for circular. Check: generic iOS Debug build, simulator.

## Task 3: copy and log
Web test first, FAQ app+web, README, feature notes, CLAUDE.md log (honest Not verified).

## Task 4: whole-branch review, one fix wave, ff merge, full suite on main, push, ship.sh, website deploy, vault note.
