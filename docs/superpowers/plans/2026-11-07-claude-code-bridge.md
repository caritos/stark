# Claude Code Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From Claude Code on the Mac, add signed batches of reminders/events to Stark on the owner's iPhone (TestFlight build) via `devicectl --payload-url`, with no network use by the app; plus a best-effort `today` read.

**Architecture:** StarkKit gets a `Bridge/` module (wire format, codec, HMAC signing, replay guard, validation to `Event`/`Reminder`, a handler that imports through `PlannerStore`). The app target adds only the `stark://` URL scheme, `onOpenURL` glue, a banner and a Settings "Claude Code" pairing screen. A new macOS-only SwiftPM target `StarkClaudeCore` plus executable `stark-claude` builds/signs/sends batches and pulls the day. A project command `.claude/commands/stark.md` drives it.

**Tech Stack:** Swift 6.3 toolchain, swift-tools 5.9 package, iOS 17 / macOS 14, Swift Testing, CryptoKit (HMAC-SHA256), Compression (zlib), Security (Keychain). No third-party code.

**Spec:** `docs/superpowers/specs/2026-11-07-claude-code-bridge-design.md` (read it first; this plan argues from it).

## Global Constraints

- Scheme `stark`, host `add`: `stark://add?batch=<base64url(zlib(JSON))>&sig=<base64url(HMAC-SHA256)>`. Bundle id `com.caritos.todo-txt`.
- The signature covers the **transmitted compressed bytes exactly**; verify before decompressing.
- Unsigned, wrongly signed, unpaired, wrong scheme/host, malformed base64 = **ignored** (log only, no banner, no crash).
- `issuedAt` (epoch seconds, signed) accepted only if no older than 600 s and no more than 120 s in the future; replay guard remembers the last 200 batch ids.
- A batch is **all-or-nothing**; any invalid item rejects the whole batch with a banner naming the first problem.
- Limits (author's call): at most 200 items per batch, title at most 500 chars, notes at most 5000.
- Priority: low = 9, medium = 5, high = 1 (reminders only). Reminders must have a start (undated reminders are not supported); date-only start = all-day (reminder due at start of day).
- Times are `yyyy-MM-dd` or `yyyy-MM-ddTHH:mm`, interpreted in the **phone's current time zone**; a nonexistent local time rejects the batch; an ambiguous one takes the first occurrence.
- Label: sanitised to lowercase `[a-z0-9-]`, max 32 chars; appended to each item's notes as `%label` unless that exact token is already present.
- The app makes no network call. No new dependencies. Secret never logged, printed, or committed.
- Pairing secret: 32 random bytes in the Keychain, `whenUnlockedThisDeviceOnly` on iOS; the "copy" action uses a local-only pasteboard item.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`), test first. Fast tier: `cd ios && swift test`. App build: `xcodebuild -project ios/App/Stark/Stark.xcodeproj -scheme Stark -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build` (no `CODE_SIGNING_ALLOWED=NO`).
- Logic lives in StarkKit/StarkClaudeCore, never in views. No `Date()` in views. Theme from `Theme.swift` only.
- Work in a worktree off branch `claude-bridge`: `git worktree add .claude/worktrees/claude-bridge-impl -b claude-bridge-impl claude-bridge`, absolute paths. Commit after each green step.
- Use `os.Logger(subsystem: "com.caritos.todo-txt", category: "bridge")` for logging (Stark has no FileLogger; adding one is out of scope).

## Review Focus

Inputs the spec implies that no single task would otherwise exercise (each is pinned by a test in the named task):

1. A batch whose destination month file is unreadable: nothing added, banner shown, store unchanged (Task 6).
2. A DST-gap local time and a phone in another time zone than the Mac (Task 2).
3. A replayed URL, an expired one, a far-future one (Mac clock wrong) (Tasks 5, 7).
4. Titles/notes/location with newlines, commas, semicolons, backslashes, CR/LF-injection attempts surviving the write -> read round trip (Task 6).
5. `stark://add` opened with no pairing, garbage base64, or a truncated URL: ignored, no crash, no banner (Task 7).

## File Structure

| Path | Responsibility |
|---|---|
| `ios/Sources/StarkKit/Bridge/BridgeBatch.swift` | Wire types, `BridgeError`, validation to `Event`/`Reminder` |
| `ios/Sources/StarkKit/Bridge/BridgeCodec.swift` | JSON <-> zlib <-> base64url, URL build/parse, size-aware splitting |
| `ios/Sources/StarkKit/Bridge/BridgeAuth.swift` | `SecretStore`, `KeychainSecretStore`, `InMemorySecretStore`, HMAC sign/verify, secret display format, `BridgePairing` |
| `ios/Sources/StarkKit/Bridge/BridgeReplayGuard.swift` | Age window + remembered batch ids |
| `ios/Sources/StarkKit/Bridge/ClaudeBridge.swift` | `handle(url) -> Outcome`, ties everything to `PlannerStore` |
| `ios/Sources/StarkKit/Planner/PlannerStore.swift` | Add `importItems` |
| `ios/Sources/StarkClaudeCore/*.swift` | Process seam, device resolver, add/pair/today commands (`#if os(macOS)`) |
| `ios/Sources/stark-claude/main.swift` | Argument parsing only |
| `ios/App/Stark/Info.plist`, `ContentView.swift`, `SettingsView.swift`, `ClaudeCodeSettingsView.swift`, `StarkApp.swift` | Glue only |
| `.claude/commands/stark.md`, `ios/scripts/install-stark-claude.sh` | Claude Code side |

---

### Task 1: Spike - does `--payload-url` reach a TestFlight build?

**Gate task.** Nothing after this starts until it passes. Needs the owner: they must approve the TestFlight upload (run `ios/App/ship.sh` only after asking) and install the build with their phone unlocked.

**Files:**
- Modify: `ios/App/Stark/Info.plist` (add `CFBundleURLTypes` with scheme `stark`)
- Modify: `ios/App/Stark/Stark/ContentView.swift` (throwaway `.onOpenURL` that sets `store.error = "SPIKE url chars: \(url.absoluteString.count)"`; mark it `// SPIKE - replaced in Task 8`)
- Modify: `docs/superpowers/specs/2026-11-07-claude-code-bridge-design.md` (append a "Spike results" section)

**Interfaces:**
- Produces: the registered `stark` scheme, and measured facts consumed by Tasks 3 and 9: max accepted URL length (`BridgeCodec.maxEncodedBytes` = measured x 0.75, capped at 32768), whether `--terminate-existing` is needed for a running app, the locked-phone failure text, and whether `devicectl device copy from` works on the TestFlight install.

- [ ] **Step 1: Add the URL type to `Info.plist` and the throwaway handler.**
- [ ] **Step 2: Verify in the simulator.** Run: `xcrun simctl openurl booted "stark://add?x=1"`. Expected: the banner shows `SPIKE url chars: 15` (screenshot it).
- [ ] **Step 3: Verify the key survives the build.** Run: `plutil -extract CFBundleURLTypes xml1 -o - <built Stark.app>/Info.plist`. Expected: the `stark` scheme is present (the generated-Info.plist whitelist drops unknown keys; the seed plist merges them).
- [ ] **Step 4: Ask the owner, then run `ios/App/ship.sh`** (commits the build bump). Owner installs the new build from TestFlight and unlocks the phone.
- [ ] **Step 5: Run on the real phone and record each result.** Device id from `xcrun devicectl list devices`.
  - (a) app not running: `xcrun devicectl device process launch --device <id> --payload-url "stark://add?x=1" com.caritos.todo-txt` -> banner appears?
  - (b) app running in background: same command, then again with `--terminate-existing`.
  - (c) phone locked: record the exact error text.
  - (d) URL length: send payloads of 2 KB, 8 KB, 32 KB, 64 KB (`stark://add?x=` plus filler); the banner shows how many chars arrived; record the largest that arrives intact.
  - (e) `xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier com.caritos.todo-txt --source /Documents --destination <empty temp dir>`: works or refused (record the message); delete the temp dir afterwards.
- [ ] **Step 6: Write the results into the spec and commit.** If (a) fails: **stop and report to the owner; do not continue and do not fall back to container writes or the clipboard route (plan B is not approved).**

---

### Task 2: Wire types and validation to models

**Files:**
- Create: `ios/Sources/StarkKit/Bridge/BridgeBatch.swift`
- Test: `ios/Tests/StarkKitTests/BridgeBatchTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct BridgeBatch: Codable, Equatable, Sendable {
      public var v: Int            // must be 1
      public var batch: String     // UUID string
      public var issuedAt: TimeInterval   // epoch seconds
      public var label: String?
      public var items: [BridgeItem]
      public init(v: Int = 1, batch: String, issuedAt: TimeInterval, label: String?, items: [BridgeItem])
      public func models(calendar: Calendar = .current) throws -> BridgeImport
  }
  public struct BridgeItem: Codable, Equatable, Sendable {
      public enum Kind: String, Codable, Sendable { case reminder, event }
      public enum PriorityLevel: String, Codable, Sendable { case low, medium, high }
      public var id: String; public var kind: Kind; public var title: String
      public var notes: String?; public var start: String; public var end: String?
      public var location: String?; public var url: String?
      public var recurrence: BridgeRecurrence?; public var priority: PriorityLevel?
  }
  public struct BridgeRecurrence: Codable, Equatable, Sendable {
      public var freq: RecurrenceRule.Frequency; public var interval: Int?
      public var byDay: [String]?   // "sun"..."sat"
      public var until: String?; public var count: Int?
  }
  public struct BridgeImport: Equatable, Sendable { public var events: [Event]; public var reminders: [Reminder] }
  public enum BridgeError: Error, Equatable, CustomStringConvertible { /* see tests; `description` is the banner text */ }
  public enum BridgeLabel { public static func sanitize(_ raw: String?) -> String?; public static func appending(_ label: String?, to notes: String?) -> String? }
  ```

- [ ] **Step 1: Write failing tests** (one `@Test` each, using a fixed `Calendar` in `America/New_York`): a reminder with `"2026-11-10"` becomes due at start of that day (all-day); a timed event `"2026-11-10T15:00"`/`end "16:30"` keeps both; an all-day event drops `end`; `end` at/before `start` is dropped (as the app does via `EventSchedule.storedEnd`); weekly recurrence with `byDay ["tue","thu"]`, `interval 2`, `until` maps to `RecurrenceRule`; priority low/medium/high -> 9/5/1; `v == 2` throws `unsupportedVersion(2)`; empty items, 201 items, 501-char title, 5001-char notes, reminder without a valid start, bad date text, `until` before start, unknown `byDay`, `interval < 1`, non-http(s) `url`, duplicate item ids, empty id each throw the matching `BridgeError` case naming the item id; `"2026-03-08T02:30"` in New York (DST gap) throws `nonexistentLocalTime`; `"2026-11-01T01:30"` (overlap) resolves to the earlier instant; `BridgeLabel.sanitize("Swift Course!")` == `"swift-course"`, empty/nil -> nil, 40-char input is cut to 32; `appending("swift-course", to: "read ch.1")` == `"read ch.1\n%swift-course"`, to nil == `"%swift-course"`, and is unchanged when the notes already contain the exact token `%swift-course`; the same item decoded from JSON text with unknown extra keys still decodes.
- [ ] **Step 2: Run** `cd ios && swift test --filter BridgeBatchTests`. Expected: FAIL (types undefined).
- [ ] **Step 3: Implement** the types above. Date parsing: split on `T`, build `DateComponents`, use `calendar.date(from:)` and reject when `calendar.dateComponents` of the result does not equal the input (this catches DST gaps). Reuse `Event.scheduled(start:end:allDay:)` and `FormFields.normalizedStart` for all-day handling. Weekday strings map to `Weekday`.
- [ ] **Step 4: Run the filter again.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: bridge wire types and validation`.

---

### Task 3: Codec, URL, splitting

**Files:**
- Create: `ios/Sources/StarkKit/Bridge/BridgeCodec.swift`
- Test: `ios/Tests/StarkKitTests/BridgeCodecTests.swift`

**Interfaces:**
- Consumes: `BridgeBatch`, `BridgeItem` (Task 2); the measured limit from Task 1.
- Produces:
  ```swift
  public enum BridgeCodec {
      public static let maxEncodedBytes: Int   // from Task 1: measured x 0.75, capped at 32_768
      public static func encode(_ batch: BridgeBatch) throws -> Data      // JSON (sorted keys) -> zlib
      public static func decode(_ payload: Data) throws -> BridgeBatch     // throws BridgeError.malformed
      public static func base64URL(_ data: Data) -> String
      public static func data(fromBase64URL: String) -> Data?
      public static func url(payload: Data, signature: Data) -> URL        // stark://add?batch=..&sig=..
      public static func parse(_ url: URL) -> (payload: Data, signature: Data)?   // nil on wrong scheme/host/missing/garbage
      public static func split(items: [BridgeItem], label: String?, issuedAt: TimeInterval,
                               newBatchID: () -> String) throws -> [BridgeBatch]
  }
  ```

- [ ] **Step 1: Write failing tests:** encode/decode round trip equals the input; `base64URL` has no `+ / =` and round-trips; `parse` returns nil for `http://add`, `stark://other`, missing `sig`, non-base64 `batch`; `url(...)` then `parse` round-trips; decoding random bytes throws `malformed`; `split` of 300 small items yields batches each `<= 200` items and whose `base64URL(encode)` length `<= maxEncodedBytes`, preserving item order and total count, with distinct batch ids; a single item bigger than the limit throws `itemTooLarge(id)`.
- [ ] **Step 2: Run** `swift test --filter BridgeCodecTests`. Expected: FAIL.
- [ ] **Step 3: Implement** with `Compression` (`COMPRESSION_ZLIB` via `NSData.compressed(using: .zlib)`/`decompressed`); `split` greedy: add items until adding one would exceed the item or byte limit.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: bridge codec, URL and batch splitting`.

---

### Task 4: Signing, secret store, pairing

**Files:**
- Create: `ios/Sources/StarkKit/Bridge/BridgeAuth.swift`
- Test: `ios/Tests/StarkKitTests/BridgeAuthTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public protocol SecretStore: Sendable { func read() throws -> Data?; func write(_ secret: Data) throws; func delete() throws }
  public final class InMemorySecretStore: SecretStore, @unchecked Sendable { public init(initial: Data? = nil) }
  public final class KeychainSecretStore: SecretStore, @unchecked Sendable { public init(service: String, account: String) }   // errors thrown, never swallowed
  public enum BridgeAuth {
      public static func newSecret() -> Data                       // 32 random bytes (SystemRandomNumberGenerator or SecRandomCopyBytes)
      public static func sign(_ payload: Data, secret: Data) -> Data          // HMAC-SHA256
      public static func verify(payload: Data, signature: Data, secret: Data) -> Bool   // constant time (HMAC.isValidAuthenticationCode)
      public static func displayString(for secret: Data) -> String            // base64url, copy/paste friendly
      public static func secret(fromDisplay: String) -> Data?                 // trims whitespace; nil unless exactly 32 bytes
  }
  public enum BridgePairing {
      public static func ensureSecret(in store: SecretStore) throws -> Data   // create once, then return the same
      public static func reset(in store: SecretStore) throws -> Data          // replace with a new secret
  }
  ```
  `KeychainSecretStore` uses `kSecClassGenericPassword`; on iOS `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

- [ ] **Step 1: Write failing tests (in-memory store only; the real Keychain is verified on the simulator in Task 8 and on the Mac in Task 9):** sign/verify accepts the same payload; flipping one payload byte, one signature byte, or using another secret fails; verify of a wrong-length signature fails without trapping; `secret(fromDisplay:)` round-trips and rejects short/garbage input and tolerates surrounding whitespace; `ensureSecret` returns the same secret on a second call; `reset` returns a different one and `ensureSecret` then returns the new one.
- [ ] **Step 2: Run** `swift test --filter BridgeAuthTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** CryptoKit `HMAC<SHA256>`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: bridge signing and pairing secret`.

---

### Task 5: Replay guard

**Files:**
- Create: `ios/Sources/StarkKit/Bridge/BridgeReplayGuard.swift`
- Test: `ios/Tests/StarkKitTests/BridgeReplayGuardTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public protocol ReplayStore: AnyObject { func load() -> [String]; func save(_ ids: [String]) }
  public final class InMemoryReplayStore: ReplayStore { public init() }
  public final class UserDefaultsReplayStore: ReplayStore { public init(defaults: UserDefaults = .standard, key: String = "bridge.recentBatchIDs") }
  public enum ReplayDecision: Equatable, Sendable { case accept, expired, fromFuture, duplicate }
  public final class BridgeReplayGuard {
      public init(store: ReplayStore, now: @escaping () -> Date, maxAge: TimeInterval = 600,
                  maxFuture: TimeInterval = 120, capacity: Int = 200)
      public func check(_ batch: BridgeBatch) -> ReplayDecision   // pure: records nothing
      public func record(_ batch: BridgeBatch)                    // call only after a successful import
  }
  ```

- [ ] **Step 1: Write failing tests with a fixed clock:** fresh batch accepts; 601 s old -> `expired`; 599 s old accepts; 121 s ahead -> `fromFuture`; after `record`, the same id -> `duplicate`; `check` alone never makes it a duplicate; after recording 201 distinct ids the oldest is evicted (but an evicted id that is still within the age window is accepted again, an old one is `expired`); state survives creating a new guard on the same store.
- [ ] **Step 2: Run** `swift test --filter BridgeReplayGuardTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Order of checks: `fromFuture`, `expired`, `duplicate`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: bridge replay guard`.

---

### Task 6: Store import (all-or-nothing, idempotent)

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/PlannerStore.swift` (add next to `addReminder`)
- Test: `ios/Tests/StarkKitTests/PlannerStoreImportTests.swift` (use the same `makeStore`/`start` helpers pattern as `PlannerStoreTests`)

**Interfaces:**
- Produces:
  ```swift
  public struct ImportOutcome: Equatable, Sendable { public var added: Int; public var alreadyPresent: Int }
  public enum ImportFailure: Error, Equatable { case unreadableMonth(String) }   // payload is the month file name
  @MainActor extension PlannerStore (inside the class, for private access):
  public func importItems(events: [Event], reminders: [Reminder]) throws -> ImportOutcome
  ```
  Behaviour: first load every month a non-recurring item lands in (`YearMonth(date: event.start)`, `YearMonth(date: reminder.dueDate ?? Date())`); if any month is not in `loadedMonths` afterwards, throw `unreadableMonth` **before changing anything**. An item whose id already exists anywhere in the store (recurring or loaded months) is counted in `alreadyPresent` and not added. The rest go through the existing `addEvent`/`addReminder`.

- [ ] **Step 1: Write failing tests:** importing a one-off event, a one-off reminder and a weekly reminder writes them to the right files (month files vs `recurring.ics`) and they survive a fresh store on the same directory; importing the same items again returns `added 0, alreadyPresent N` and leaves files unchanged; a month outside the started window is loaded first (an item 6 months out appears and an existing item in that month is not lost); **an unreadable destination month (write garbage non-UTF8 bytes into that month's file) throws and adds none of the batch's other items**; titles/notes/location containing `\n`, `,`, `;`, `\`, `\r\nBEGIN:VEVENT` and an emoji round-trip through write -> reload unchanged (or, where the serializer must strip CR/LF, with exactly that documented normalisation) and never create an extra component.
- [ ] **Step 2: Run** `swift test --filter PlannerStoreImportTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `importItems` as described. If the injection test shows the serializer lets a CR/LF through, fix it in `ICSSerializer` with its own test in `ICSSerializerTests`.
- [ ] **Step 4: Run** the new tests, then the full `swift test`. Expected: PASS, no regressions.
- [ ] **Step 5: Commit** `feat: PlannerStore.importItems`.

---

### Task 7: `ClaudeBridge.handle(url:)`

**Files:**
- Create: `ios/Sources/StarkKit/Bridge/ClaudeBridge.swift`
- Test: `ios/Tests/StarkKitTests/ClaudeBridgeTests.swift`

**Interfaces:**
- Consumes: Tasks 2-6.
- Produces:
  ```swift
  @MainActor public final class ClaudeBridge {
      public enum Outcome: Equatable, Sendable {
          case ignored                                  // log only, no banner
          case added(count: Int, label: String?)
          case alreadyAdded
          case rejected(String)                         // banner text
          public var notice: String?                    // "Added 6 items (swift-course)", "Already added", the rejection text; nil for ignored
      }
      public init(store: PlannerStore, secrets: SecretStore, replay: BridgeReplayGuard, calendar: Calendar = .current)
      public func handle(_ url: URL) -> Outcome
  }
  ```
  Order: parse URL (nil -> ignored) -> read secret (nil/throws -> ignored) -> verify signature (fail -> ignored) -> decode (fail -> rejected "Couldn't read the request") -> replay check (`duplicate` -> alreadyAdded; `expired`/`fromFuture` -> rejected with a message that mentions the Mac and phone clocks) -> `models(calendar:)` (throws -> rejected(error.description)) -> `store.importItems` (throws -> rejected naming the month file) -> `replay.record` -> `added`. Apply `BridgeLabel.appending` to every item's notes before `importItems`. Log every outcome with `os.Logger`, never the secret, payload or titles.

- [ ] **Step 1: Write failing tests** with an in-memory secret/replay store, a fixed clock and a temp-directory store, building real signed URLs with `BridgeCodec`/`BridgeAuth`: a valid batch returns `added(count: 2, label: "swift-course")` and both items are in the store with `%swift-course` in the notes; the same URL again returns `alreadyAdded`; a URL signed with another secret, an unpaired phone (no secret), a tampered payload byte, wrong host, garbage base64 and a truncated URL each return `ignored` and leave the store untouched; an expired signed batch and a 5-minutes-future one return `rejected`; a signed batch with one invalid item returns `rejected` and adds nothing; a signed batch into an unreadable month returns `rejected` and adds nothing and is **not** recorded (a corrected resend of the same batch id after fixing the file succeeds).
- [ ] **Step 2: Run** `swift test --filter ClaudeBridgeTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter, then the full `swift test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: ClaudeBridge URL handler`.

---

### Task 8: App glue, banner, Settings pairing screen

**Files:**
- Modify: `ios/App/Stark/Stark/StarkApp.swift` (build the `ClaudeBridge` once: `KeychainSecretStore(service: "com.caritos.todo-txt.bridge", account: "pairing")`, `UserDefaultsReplayStore`, guard with `Date.init`), `ContentView.swift` (replace the Task 1 spike handler with `.onOpenURL { outcome = bridge.handle($0) ... }` and a notice banner above the error banner, tap or 4 s to dismiss), `SettingsView.swift` (new "Claude Code" section linking to the screen)
- Create: `ios/App/Stark/Stark/ClaudeCodeSettingsView.swift`
- Test: no new unit tests (logic is Task 4/7); verification is below.

**Interfaces:**
- Consumes: `ClaudeBridge`, `BridgePairing`, `BridgeAuth.displayString`.
- Produces: `ClaudeCodeSettingsView` showing "Paired" state, a **Show secret** reveal, **Copy** (`UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: [.localOnly: true, .expirationDate: now+120s])`), **Reset pairing** (confirmation, then `BridgePairing.reset`), a footer: "Lets Claude Code on your Mac add tasks to Stark. Stark still makes no network connections." Keychain errors surface in an inline error text (never swallowed).

- [ ] **Step 1: Implement the glue and screen.** Remove the `// SPIKE` handler.
- [ ] **Step 2: Build** with the simulator command in Global Constraints. Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Simulator verification** (record screenshots). Open Settings > Claude Code, show and copy the secret (this also proves the real Keychain works). Sending a signed URL needs the CLI, so that half is done in Task 9 Step 5. Here, verify only that an unsigned `xcrun simctl openurl booted "stark://add?batch=AAAA&sig=AAAA"` shows nothing and does not crash.
- [ ] **Step 4: Run** the full `swift test` and the app build once more. Commit `feat: Claude Code bridge in the app`.

---

### Task 9: `stark-claude` CLI core: `add` and `pair`

**Files:**
- Modify: `ios/Package.swift` (add `StarkClaudeCore` library, `stark-claude` executable, `StarkClaudeCoreTests`; all Process-using code wrapped in `#if os(macOS)` so iOS builds of the package are unaffected)
- Create: `ios/Sources/StarkClaudeCore/ProcessRunning.swift`, `DeviceResolver.swift`, `AddCommand.swift`, `PairCommand.swift`, `CLIError.swift`; `ios/Sources/stark-claude/main.swift`
- Test: `ios/Tests/StarkClaudeCoreTests/*.swift`

**Interfaces:**
- Consumes: `BridgeCodec`, `BridgeAuth`, `SecretStore`, `BridgeItem`.
- Produces:
  ```swift
  public struct ProcessResult: Equatable, Sendable { public var status: Int32; public var stdout: String; public var stderr: String }
  public protocol ProcessRunning: Sendable { func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult }
  public struct FoundationProcessRunner: ProcessRunning { public init() }
  public enum CLIError: Error, Equatable, CustomStringConvertible { case notPaired, noDevice, ambiguousDevice([String]), phoneLocked, launchFailed(String), badRequest(String), pullRefused(String) }
  public struct DeviceResolver { public init(runner: ProcessRunning, environment: [String: String]); public func resolve() throws -> String }
  public struct AddRequest: Decodable { public var label: String?; public var items: [BridgeItem] }   // item `id` optional here; the CLI fills missing ones with UUIDs
  public struct AddReport: Equatable { public var itemIDs: [String]; public var batchesSent: Int; public var batchesTotal: Int }
  public struct AddCommand {
      public init(runner: ProcessRunning, secrets: SecretStore, device: DeviceResolver, now: @escaping () -> Date,
                  newID: @escaping () -> String, terminateExisting: Bool)   // value from Task 1 result
      public func run(requestJSON: Data) throws -> AddReport
  }
  public struct PairCommand { public init(secrets: SecretStore); public func run(secretText: String) throws }
  ```
  Launch invocation: `xcrun devicectl device process launch --device <id> --payload-url <url> [--terminate-existing] com.caritos.todo-txt`. Device choice: `STARK_DEVICE` env (name or id) else the single available paired iPhone from `xcrun devicectl list devices --json-output <tmpfile>`; none -> `noDevice`, several -> `ambiguousDevice(names)`. A devicectl failure whose stderr mentions "locked" -> `phoneLocked`; any other -> `launchFailed(stderr)`. Batches are sent in order and sending stops at the first failure; the thrown error carries how many were sent. `main.swift` uses `KeychainSecretStore(service: "com.caritos.stark-claude", account: "pairing")` and prints the report (item ids, "sent N of M batches", reminder that only "sent" is known), exit code non-zero on any `CLIError` with its `description`.

- [ ] **Step 1: Write failing tests with a fake `ProcessRunning`:** device JSON fixtures -> resolves the only available paired iPhone, ignores `unavailable` ones and watches/iPads, honours `STARK_DEVICE`, throws `noDevice` and `ambiguousDevice`; `AddCommand` with a valid request and a paired in-memory store runs devicectl once with a URL whose `BridgeCodec.parse` + `BridgeAuth.verify` + `decode` give back the items, fills missing ids, sets `issuedAt` from `now`; includes `--terminate-existing` only when configured; unpaired -> `notPaired` and no process run; a 300-item request sends several batches in order and stops after a failing second launch reporting 1 of N sent; stderr containing "device is locked" -> `phoneLocked`; an item that fails `BridgeBatch.models()` validation is caught **before** anything is sent (`badRequest` naming the item); `PairCommand` stores a valid 32-byte secret, rejects garbage without writing, and never echoes the secret.
- [ ] **Step 2: Run** `swift test --filter StarkClaudeCoreTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and the full `swift test`. Expected: PASS.
- [ ] **Step 5: Build and verify against the simulator.** Run `swift build -c release --product stark-claude`. `devicectl` cannot reach the simulator, so give `add` a hidden `--print-url` flag that prints the signed URL(s) instead of launching (covered by one extra test). Run `.build/release/stark-claude pair` with the secret copied from the simulator's Settings > Claude Code screen, then `add --print-url` with a two-item JSON file, and open each URL with `xcrun simctl openurl booted "<url>"`. Expected: banner "Added 2 items (label)", both in the agenda; opening the same URL again shows "Already added". Commit `feat: stark-claude add and pair`.

---

### Task 10: `stark-claude today` (best effort)

**Files:**
- Create: `ios/Sources/StarkClaudeCore/TodayCommand.swift`
- Modify: `ios/Sources/stark-claude/main.swift` (add `today [--date yyyy-MM-dd]`)
- Test: `ios/Tests/StarkClaudeCoreTests/TodayCommandTests.swift`

**Interfaces:**
- Consumes: `ProcessRunning`, `DeviceResolver`, `PlannerFile`, `buildAgendaItems`, `groupAgendaByDay`, `DayExport.text`, `AgendaWindow.loadRange(around:)`.
- Produces: `public struct TodayCommand { public init(runner: ProcessRunning, device: DeviceResolver, makeTempDirectory: @escaping () throws -> URL, now: @escaping () -> Date); public func run(day: Date?) throws -> String }`. Pulls `/Documents` with `devicectl device copy from ... --domain-type appDataContainer --domain-identifier com.caritos.todo-txt --source /Documents --destination <temp>`; reads it with `PlannerFile(directory: temp, pendingDirectory: <another temp>)`; expands the day with the app's own functions (same overdue/completion rules, no reimplementation) and returns `DayExport.text`. A refused pull -> `CLIError.pullRefused` with a plain message (exit non-zero). **The temp directory (private data) is always deleted, including on errors.**

- [ ] **Step 1: Write failing tests:** a fake runner that "pulls" by copying a fixture folder (one-off event, a daily reminder in `recurring.ics`, an overdue reminder, a completed one) -> expected text for a given day, in agenda order; the temp directory no longer exists afterwards, also when the runner fails; a non-zero devicectl status -> `pullRefused`; empty folder -> the "(none)" day text.
- [ ] **Step 2: Run** `swift test --filter TodayCommandTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and full `swift test`. Expected: PASS. Commit `feat: stark-claude today`.

---

### Task 11: Claude Code command, install script, docs, device verification

**Files:**
- Create: `.claude/commands/stark.md`, `ios/scripts/install-stark-claude.sh` (builds release and symlinks `~/.local/bin/stark-claude`)
- Modify: `ios/App/Stark/Stark/FAQView.swift` (new entry), `web/public/pages/faq.html` and `web/public/pages/privacy.html` (matching copy; keep `Build @@BUILD_ID@@` footer once), `CLAUDE.md` (dated Done / Not yet verified on device / Deferred log, including the spike results), `docs/superpowers/specs/2026-11-07-claude-code-bridge-design.md` status line

**Interfaces:** none (copy and tooling).

- [ ] **Step 1: Write `.claude/commands/stark.md`:** how to turn the conversation's task list into the request JSON (field shapes from the spec, generate item ids so a resend is idempotent, spread tasks over days, call `stark-claude today --date` first for busy days), "do not ask for approval before adding" (owner's decision), after sending say "sent N of M batches" and name the label to search for, never claim "added" (no return channel), the exact permissions to allow (`Bash(stark-claude:*)`, `Bash(xcrun devicectl:*)`) and a note that a sandboxed session may block devicectl/Keychain.
- [ ] **Step 2: Install script** with `set -euo pipefail`; verify with `bash ios/scripts/install-stark-claude.sh && stark-claude --help`.
- [ ] **Step 3: Docs copy.** FAQ (in-app and web): what the Claude Code bridge is, that it is optional, off until paired, the phone makes no network connection, how to reset pairing. Privacy: the app still makes no network calls; the `stark://add` link only accepts requests signed with a secret that stays in the Keychain on the device. Run `cd web && make test-fast`.
- [ ] **Step 4: Ship and verify on the real phone, TestFlight build** (ask the owner before `ios/App/ship.sh`). Record in `CLAUDE.md` separately as "confirmed on device": `stark-claude pair`; `stark-claude add` with the app closed and with it open; items and `%label` visible in Search; wrong secret ignored; locked-phone message; `today` result (works or the clean refusal).
- [ ] **Step 5: Run the full suite** (`cd ios && swift test`; app build; `cd web && make test-fast`) and commit `docs: Claude Code bridge copy and log`. Then follow superpowers:finishing-a-development-branch (merge locally, per the owner's standing instruction, after the full suite passes on the merged result).
