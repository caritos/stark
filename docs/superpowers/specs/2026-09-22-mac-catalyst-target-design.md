# Native iOS App: Mac Catalyst Target — Design

Date: 2026-09-22

## Background

Follow-up from issue #98 → #100: the ask is desktop access for the native
Swift app (`ios/`) — view/edit tasks and events from a Mac, like `mobile/`
(the Expo app, now deprecated) already supports via its iCloud Drive storage
mode.

A first design (`2026-09-22-native-icloud-drive-storage-design.md`, now
superseded) proposed mirroring `mobile/`'s approach directly: a user-picked
iCloud Drive folder + security-scoped bookmark, editing raw `.ics` files in
Finder. That was rejected because `.ics` (`BEGIN:VEVENT`/`RRULE`/`EXDATE`
blocks) is much less forgiving to hand-edit than `todo.txt`'s flat
`key:value` lines.

Instead: build a **Mac Catalyst companion app** and, in a second, dependent
sub-project, switch storage to an **automatic private iCloud ubiquity
container** — real native UI editing on both platforms, no raw-file editing,
no folder picker. This is viable in a way it wasn't for the (iOS-only)
Expo app: per the global CLAUDE.md's iCloud lessons, a Mac with no
locally-installed app matching the bundle ID never actively syncs a
third-party app's *private* ubiquity container (confirmed by control-testing
Drafts/Bear vs. Obsidian on the same Mac). A Mac Catalyst build of Stark,
sharing the iPhone app's bundle ID, makes this the "Obsidian case" instead.

**This spec covers only the first sub-project: getting Stark running on the
Mac at all**, as a Catalyst build of the existing app, still using
independent local storage on each platform. The shared-container storage
work is a separate, later spec that depends on this one existing and working.

## Decisions already made with the user

1. **Mac Catalyst, not a separate native macOS app** — reuse `StarkKit`
   (all business logic, untouched) and the existing SwiftUI views in
   `App/Stark`, rather than building and maintaining a second UI.
2. **Mac layout: sidebar mode-picker only, not a fuller sidebar nav.** The
   native app currently has one screen (`ContentView`) — Year is an internal
   drag-bar *mode*, not a separate screen (see `CalendarMode`/`ModeHandle` in
   `CLAUDE.md`), and there is no Search feature built natively yet. The
   sidebar's only job is to replace `ModeHandle`'s touch-only drag gesture
   with a Week/Month/Year picker. No native Search feature is in scope here.
3. **`CustomRepeatView`'s wheel pickers get a Mac-appropriate alternative**
   (stepper/menu) rather than shipping `.pickerStyle(.wheel)` unchanged on
   Catalyst.
4. **Distribution: Mac App Store, same App Store Connect record as iOS**
   ("iPhone + Mac" / Universal Purchase) — not a separate Developer
   ID/notarization pipeline for direct distribution.

## Xcode project changes

`Stark.xcodeproj/project.pbxproj` (both Debug and Release configs):

- `SUPPORTED_PLATFORMS` gains `maccatalyst` (currently `"iphoneos
  iphonesimulator"` only).
- `SUPPORTS_MACCATALYST = YES` (currently absent).
- `TARGETED_DEVICE_FAMILY` changes from `1` (iPhone only) to `"1,2"` — Mac
  Catalyst requires the iPad idiom under the hood, so device family 2 must
  be enabled even though no iPad-specific layout work is being done.
- This resolves a vestigial inconsistency the portability survey found:
  `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` was already set
  despite `TARGETED_DEVICE_FAMILY = 1` (dead until now) — it becomes
  load-bearing once device family 2 is enabled, since Catalyst inherits the
  iPad idiom's Info.plist keys.
- No deployment-target mismatch: `IPHONEOS_DEPLOYMENT_TARGET = 17.0` and
  `StarkKit`'s `Package.swift` (`platforms: [.iOS(.v17), .macOS(.v14)]`)
  already line up — iOS 17 pairs with Catalyst's macOS 14 minimum.
- Same target, same bundle id (`com.caritos.todo-txt`) — Mac Catalyst is a
  second destination of the existing app target, not a new target.
- Same `DEVELOPMENT_TEAM`/automatic signing as today; no entitlements file
  exists yet and none is needed for this sub-project (that comes with the
  shared-container storage spec, which needs
  `com.apple.developer.ubiquity-container-identifiers`).

## App-layer changes

This introduces the first `#if targetEnvironment(macCatalyst)` branching in
the codebase (no `#if os(...)`/platform conditionals exist anywhere in
`App/Stark` today).

### Sidebar mode-picker (replaces `ModeHandle` on Mac only)

- iPhone: `ModeHandle`'s drag bar is unchanged — `.gesture(DragGesture
  (minimumDistance: 8).onEnded { ... })` driving `CalendarMode.afterDrag`.
- Mac: a `NavigationSplitView` sidebar with three rows (Week / Month / Year),
  selecting the same `CalendarMode` state `ModeHandle` drives today. Only the
  *picker* changes — `MonthGridView`/`YearView`/`AgendaView` and all
  mode-driven behavior (`ContentView.visibleMonth` re-sync, the opaque
  `YearView` overlay, etc.) are untouched; the sidebar is just a different
  input for the same state.
- `ModeHandle` itself stays as the iPhone implementation; the Mac sidebar is
  a new, separate view, gated by `#if targetEnvironment(macCatalyst)` at the
  `ContentView` call site.

### Mac-friendly recurrence pickers

- iPhone: `CustomRepeatView`'s `.pickerStyle(.wheel)` rows (216pt-boxed, per
  `UIPickerView`'s minimum) are unchanged.
- Mac: the "every N" interval becomes a `Stepper` with an inline value
  label; the unit picker becomes `Picker(_:selection:) { }.pickerStyle
  (.menu)`. Both write the same `RecurrenceRule` fields the wheel pickers do
  — this is a control swap, not a data-model change.

### Window sizing

`StarkApp`'s `WindowGroup` currently has no `.defaultSize`/
`.windowResizability` set. Add a sensible minimum content size (e.g. via
`.windowResizability(.contentSize)` combined with a `.frame(minWidth:
minHeight:)` on the root view) — without one, an aggressively resized Mac
window could crush the agenda area, since `MonthGridView`/`YearView` use
fixed-height rows (`rowHeight`, `cellSize`, `44pt` chevron targets) that
don't currently shrink with the window.

### Day-rollover detection (unverified, not changed)

`ContentView` listens for `UIApplication.significantTimeChangeNotification`
to detect midnight/timezone changes (see "The window follows the calendar
past midnight" in `CLAUDE.md`). This is left as-is under Catalyst — it's a
UIKit-backed notification that should still exist — but its firing semantics
on Mac haven't been verified (mirrors the existing, already-documented "not
verified: a timezone change while running" caveat for this exact mechanism).
Confirmed or refuted during manual testing below; no code change unless
testing shows it doesn't fire.

## Distribution

Mac Catalyst becomes a second destination of the existing
`com.caritos.todo-txt` App Store Connect record (Universal Purchase:
"iPhone + Mac"), using the same automatic signing/team as the iOS target.
No separate Developer ID certificate or `notarytool` pipeline. No actual App
Store submission happens as part of this sub-project — the native app
hasn't reached feature parity or shipped yet — this only gets the Catalyst
destination building and signable correctly for when that day comes.

Day-to-day iteration: build and run locally via Xcode (Mac Catalyst
destination) or `xcodebuild -destination 'platform=macOS,variant=Mac
Catalyst'`. No install/deploy step is needed the way `ios/App/deploy.sh`
needs one for a physical iPhone — running a Mac Catalyst build just runs
directly on the development Mac.

## Testing

- `swift test` for `StarkKit` already runs on macOS directly today (the
  package declares `.macOS(.v14)`) — no new test infrastructure needed;
  confirm it still passes unmodified once the app target changes land
  (StarkKit itself doesn't change in this sub-project).
- App-layer verification is manual (build + run on the Mac via Xcode),
  matching this repo's existing preference for real-hardware iteration over
  simulators. Specifically confirm:
  - The sidebar mode-picker drives the same agenda content the drag bar
    would (Week/Month/Year selection matches `CalendarMode` behavior).
  - The Mac recurrence controls (stepper + menu) save/round-trip the same
    `RecurrenceRule` values the wheel pickers do.
  - Resizing the window (including toward the minimum) doesn't break the
    grid/agenda layout.
  - The day-rollover notification actually fires on Mac (see above).
  - Add/Edit sheets, checkbox completion (`PendingCompletions`'s 2.5s undo
    window), and event outcome actions all still work with mouse/trackpad
    input, not just touch.

## Non-goals for this sub-project

- Shared iCloud container storage — a separate, later spec. Each platform
  keeps independent local storage for now, so the Mac and iPhone builds will
  show *different* data until that ships. This is an expected, temporary
  state, not a bug.
- A native Search feature.
- Actual App Store submission of the Mac build.
- Any UI redesign beyond the two identified touch-only controls (`ModeHandle`
  and the wheel pickers) — every other view ports as-is, without dedicated
  pointer/hover styling (no `onHover`/`hoverEffect`/`pointerStyle` work).
- iPad-specific layout optimization — device family 2 is enabled only
  because Catalyst requires it; no iPad-tailored UI is being built.
