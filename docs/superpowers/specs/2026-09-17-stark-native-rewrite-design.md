# Stark Native Rewrite — Design

Date: 2026-09-17

## Overview

**Goal:** Replace Stark's Expo/React Native mobile app with a native
Swift/SwiftUI app, built in the same style as the user's `spool` project
(`~/src/spool`): a pure-logic SwiftPM package plus a thin SwiftUI app
target, TDD throughout the package, CLI-only build/ship tooling (no EAS).

**Product pivot:** Stark moves away from the `todo.txt` single-line-text
format entirely. The new app is a Fantastical-inspired blended
calendar+reminders app: a single timeline mixing **Events** and **Tasks**,
each a distinct data type, backed by the app's own `.ics`-based storage —
not a sync target for the user's actual Apple Calendar/Reminders (no
EventKit).

**Ships as:** an update to the existing App Store listing ("Stark: To Do
List & Calendar", Apple ID 6772774783), same bundle identifier
`com.caritos.todo-txt`. `mobile/` (the Expo app) stays in the repo,
untouched, until this native app reaches parity and actually ships —
it is not deleted as part of this work. `shared/`, `console/`, and `web/`
are unaffected; they keep the `todo.txt` format for CLI/web use. The new
native app does not share code with them — it is its own self-contained
Swift codebase under `ios/`.

**First sub-project (MVP) scope:**
- Blended agenda/day view (events + tasks together, by date)
- Add / Edit / Delete Events and Tasks (structured forms, no NL parsing)
- Recurrence via `RRULE`/`EXDATE`
- Month calendar grid view
- Local-only storage (Documents directory)

**Explicitly deferred to later sub-projects:**
- iCloud Drive folder-picker storage mode (Settings toggle, security-scoped
  bookmark) — same UX Stark's Expo app already has; ported once local-only
  is proven
- Natural-language quick add (e.g. "lunch tomorrow 1pm")
- EventKit/CalDAV/Google Calendar integration of any kind
- Search screen, Year view, birthday/anniversary age badges, multi-day
  event end-date badges — all present in the Expo app today, all
  candidates for follow-on sub-projects once the native core is solid

## Relationship to prior work

An earlier, uncommitted spec/plan pair (`2026-09-15-calendar-app-design.md`
/ `-v1.md`, for an app called "persistence-of-memory") explored similar
ground but reached different conclusions on several points that this spec
deliberately overrides:

| | persistence-of-memory (2026-09-15) | This spec |
|---|---|---|
| App identity | New app, `com.caritos.persistence-of-memory` | Replaces Stark, `com.caritos.todo-txt` |
| Storage location | Private iCloud **ubiquity container** | Local Documents (iCloud Drive folder picker deferred) |
| Data model | Unified `CalendarItem` (kind: event/reminder) | Separate `Event` + `Task` types |
| Recurrence encoding | Custom `X-EVERY`/`X-FREQ-DAY` properties | Standard `RRULE`/`EXDATE` |

The storage choice matters most: a private ubiquity container is exactly
what Stark's own `mobile/` app tried and abandoned (see that project's
CLAUDE.md), because it doesn't show up in Finder/Files on a Mac without a
locally-installed counterpart app — which defeats the actual goal here
(easier desktop sharing via a plain `.ics` file).

Four pieces from that earlier spec **are** carried forward, adapted:
1. One `.ics` file per calendar month (file layout)
2. A `DateMath` utility module (ISO-date-string arithmetic)
3. A pending-write queue for save failures
4. Skip-just-the-malformed-block, not fail-the-whole-file, on parse errors

The old spec/plan files should be deleted once this spec is approved,
since they describe an app that will not be built.

## Project structure

New top-level `ios/` directory, independent of `shared/`/`console/`/`web/`/`mobile/`:

```
ios/
├── Package.swift                      ← SwiftPM package "StarkKit"
├── Sources/StarkKit/
│   ├── DateMath.swift                 ← ISO-date-string arithmetic (ported)
│   ├── Models/
│   │   ├── Event.swift
│   │   ├── Task.swift
│   │   └── RecurrenceRule.swift
│   ├── ICS/
│   │   ├── ICSParser.swift            ← VEVENT/VTODO → Event/Task
│   │   └── ICSSerializer.swift        ← Event/Task → VEVENT/VTODO
│   ├── Planner/
│   │   ├── OccurrenceExpander.swift   ← expands RRULE into dated occurrences
│   │   ├── PlannerFile.swift          ← month-file + recurring.ics I/O, pending-write queue
│   │   └── PlannerStore.swift         ← in-memory cache, CRUD, month loading policy
├── Tests/StarkKitTests/
└── App/
    ├── deploy.sh                      ← build+install+launch on device (xcodebuild + devicectl)
    ├── ship.sh                        ← archive+export+upload to App Store Connect (xcodebuild + ASC API key)
    ├── ExportOptions.plist
    └── Stark/Stark.xcodeproj + Stark/*.swift (SwiftUI app target)
```

Same split as `spool`: **StarkKit** holds every bit of testable logic;
the Xcode app target holds only SwiftUI views and is verified manually,
not unit-tested.

## Data model

Priority is native iCal 1–9 (no A–Z, since this isn't inherited from
`todo.txt` anymore):

```swift
struct Event {
    var id: String              // UID
    var title: String
    var notes: String?
    var start: Date
    var end: Date?
    var isAllDay: Bool
    var location: String?
    var recurrence: RecurrenceRule?
    var exceptionDates: [Date]  // EXDATE
}
```

(Birthday/anniversary as a distinct `Event` category, with the age-badge
display the Expo app has today, is deferred along with that feature — see
Non-Goals. Adding it later is a one-field, additive model change, not a
migration.)

```swift
struct Task {
    var id: String              // UID
    var title: String
    var notes: String?
    var dueDate: Date?
    var isCompleted: Bool
    var completedDate: Date?
    var priority: Int?          // iCal PRIORITY 1-9, nil = none
    var recurrence: RecurrenceRule?
    var exceptionDates: [Date]
}

struct RecurrenceRule {
    enum Frequency { case daily, weekly, monthly, yearly }
    var frequency: Frequency
    var interval: Int           // INTERVAL
    var byDay: [Weekday]?       // BYDAY
    var byMonthDay: Int?        // BYMONTHDAY
    var count: Int?             // COUNT
    var until: Date?            // UNTIL
}
```

`Event` ↔ `VEVENT`, `Task` ↔ `VTODO`. `ICSParser`/`ICSSerializer` only
need to handle the subset of RFC 5545 this app itself emits — no need to
preserve arbitrary third-party `.ics` quirks, since nothing else writes
to these files.

## Storage model

### File layout

- **`recurring.ics`** — every `Event`/`Task` that has a `RecurrenceRule`,
  regardless of how far in the past it started. Always loaded, in full,
  on every launch. This is a deliberate fix to a gap in the
  persistence-of-memory spec: that design stored a recurring item once,
  in its *first-occurrence month's* file, but only ever loaded "current
  month ± 1" lazily — a recurring master from two years ago would never
  be found. Keeping all recurring masters in one small, always-loaded
  file removes the gap entirely without losing the "don't duplicate a
  recurring item across every month it recurs into" benefit.
- **`YYYY-MM.ics`** (e.g. `2026-09.ics`) — every non-recurring `Event`/`Task`
  whose date falls in that month, plus **completion records**: when a
  recurring `Task`'s occurrence is completed, that occurrence's date is
  added to `exceptionDates` on the master in `recurring.ics`, and a
  separate one-off completed `Task` is appended to the month file for the
  date it was completed (mirroring `applyDone`'s "append a completed
  copy" pattern from the old todo.txt app).

Rejected (per the reasoning already validated in persistence-of-memory's
spec): one file per event (too many tiny files), and SQLite. SQLite isn't
a local-only concern today, but iCloud Drive file sync operates on whole
files, not transactions, which risks corruption for a database file — so
choosing `.ics` now avoids a storage-format migration when the deferred
iCloud Drive mode is built.

### `PlannerFile` (storage layer)

- `loadRecurring()` / `loadMonth(_:)` / `saveMonth(_:items:)` /
  `saveRecurring(_:)` — read/write the files above from the local
  Documents directory (no ubiquity container APIs needed for local-only
  storage; `NSFileCoordinator` etc. become relevant once the deferred
  iCloud Drive mode is built).
- **Pending-write queue**: on a save failure, the fully-serialized file
  content is written to a local-only fallback location keyed by file name
  (e.g. `Library/PendingWrites/2026-09.ics`), coalesced (only the latest
  write per file is kept), and retried on next app launch/foreground.
  Clears once the retry succeeds.
- **Malformed content**: a parse error in one `VEVENT`/`VTODO` block logs
  a warning and skips just that block — never fails the whole file load.
- A missing file (month or `recurring.ics`) means "no items yet," not an
  error.

### `DateMath`

Ported from persistence-of-memory's Task 1: ISO ("YYYY-MM-DD") date-string
arithmetic — `addDays`, `daysInMonth`, `weekday`, `isoDate(from:)`,
`components(_:)`. Used by `OccurrenceExpander` and the month-grid/agenda
views. Pure, no I/O — fully unit-testable.

## Recurrence & completion semantics

Full iCalendar `RECURRENCE-ID` single-instance overrides are skipped —
they mainly exist for cross-app interop, and nothing else reads this file
live. Instead:

- **Completing one occurrence of a recurring `Task`**: add that
  occurrence's date to `exceptionDates` on the master (in
  `recurring.ics`), and append a non-recurring completed `Task` to the
  relevant month file (`isCompleted: true`, `completedDate` set).
- **Non-recurring `Task`**: completing it flips `isCompleted`/`completedDate`
  in place; undo flips it back.
- `OccurrenceExpander.expand(event/task, in: dateRange)` is the single
  source of truth for turning a recurring `Event`/`Task` into concrete
  dated occurrences for the agenda — respects `recurrence.until`,
  `recurrence.count`, and `exceptionDates`.
- An incomplete `Task` occurrence whose date has passed is surfaced
  pinned to today, not silently hidden (matches the Expo app's overdue
  pinning).

## State management: `PlannerStore`

`ObservableObject`, app-wide:

- Loads `recurring.ics` fully on launch. Eagerly loads the current
  month's file ± 1 month; lazily loads additional months as the user
  navigates the month grid.
- Every mutation (add/edit/done/undo/delete) resolves to exactly one
  affected file (a non-recurring item's month file, or `recurring.ics`
  for a recurring master's own fields/exceptions), applies it to the
  in-memory cache first for instant UI feedback, then writes through via
  `PlannerFile`.
- Exposes `error: String?`, reflecting pending-write queue state.

## UI layer

- `AgendaView` — blended day-by-day list (events + tasks), built on
  `OccurrenceExpander` output for a rolling window, sorted by time
  (all-day/multi-day first, then timed, untimed tasks grouped with
  untimed events).
- `MonthGridView` — month calendar grid; tapping a date scrolls/jumps
  `AgendaView` to it. Swiping between months triggers `PlannerStore`'s
  lazy month loading.
- `AddItemView` — structured form (no NL parsing in MVP), type toggle
  (Event/Task), reusing the Braun/Bauhaus design tokens ported to a Swift
  `Theme.swift` (Colors/Fonts/Spacing) — one accent color, JetBrains Mono,
  hard edges.
- `EditItemView` — detail/edit sheet, mirroring the Expo app's Task
  Detail: delete confirmation differs for recurring vs one-off items.

## Testing strategy

Swift Testing (`import Testing`, `@Test`, `#expect`) — matching `spool`'s
actual precedent, not XCTest (which the older persistence-of-memory plan
assumed).

- `DateMathTests`, `RecurrenceRuleTests`, `OccurrenceExpanderTests` — pure
  logic, no I/O.
- `ICSParserTests` / `ICSSerializerTests` — round-trip Event/Task ↔
  VEVENT/VTODO text, including the malformed-block-skip behavior.
- `PlannerFileTests` — against a temp local directory: read/write
  round-trip, missing-file-is-empty, pending-write-queue coalesce/retry.
- `PlannerStoreTests` — mutation → correct file targeted → cache updated.
- UI views: not unit-tested, verified manually in the simulator, per
  `spool`'s established pattern for thin SwiftUI/adapter layers.

## Build & deploy tooling

Adapted directly from `spool/ios/App/{deploy.sh,ship.sh}`:

- `deploy.sh` — `xcodebuild` (Debug) + `xcrun devicectl` to build,
  install, and launch on a connected physical iPhone. No Metro, no dev
  client concept at all (this isn't Expo).
- `ship.sh` — `xcodebuild archive` + `-exportArchive` with an App Store
  Connect API key (`~/.appstoreconnect/private_keys/AuthKey_<ID>.p8`),
  uploading straight to TestFlight. Bumps `CURRENT_PROJECT_VERSION` in
  `project.pbxproj` itself (no EAS remote build-number counter exists for
  a fully native build).
- Since the bundle ID (`com.caritos.todo-txt`) already has an App Store
  listing and existing distribution certificate, `-allowProvisioningUpdates`
  should let `xcodebuild` fetch/reuse the existing profile automatically,
  same as `spool`'s scripts do for a fresh bundle ID.

## Workflow

Mirrors how `spool`'s native rewrite was actually built:

1. This spec, committed.
2. `writing-plans` skill produces an implementation plan
   (`docs/superpowers/plans/2026-09-17-stark-native-rewrite.md`), structured
   like `spool`'s: a **Global Constraints** section, then **Part A**
   (the `StarkKit` package: one task per file, each stating **Files** +
   **Interfaces** up front, strict TDD red→green→commit cycles with exact
   `swift test --filter X` commands), then **Part B** (the Xcode app
   target).
3. **Part B's first step — creating the Xcode project itself — requires
   Xcode's GUI and cannot be dispatched to a subagent** (no CLI tool
   scaffolds a new SwiftUI App project). That one step is done by hand;
   subagent-driven work resumes afterward for wiring views to `StarkKit`.
4. Execution happens in an isolated git worktree (per standing
   preference), subagent-driven, finishing as a clean commit (or commits)
   via the `finishing-a-development-branch` skill.
