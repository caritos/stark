# Native iOS App: iCloud Drive Storage — Design

Date: 2026-09-22

## Background

The native Swift app (`ios/`) currently stores its data in its own app-sandboxed
local Documents directory only (`recurring.ics` + one `YYYY-MM.ics` per month,
via `PlannerFile`/`PlannerStore`) — see "Native iOS App (`ios/`)" in the root
`CLAUDE.md`. There is no Settings screen, no entitlements file, and no
iCloud/ubiquity/bookmark code anywhere in `ios/` yet; this is greenfield.

The goal (originating from issue #98, which surfaced the confusion that no
`.ics` files were showing up in the user's iCloud Drive "Stark" folder): make
the native app's data viewable and editable from a Mac as well as an iPhone,
the same way the Expo app (`mobile/`) already does for `todo.txt` — see
`docs/superpowers/specs/2026-08-21-icloud-drive-storage-design.md` and the
"Storage: local by default, with an optional iCloud Drive mode" section of
`CLAUDE.md`.

**Key difference from the mobile precedent:** `todo.txt` is one line per task
— trivially hand-editable in any text editor. The native app's format is
`.ics` (iCalendar: `BEGIN:VEVENT`/`RRULE`/`EXDATE` blocks). It is still plain
text and can be hand-edited, but it is far less forgiving of mistakes than
todo.txt's flat `key:value` lines. The user has explicitly chosen to accept
this trade-off for now (see Decisions) rather than build a friendlier desktop
editing surface (e.g. via EventKit/Calendar.app) or a Mac companion app.

## Decisions already made with the user

1. **Desktop editing surface:** raw `.ics` files in a Finder-visible iCloud
   Drive folder — the same mechanism as mobile, not an EventKit/Calendar.app
   integration and not a Mac/Catalyst companion app.
2. **Foreground refresh:** when the app returns to the foreground, re-read
   `recurring.ics` and every already-loaded month file from disk, discarding
   the in-memory cache for those files, so a Mac edit made while the app was
   backgrounded is picked up without a force-quit. No live `NSMetadataQuery`
   watching while the app is actively in the foreground — out of scope for
   this pass (see Non-goals).
3. **Architecture:** introduce a `PlannerDirectoryAccess` protocol that
   `PlannerFile` delegates raw I/O to, with `LocalDirectoryAccess` (today's
   behavior, unchanged) and a new `ICloudDirectoryAccess` implementation,
   rather than resolving a bookmark externally and handing `PlannerFile` a
   raw `URL`, and rather than two parallel `PlannerFile` types.

## Architecture

### `PlannerDirectoryAccess` (new, `Sources/StarkKit/Planner/`)

```swift
protocol PlannerDirectoryAccess {
    /// nil means the file genuinely doesn't exist yet — not an error.
    func read(fileName: String) throws -> String?
    func write(fileName: String, content: String) throws
}
```

**`LocalDirectoryAccess`**: wraps a plain `URL` (the app's Documents
directory). Implements `read`/`write` with exactly the `FileManager` /
`String(contentsOf:encoding:)` / `content.write(to:atomically:true,encoding:)`
calls `PlannerFile` uses today. Zero behavior change for local mode — this is
a pure refactor of the existing code into the new shape.

**`ICloudDirectoryAccess`**: holds a security-scoped bookmark (`Data`) and a
`onBookmarkRefreshed: (Data) -> Void` callback (see Stale bookmarks, below).
Each `read`/`write` call:

1. Resolve the bookmark (`URL(resolvingBookmarkData:...)`) to get the folder
   URL and an `isStale` flag.
2. `url.startAccessingSecurityScopedResource()`, with a `defer` to stop.
3. For a **read**: trigger `startDownloadingUbiquitousItemAtURL:` on the
   target file and poll `NSURLUbiquitousItemDownloadingStatusKey` (0.5s
   interval, 60 attempts — same pattern as the global CLAUDE.md's documented
   iCloud read recipe) before reading, in case the file is a cloud-only stub
   because it was just edited on the Mac.
4. Do the actual I/O inside `NSFileCoordinator.coordinate(readingItemAt:...)`
   / `coordinate(writingItemAt:...)`, using the coordinator's callback-provided
   URL (not the original one) for the real `FileManager`/`String` call.
   Writes use `atomically: false` (required inside iCloud-synced locations;
   atomic writes create a forbidden `.tmp` file first).
5. If `isStale` was true, re-create a fresh bookmark from the resolved URL
   and invoke `onBookmarkRefreshed` so the caller (`PlannerConfig`, see below)
   persists it — `ICloudDirectoryAccess` itself has no knowledge of where
   config is stored.
6. A resolution failure (folder deleted, iCloud signed out, un-refreshable
   stale bookmark) throws, propagating up exactly like a real I/O error.

### `PlannerFile` changes

Constructor changes from `(directory: URL, pendingDirectory: URL, ...)` to
`(access: PlannerDirectoryAccess, pendingDirectory: URL, ...)`. `load`/`save`
delegate to `access.read`/`access.write` instead of calling `FileManager`
directly. The pending-write-to-`Library/PendingWrites` fallback/retry logic
(`clearPendingWrite`, `retryPendingWrites`, `pendingWriteCount`) is unchanged
— it stays a local directory regardless of storage mode, since it is
non-user-visible retry bookkeeping, not user data.

### `PlannerStore` changes

One new method:

```swift
/// Re-reads recurring.ics and every already-loaded month file from disk,
/// discarding the in-memory cache for those files, then rebuilds. Called on
/// every foreground transition so a change made elsewhere (e.g. edited on a
/// Mac while this app was backgrounded) is picked up without a relaunch.
/// A read failure here behaves like any other PlannerFile read failure:
/// sets `error`, leaves the previously-loaded in-memory state untouched.
public func refreshFromDisk()
```

Implementation: re-run the same logic as `start()`'s recurring load, and for
each `YearMonth` already in `loadedMonths`, re-run `file.loadMonth` and
replace that month's entries (bypassing `loadMonth`'s existing "already
loaded, skip" guard, which exists for the different purpose of not re-reading
a month the agenda scrolls past repeatedly in the same session).

`ContentView`'s existing `scenePhase == .active` handler (already used for
the day-rollover check, per "The window follows the calendar past midnight"
in `CLAUDE.md`) also calls `store.refreshFromDisk()` there.

## Folder picking & config persistence

### Picking a folder

SwiftUI's `.fileImporter(isPresented:allowedContentTypes: [.folder])` is used
directly — no custom native module is needed here (unlike mobile's Expo
module), since this is native Swift/SwiftUI with first-party folder-picking
support.

Flow (mirrors mobile's collision-aware open-mode design — not the earlier,
superseded export-mode version):

1. Settings → "Use iCloud Drive" → `.fileImporter` opens in folder-picking
   mode (suggests "Stark" as a folder name via the picker's own UI, same as
   mobile's copy).
2. On pick: `url.startAccessingSecurityScopedResource()` immediately, create
   a bookmark via `url.bookmarkData()` (iOS bookmark options — no
   `.withSecurityScope`, that flag is macOS-only).
3. Check the folder for an existing `recurring.ics` or any `YYYY-MM.ics`.
   - **Empty folder:** copy the app's current local files into it directly,
     no prompt.
   - **Folder already has Stark files:** destructive-confirm alert with two
     choices — *"Use iCloud's files"* (read what's already there; local data
     is not deleted, just no longer the active store) or *"Keep this
     device's files"* (overwrite the iCloud folder's contents with the
     local files) — same two-choice shape as mobile's `handleUseICloud`.
4. Persist the new `PlannerConfig` (mode: iCloud, the bookmark, the folder's
   display name).
5. Swap the running `PlannerStore`'s access to a new `ICloudDirectoryAccess`
   and call `store.refreshFromDisk()` (or re-run `start()`) so the UI reflects
   the newly active folder immediately, without requiring a relaunch.

### `PlannerConfig` (new)

A small UserDefaults-backed type (no existing config layer exists in `ios/`
yet, and this is simple enough not to need a JSON file the way mobile's
`todo-config.json` does):

```swift
struct PlannerConfig {
    enum Mode { case local, icloud }
    var mode: Mode
    var icloudBookmark: Data?
    var icloudFolderName: String?
}
```

`StarkApp.makeStore()` reads `PlannerConfig` at launch to decide whether to
construct `LocalDirectoryAccess` or `ICloudDirectoryAccess`.

### "Switch to Local"

Destructive-confirm action in Settings: writes the store's current in-memory
events/reminders back to the local Documents directory (all currently loaded
months + recurring), then resets `PlannerConfig` to local mode and swaps the
running store's access back to `LocalDirectoryAccess`.

### Stale / broken bookmarks

A transparently-refreshed stale bookmark (`isStale == true` but still
resolvable) updates `PlannerConfig` via `ICloudDirectoryAccess`'s
`onBookmarkRefreshed` callback with no user-visible effect. A bookmark that
fails to resolve at all (folder deleted, iCloud signed out) surfaces through
`store.error` like any other read/write failure; Settings additionally shows
a "Reconnect iCloud Folder" affordance in that state (re-runs the picker flow
in step 1 above) rather than silently falling back to local storage.

## Settings screen (new)

No Settings screen exists in the native app yet. Smallest version that does
this one job:

- A gear-icon `FlatToolbarButton` (leading placement, alongside the existing
  "Add" button at `.primaryAction`) opens a sheet: `SettingsView`.
- Shows current mode: `LOCAL (this device only)` or `ICLOUD DRIVE —
  <folderName>`.
- **Local mode:** one button, "Use iCloud Drive" (triggers the picker flow
  above).
- **iCloud mode:** one button, "Switch to Local" (destructive-confirm, as
  above). If the bookmark is currently broken, also: "Reconnect iCloud
  Folder".
- No other settings live here yet — room to grow, not designed for future
  sections beyond this.

## Error handling

Unchanged shape from what `PlannerStore`/`ContentView` already do: a read
failure sets `store.error`, surfaced by `ContentView`'s existing banner (see
line ~45, `if let error = store.error`). A file that genuinely doesn't exist
yet (nil from `PlannerDirectoryAccess.read`) is not an error, in either mode.
No new entitlements are required — `.fileImporter` grants access via
per-pick user consent, unlike an app-private ubiquity container
(`com.apple.developer.ubiquity-container-identifiers`), which is the thing
that actually needs an entitlement and which this design does not use.

## Testing

- `PlannerFile`/`PlannerStore` logic — including the new `refreshFromDisk()`
  — stays fully unit-tested in Swift Testing against a fake, in-memory
  `PlannerDirectoryAccess` test double. The existing `PlannerFileTests`/
  `PlannerStoreTests` are updated to construct `PlannerFile` with a
  `LocalDirectoryAccess`-backed or fake access value instead of a raw
  `directory: URL`, with identical coverage.
- `ICloudDirectoryAccess`'s bookmark resolution / `NSFileCoordinator` /
  download-stub-polling plumbing is only meaningfully verifiable on a real
  device with a real iCloud Drive folder — consistent with this repo's
  existing preference for real-device native testing (`CLAUDE.md`'s
  "Testing and deploying" section) and with mobile's iCloud design doc's own
  testing section. No unit test attempts to fake real iCloud behavior.
- Manual on-device pass (`ios/App/deploy.sh`): pick a folder, edit a `.ics`
  file from a Mac text editor, background then foreground the iPhone app,
  confirm the change appears; edit on the phone, confirm the Mac sees it;
  verify "Switch to Local" round-trips the current data correctly; verify
  the collision alert's two choices both behave as described.

## Non-goals

- Live `NSMetadataQuery`/file-presenter watching while the app is actively
  foregrounded (decided above — foreground-transition refresh is enough for
  v1; real-time watching is the most complex and failure-prone piece per the
  global CLAUDE.md's iCloud lessons).
- A friendlier desktop editing surface (EventKit/Calendar.app integration,
  or any GUI editor) — raw-file editing was the explicit choice for this
  pass.
- A Mac/Catalyst companion app — considered and rejected for the mobile app
  already (see the 2026-08-21 spec); same reasoning applies here.
- Real-time conflict resolution UI for iCloud's own "conflicted copy" files
  — rare for single-writer-at-a-time usage; not handled specially.
- Merge-on-conflict when switching storage modes — mode switches are
  replace-only (pick one side's files), matching mobile's precedent.
- The actual real-data migration onto the phone (the `devicectl copy` step
  in `docs/superpowers/plans/2026-09-20-todo-txt-to-native-migration.md`,
  Task 12 step 6) — orthogonal to this feature. This feature ships and is
  tested against whatever data is currently on the phone (test data, per
  that plan's own note).
