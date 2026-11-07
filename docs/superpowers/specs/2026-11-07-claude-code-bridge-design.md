# Claude Code bridge: add tasks and events to Stark from the Mac

Date: 2026-11-07. Status: approved 2026-11-07; implemented on branch claude-bridge-impl, device verification of the shipped build pending.

## Intent and why

The owner is learning something, and Claude suggests a set of tasks ("practice X on Tuesday, read Y on Thursday"). Today they type each into Stark by hand. They want to say "put those in Stark" to Claude Code and have them appear in the agenda with no further step. More generally: more automation between their tools.

Hypothesis to test: *"I tell Claude 'dentist Tuesday 3pm' or accept a batch of study tasks, and they appear in Stark."* If that works, extend; if the pairing or foregrounding friction makes them stop using it, stop.

## Goals

1. From Claude Code on the Mac, add reminders and events (one or a batch) to Stark on the owner's iPhone, landing in the agenda immediately, with no approval step.
2. Works with the **TestFlight / App Store build** the owner runs day to day (not only `deploy.sh` development builds).
3. Stark stays fully offline: no network call from the app, no server, no iCloud storage. The only link is the phone being paired and reachable from the Mac (USB or Wi-Fi) and unlocked.
4. Safe without approval: only batches signed with a secret the owner paired are accepted. A web page or other app opening the URL scheme can add nothing.
5. Every add is idempotent, tagged so a batch can be found and cleared later, and reports what it did.
6. Best-effort: Claude can read a day's agenda (the `/today` case) when the phone allows it.

## Non-goals

- Editing, completing, moving or deleting existing items from Claude (add only).
- Any approval/preview step before items land (the owner decided: lands straight away).
- Adding tasks while the phone is away from the Mac (needs a server; rejected, offline stance is non-negotiable).
- Push/silent delivery: items arrive when Claude launches the app, not while it is closed on its own.
- Mac Catalyst target support, Android, other users, multiple phones.
- Undo of a batch (the shared tag makes manual cleanup in Search possible).

## Anti-goals (a failure even if it technically works)

- Any network call from Stark, any new third-party SDK, any data leaving the phone.
- Unsigned or tampered input creating items, or a replayed URL creating duplicates or resurrecting deleted items.
- A silently partial import. A batch is added fully or not at all, and the owner is told which.
- Overwriting or touching existing data files from outside the app (the app remains the only writer).

## Decisions made by the owner

- Items land straight away; no approval.
- Offline stance is non-negotiable; phone connected to the Mac is the go-between.
- Runs against the TestFlight build, so the design must not rely on writing into the app container.
- Accepts Stark coming to the foreground on each add, and a one-time pairing step.
- Reading the schedule is wanted ("see my schedule for that day") but adds are the core.

## Design

### Delivery: URL payload via devicectl

Claude Code runs `xcrun devicectl device process launch --device <phone> --payload-url "<stark://add?...>" com.caritos.todo-txt`. `devicectl` supports `--payload-url` ("a URL to pass to the application for it to open during launch"). Nothing is written into the app container. The app registers the `stark` URL scheme and handles it in `onOpenURL`, which fires for a cold launch and for an already-running app.

**Unverified on TestFlight. The first deliverable is a spike** that proves this path against a real TestFlight build (a build with the scheme registered and a logging handler shipped via `ship.sh`), before the importer is built. If devicectl refuses to launch or pass the URL for a TestFlight install, stop and bring the finding back; do not fall back to container writes without asking.

### Batch format (v1)

JSON, then deflate-compressed (Apple `Compression` framework, no third-party code), then base64url, in a `batch` query parameter, with the signature in `sig`:

```
{ "v": 1, "batch": "<uuid>", "label": "swift-course",
  "items": [ { "id": "<uuid>", "kind": "reminder" | "event",
               "title": "...", "notes": "...",
               "start": "2026-11-10T15:00" (local, no zone; "2026-11-10" = all-day),
               "end": "..." (events only, optional), "location": "...", "url": "...",
               "recurrence": { "freq": "daily|weekly|monthly|yearly", "interval": 1,
                               "byDay": [...], "until": "date", "count": n },
               "priority": "low|medium|high" (reminders only) } ] }
```

Maps onto the existing models: `Event`/`Reminder`, `RecurrenceRule`, `ReminderPriority`, all-day via the existing date-only convention (reminders store start-of-day). Item ids are the supplied UUIDs, so retries are idempotent. Unknown `v` is rejected. Encoded size is capped (about 32 KB); the CLI splits larger requests into several batches.

### Authentication

- **Pairing:** Settings gets a **Claude Code** row. First open generates a 32-byte secret, stored in the Keychain via the existing throwing Keychain store, and shows it with a copy button. The owner runs `stark-claude pair` on the Mac and pastes it; the CLI stores it in the Mac login Keychain (`security`), never prints it, never writes it to disk or the repo. A "Reset pairing" action regenerates it.
- **Signing:** `sig` = HMAC-SHA256 (CryptoKit, constant-time compare) over the exact payload bytes. Unsigned, wrongly signed or modified batches are ignored and logged (FileLogger), with no UI beyond a quiet "Ignored an unrecognised request" line in the log.
- **Replay:** the app remembers recent batch ids (bounded, UserDefaults) and treats a repeat as a no-op, so replaying a captured URL cannot recreate items the owner deleted.

### Import in the app

All logic in StarkKit (testable), thin glue in the app target: `onOpenURL` -> `ClaudeBridge.handle(url:)` -> verify -> decode -> validate -> store.

- **All or nothing per batch.** Any invalid item rejects the whole batch with a visible banner naming the problem (and a log line); nothing is added.
- Items go through the normal store add path (month routing, `recurring.ics` for recurrences, `PlannerFile` queueing), after `store.loadMonths(covering:)` for every month touched. Unreadable destination month aborts the batch with nothing changed.
- The batch `label` is appended to each item's notes as a `%label` token, so it is findable in Search (tags are plain text in this app). This is the only marking; no new model field.
- On success a short banner: "Added N items (label)". On a repeated batch: "Already added".
- Adds are idempotent by item id inside the store (existing rule: store mutations are idempotent).

### Mac side: `stark-claude` CLI + Claude Code command

An executable target in the StarkKit package (the package already builds for macOS 14), subcommands:

- `pair`: store the secret (above).
- `add <file|->`: read a request JSON (same item shape, no signature), build and sign batches, split by size, resolve the phone, run `devicectl ... process launch --payload-url`, print what was sent and the exit state. Fails loudly with a clear message for: phone not reachable, phone locked, no pairing secret, devicectl error. Process execution sits behind a protocol seam so tests use a fake runner.
- `today [--date]`: **best effort.** Pulls `Documents` with `devicectl device copy from` into a temp directory and expands the day with the app's own `buildAgendaItems`, printing the agenda. If the pull is refused for this install, say so plainly and exit non-zero. Spike this early too; it may not work for TestFlight builds.
- Device selection: `STARK_DEVICE` env or the single available paired iPhone; error if ambiguous.

A project Claude Code command (`.claude/commands/stark.md`) tells Claude how to turn a conversation's task list into the request JSON, to call `today` first to avoid piling tasks on a full day, to report exactly what was sent, and never to ask for approval before adding (owner's decision).

## Constraints

- Swift 6 / StarkKit pure logic with Swift Testing; test first (red/green) for all logic. Fakes behind seams: process runner, Keychain, clock.
- No logic in views. No `Date()` in views.
- No absolute paths persisted. No secrets in the repo, transcripts or logs (redact).
- Do not add the URL scheme's handler anywhere that processes unsigned input.
- Pending UI state keyed by stable ids (batch id / item id).
- Run in a worktree. `ship.sh` bumps the build; the spike needs one TestFlight upload.

## Docs that must change with it ("done" includes this)

- `FAQView` (in-app) and `web/public/pages/faq.html`: a short "Claude Code bridge" entry (what it is, that it is optional and off until paired, offline, how to reset pairing).
- `web/public/pages/privacy.html`: state the app still makes no network calls, the URL scheme only accepts batches signed with the owner's pairing secret, and the secret stays in the Keychain.
- Settings row and this project's `CLAUDE.md` dated Done / Not yet verified on device / Deferred log.

## Verification

- Unit: codec round-trip, signature accept/reject/tamper, replay, size cap and splitting, validation (each field), recurrence mapping, all-day, store import incl. idempotency and unloaded-month case, CLI request building with the fake runner.
- Simulator: `xcrun simctl openurl` with a signed URL adds items; unsigned is ignored.
- **On the real phone, TestFlight build** (recorded separately as "confirmed on device"): `stark-claude add` from the Mac adds a batch while Stark is closed and while it is open; locked-phone error message; wrong secret ignored; `today` result (works or clean refusal).

## Details settled after the builder check (author's calls)

- **Spike pass criteria:** on a TestFlight build, `--payload-url` must reach `onOpenURL` (a) with the app not running, (b) with the app backgrounded/running, (c) record what happens on a locked phone (expected: devicectl fails; the CLI reports "phone locked"). If (b) only works with `--terminate-existing`, the CLI uses it. Also measure the largest URL devicectl and iOS accept, and set the batch split size from that, not from the 32 KB guess.
- **Signature covers the transmitted bytes** (the compressed payload exactly as sent, not the JSON re-serialised), so `v`, `batch`, `label` and every item are bound. Deflate output is not canonical, so verify before decompressing.
- **Replay:** the signed payload carries `issuedAt`. The app rejects a batch older than 10 minutes or more than 2 minutes in the future, and also keeps the last 200 batch ids. Both clocks are network-synced. An evicted id with an expired `issuedAt` is still rejected.
- **Partial multi-batch failure:** the CLI can only report **"sent"**, never "applied" (no return channel). It sends batches in order, stops at the first devicectl failure, and prints which batches were sent. Split so each batch is independently valid (whole items only). The command file tells Claude to say "sent N of M" and to ask the owner to glance at the banner/Search, not to claim success.
- **Times:** `start`/`end` are interpreted in the **phone's current time zone** at import. A local time that does not exist (DST gap) rejects the batch; an ambiguous one (DST overlap) takes the first occurrence.
- **Label:** sanitised to lowercase `[a-z0-9-]`, max 32 characters, one token; skipped if the notes already contain that exact `%label`.
- **Pairing secret:** the copy button uses a local-only pasteboard item (no Universal Clipboard hand-off to other devices); Keychain class is `whenUnlockedThisDeviceOnly` (verification only happens with the app launched and the phone unlocked, and the secret never leaves this phone via backup).
- **Permissions:** the CLI needs `devicectl` and the Mac login Keychain; the command file lists the exact `Bash` permissions to allow, and the build documents that a sandboxed session may block them.

## Left to the builder

CLI argument names, exact JSON field spellings beyond the shape above, banner copy, where the sigil/label token goes in notes, the bounded replay-set size, the Settings row layout, how the CLI discovers the phone.

## Calls made by the author (not stated by the owner)

- URL scheme + HMAC pairing rather than a Shortcuts/AirDrop route.
- All-or-nothing batches; `%label` in notes as the batch marker; no undo.
- `today` is best-effort and not a blocker for shipping adds.
- Spike-first ordering because both devicectl paths are unverified on TestFlight.

## Spike results (2026-11-07, iPhone 16 Plus, Stark 2.0.21 build 23, uploaded with ship.sh)

Caveat: the device reports `builtByDeveloper: true` for this install. Build 23 was only ever produced by `ship.sh`, so this is most likely how TestFlight installs report, but it was not independently confirmed.

- **Delivery works.** `devicectl device process launch --payload-url "stark://add?..."` reached `onOpenURL` with the app not running (cold launch) and with the app already running and no `--terminate-existing`. No "Open in Stark?" prompt was reported; the banner simply appeared. The CLI does not need `--terminate-existing`.
- **URL length:** 2 KB, 8 KB, 32 KB and 64 KB (65,536 characters) were all accepted by devicectl and received by the app. Length is not the limit; the 32 KB cap in this design stands (not the 48 KB the plan's formula gives).
- **Locked phone: silent drop.** devicectl prints "Launched application" and exits successfully, but the URL is NOT delivered (the app did not come to the foreground and, once opened, still showed the previous URL). The CLI cannot rely on an error. **The CLI must check `xcrun devicectl device info lockState --device <id>` first and refuse when `passcodeRequired: true`** (it reports `false` when unlocked and `true` when locked; verified both).
- **`today` pull works:** `devicectl device copy from --domain-type appDataContainer --domain-identifier com.caritos.todo-txt --source /Documents` returned the month files from this install.
- Not tested: a screen-on-but-locked-in-use edge case, and whether a URL sent while locked is ever delivered later (it was not, after unlock).
