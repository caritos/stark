# Remove the Claude Code integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Delete the whole Claude Code bridge feature (the `stark://add` URL handler and its signing, the Settings > Claude Code screen, the Mac CLI `stark-claude`, its install script, the `/stark` slash command and all copy about it), leaving the rest of Stark working exactly as before.

**Architecture:** Pure removal. Delete files, then fix every reference the compiler, the tests and a grep find. No new behaviour, except keeping old sidecar files loadable.

**Tech Stack:** Swift 5.9 (StarkKit, SwiftPM, Swift Testing), SwiftUI app target, Go + static HTML website tests.

**Spec:** the owner's instruction in conversation 2026-11-17: "i don't think we need claude code integration, let's remove that feature". The feature's history stays in git and in `docs/superpowers/specs/2026-11-07-claude-code-bridge-design.md` and its plan (keep those two files as history; do not delete them).

## Global Constraints

- Remove ONLY the bridge. Do not touch the Apple write path, `ItemRepository`, the sidecar's plans/outcomes/import ledger, the import feature, or anything the bridge merely shares code with. For every shared helper (Keychain secret store, `DefaultDestinations`, `PhoneLock`, notice strip, `ItemSidecar` ledger APIs) check its callers with grep and keep it if anything else uses it; delete it only if the bridge was its only user.
- Sidecar compatibility: a `sidecar.json` written by earlier builds contains a `bridgeLedger` key. Removing the field must not make old files unreadable (Codable ignores unknown keys, but prove it with a test using the committed v1 fixture `ios/Tests/StarkKitTests/Fixtures/sidecar-v1.json` and a v2 file with an import ledger). No schema version bump. `ImportRunner`/`ItemSidecar.recordImport` stop writing the bridge-ledger entry.
- Tests that only covered the bridge are deleted with it; all other tests stay and pass. The full suite count will drop; report the before and after counts and the names of the deleted suites.
- `mobile/` is deprecated: do not touch it. `ios/.build` is tracked: never `git add` it (`git checkout -- ios/.build; git clean -fdq ios/.build`). Run Swift tests from the worktree's `ios/` with `swift test --scratch-path /private/tmp/claude-501/sdd-scratch`.
- Web tests need Node 24 on PATH (`N=$(ls -d $HOME/.nvm/versions/node/v24*/bin | tail -1); export PATH="$N:$PATH"`, then `cd web && make test-fast && make e2e`). Do NOT deploy the website and do not touch the VPS.
- Do not touch anything outside this worktree: not `~/.local/bin/stark-claude`, not the Mac Keychain, not `~/.claude/` (the owner's global `~/.claude/commands/stark.md` is a symlink into this repo's file; deleting the repo file leaves it dangling and that is reported, not fixed here).
- Commit trailers: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01D4JSV4Qz5xEkCxoor2D9h7`. Small commits.

## Done when

- `cd ios && swift test` green; `cd ios/App/Stark && xcodebuild` simulator build (iPhone 17) and a generic iOS build (`CODE_SIGNING_ALLOWED=NO`) succeed; `swift build` for the whole package succeeds (no dangling `stark-claude` / `StarkClaudeCore` target or product).
- `grep -rniE "ClaudeBridge|BridgeBatch|BridgeCodec|BridgeAuth|BridgeReplayGuard|stark-claude|StarkClaudeCore|ClaudeCodeSettings|stark://|bridgeLedger|Claude Code" ios/Sources ios/Tests ios/App ios/Package.swift ios/scripts web/public web/api/internal web/test .claude docs/ios-feature-notes.md` returns nothing except deliberate history notes you list (an "Removed 2026-11-17" note is expected in CLAUDE.md and `docs/ios-feature-notes.md`).
- `cd web && make test-fast` and `make e2e` green (privacy and FAQ pages no longer mention the bridge; the tests that pinned that copy are updated first).
- Simulator: Settings shows no "Integrations > Claude Code" row (Apple Calendar and Reminders remains), screenshot read; opening `stark://add?batch=x&sig=y` with `xcrun simctl openurl` does nothing and does not crash the app (screenshot or note); the agenda, Add, Search and Settings still open.
- NOT part of done: deploying the website, removing the owner's Mac-side leftovers, shipping TestFlight (the controller does it after review).

## Review Focus

- A leftover reference that only fails at runtime: Info.plist `CFBundleURLTypes` for the `stark` scheme, `onOpenURL` handlers, a Keychain item read at launch, `bridgeReady` gating in `ContentView`.
- The import feature still records ledger entries correctly after the bridge-ledger write is removed (`ItemSidecarImportLedgerTests`, `ImportRunnerTests` updated, not deleted).
- Old sidecar files still load.

---

### Task 1: Remove the Swift code, tests, CLI and scripts

**Files (delete):** `ios/Sources/StarkKit/Bridge/*`, `ios/Sources/StarkClaudeCore/*`, `ios/Sources/stark-claude/*`, `ios/Tests/StarkClaudeCoreTests/*`, the Bridge* and ClaudeBridge tests in `ios/Tests/StarkKitTests/`, `ios/scripts/install-stark-claude.sh` and `.test.sh`, `ios/App/Stark/Stark/ClaudeCodeSettingsView.swift`, `.claude/commands/stark.md`.
**Files (modify):** `ios/Package.swift`, `ios/App/Stark/Info.plist` (the `stark` URL scheme), `SettingsView.swift` (Integrations row; keep Apple Calendar and Reminders; drop the section header only if it would be left with one row that reads fine, else keep "Integrations"... decide: rename the section to "Apple" if only one row remains), `StarkApp.swift`, `ContentView.swift` (`onOpenURL`, `bridgeReady`, queued URL), `FAQView.swift`, `ItemSidecar.swift` (`bridgeLedger`, `recordBridge`, `bridgedIdentifier`, the `recordImport` bridge write), `PlannerStore.swift` (`importItems`/`ImportOutcome`/`ImportFailure` only if their sole caller was the bridge/its test), `.claude/settings.json` (any `stark-claude` permission entries), the Xcode project if it lists files explicitly, `ios/Tests/StarkKitTests/ItemSidecar*Tests.swift`, `ImportRunnerTests.swift`, `PlannerStoreImportTests.swift`.

- [ ] **Step 1: Record the baseline:** run the full suite and note the test and suite counts; list shared helpers the bridge used and their other callers (grep) in your report.
- [ ] **Step 2: Write the failing compatibility tests first** (they fail or are vacuous until the field is removed, so write them against the post-removal API): `oldSidecarWithBridgeLedgerKeyStillLoads` (v1 fixture) and `v2SidecarWithImportLedgerAndBridgeLedgerKeyStillLoads`; `recordImportNoLongerWritesBridgeLedger` (the encoded file has no `bridgeLedger` key).
- [ ] **Step 3: Delete and edit** as listed; let the compiler and `swift build` of the whole package find the rest; fix `ItemSidecar` so old files load.
- [ ] **Step 4: Run** `swift test`, the simulator build and a generic iOS build: PASS. Report counts before and after.
- [ ] **Step 5: Commit** `feat: remove the Claude Code bridge (app, kit, CLI, scripts)`.

### Task 2: Website copy and tests

**Files:** `web/public/pages/privacy.html` (the CLAUDE CODE BRIDGE section, mentions in the sidecar/Keychain paragraphs: read the whole page for sentences that only make sense with the bridge, including "the record of which Claude Code items were already added" and the Keychain/backup claims), `web/public/pages/faq.html`, `web/api/internal/web/web_test.go` (`TestPrivacyDatedAndMentionsData` and any check naming the bridge), `web/test/e2e/site.spec.ts` if it names it.

- [ ] **Step 1: Update the tests first** so they forbid the bridge wording ("Claude Code", "stark://", "pairing secret", "Keychain" in the bridge sense) and keep every other assertion; run `make test-fast` (Node 24 on PATH): FAIL for the right reason.
- [ ] **Step 2: Edit the pages** so every remaining statement is true after the removal: Stark makes no network connection, asks only for calendars and reminders, the small file of its own holds plan blocks, attended/skipped marks and the import ledger (no Claude Code ledger), nothing about a Keychain secret. Keep the page's "LAST UPDATED" at NOVEMBER 2026 (it is already). Do not restyle.
- [ ] **Step 3: Run** `make test-fast` and `make e2e`: PASS.
- [ ] **Step 4: Commit** `web: copy no longer mentions the Claude Code bridge`.

### Task 3: Docs

**Files:** `CLAUDE.md`, `docs/ios-feature-notes.md`, `README.md` if it mentions it.

- [ ] **Step 1:** In `CLAUDE.md` replace the "Claude Code bridge log (2026-11-07)" section with a short "Claude Code bridge removed (2026-11-17)" section (what was removed, why: the owner decided he does not need it; where the history is: git before this commit, the 2026-11-07 spec and plan; what Mac-side leftovers the owner may still have: `~/.local/bin/stark-claude` link, the pairing secret in the Mac login Keychain, `~/.claude/commands/stark.md` symlink now dangling; the sidecar still tolerates the old `bridgeLedger` key). Remove or reword every other CLAUDE.md sentence that presents the bridge as live (the Apple write-through log mentions the bridge ledger, `stark-claude today`, "BEFORE SHIP" instructions, the Storage paragraph, the Mac tool "last" item: reword the Mac tool item as "no longer planned unless asked"). In `docs/ios-feature-notes.md` replace the bridge paragraph with a one-line removal note and fix other mentions (Apple overlay paragraph).
- [ ] **Step 2:** grep check from "Done when" (list deliberate history mentions). Commit `docs: log the removal of the Claude Code bridge`.

### Task 4: Simulator verification

- [ ] Build and install on the iPhone 17 simulator (CLAUDE.md "Testing and deploying", idb notes: `idb ui tap` works; redirect `idb_companion` output, never paste it). Screenshot and READ: Settings (no Claude Code row), Apple Calendar and Reminders screen still opens, agenda, Add. Run `xcrun simctl openurl booted "stark://add?batch=x&sig=y"` and confirm the app does not react or crash (the scheme is gone, iOS shows its own "cannot open" or nothing). Report seen / not seen. Do not merge, push or ship.
