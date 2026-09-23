# Native iOS App: Search — Design

Date: 2026-09-23

## Background

The native app (`ios/`) has no way to search tasks and events at all — it's
a single screen (`ContentView`) showing the current agenda/calendar grid,
with no text-search entry point anywhere. The user wants to search their
tasks and events, with the entry point placed next to the existing Add
floating action button (added earlier the same day, replacing the old
nav-bar Add button).

## Decisions already made with the user

1. **Search covers everything ever stored**, not just what's currently
   loaded into the agenda's display window (today ±14/+60 days, plus
   whatever's been scrolled/tapped into). The app currently has no way to
   even enumerate which month files exist on disk without guessing —
   `PlannerFile` needs that capability added.
2. **Entry point:** a second floating button next to the existing Add FAB,
   same square/flat/accent style, a magnifying-glass glyph.
3. **Matching fields:** title, notes, and location (events) / title and
   notes (reminders) — the natural things people search by, matched
   unconditionally, with no filter/field picker in the UI. (Fantastical's
   own search offers a Title/Location/Invitees/All filter row; considered
   and deliberately dropped for simplicity — see the note in the Search
   screen section below.) Case-insensitive substring match, not
   fuzzy/ranked search.
4. **Results open the existing `EditItemView`** — no new detail UI. A
   recurring item opens its master series, matching how editing already
   works everywhere else in the app.

## Architecture

### `PlannerFile.availableMonths()`

```swift
public func availableMonths() -> [YearMonth]
```

Scans `directory` for files matching `YYYY-MM.ics` (skipping `recurring.ics`
and anything else), parsing each filename into a `YearMonth`. Returns `[]`
if the directory can't be enumerated (e.g. doesn't exist yet — a normal
state for a brand-new install, not an error).

### `PlannerStore.loadAllMonths()`

```swift
public func loadAllMonths() async
```

Enumerates `file.availableMonths()` and calls the existing `loadMonth(_:)`
for every month not already in `loadedMonths` (that method's own guard
already skips repeats). `await Task.yield()` between each call — this
doesn't make individual file reads faster, but it lets the main actor
process other work (redrawing a loading indicator) between them, rather
than the UI freezing solid for however long it takes to read every month
file that exists. Safe to call more than once per session — after the
first call, everything is already in memory and later calls are instant
no-ops (every month is already in `loadedMonths`).

This does not change `start()`'s existing behavior (still only loads the
display window's months on launch) — `loadAllMonths()` is only ever called
when Search is opened, not on every launch, since most sessions never open
Search and shouldn't pay for it.

### `SearchView` (new)

A sheet presented from `ContentView`. Structure:
- A search `TextField` at the top.
- Below it, a results list reusing `AgendaRowView` for each match (so
  results look like agenda rows — same title/time/priority rendering the
  user already knows).
- On appear: calls `await store.loadAllMonths()`, showing a lightweight
  "Loading…" state (e.g. a `ProgressView`) until it completes. Since
  `loadedMonths` persists for the app's session, re-opening Search later
  skips straight to instant results.
- Filtering: for each `store.events`/`store.reminders` entry, a
  case-insensitive substring match against title + notes + location
  (events) or title + notes (reminders) — no field picker, always all of
  them. (A Fantastical-style Title/Notes/Location/All filter row was
  considered and deliberately dropped: one always-on match covers the same
  ground with a simpler UI and no extra state to manage.) Empty search
  text shows no results (not the full list) — searching, not browsing, is
  the point of this screen.
- Tapping a result builds an `AgendaItem` directly from the found
  `Event`/`Reminder` (`AgendaItem(kind: .event(event)` or
  `.reminder(reminder), occurrence: event.start` or
  `reminder.dueDate ?? Date(), displayDate: <same>, isOverdue: false)`) and
  presents `EditItemView(item:)` — the exact same detail/edit sheet
  `ContentView` already uses, no new UI.

### Entry point (`ContentView`)

A second floating button, `searchButton`, built the same way as the
existing `addButton` (square, `Colors.accent` fill, no shadow/glass), with
a magnifying-glass SF Symbol instead of a plus. Positioned to the left of
`addButton` in the same bottom-trailing overlay (an `HStack` of the two
buttons instead of a single button). Tapping it sets a new
`@State private var showSearch = false` to `true`, presenting `SearchView`
via `.sheet(isPresented: $showSearch)`.

## Error handling

`loadAllMonths()` reuses `loadMonth`'s existing error handling — a month
that fails to read sets `store.error` (surfaced by `ContentView`'s existing
error banner) and stays out of `loadedMonths` (retryable later), exactly
like today. Search doesn't need its own error UI: a failed month's items
are simply absent from search results until the underlying read problem is
fixed, same as they'd be absent from the agenda.

## Testing

- `PlannerFile.availableMonths()`: parses real month filenames correctly,
  ignores `recurring.ics`, ignores non-`.ics` files, returns `[]` for a
  missing/unreadable directory. StarkKit unit tests (Swift Testing).
- `PlannerStore.loadAllMonths()`: loads a month outside the normal display
  window that `start()` wouldn't have touched; confirms calling it twice
  doesn't re-read already-loaded months (observable via the store's error
  state staying clean / no duplicate items appearing). StarkKit unit tests.
- `SearchView`/the entry-point button: SwiftUI wiring, verified by building
  both destinations and manual testing — matching this app's existing
  convention that view-layer code isn't unit-tested, StarkKit logic is.

## Non-goals

- Fuzzy or ranked search — plain case-insensitive substring matching only.
- Filtering search by date range, type (event vs. reminder), or completion
  status — a plain text match against everything, matching the user's
  literal ask ("search my tasks and events").
- Searching `recurring.ics` items beyond what's already always loaded (they
  already are, at `start()` — no change needed there).
- Any change to the Mac Catalyst sidebar or desktop-specific UI — this is
  an iPhone-and-Mac-shared feature (the search button appears in
  `screenContent`, shared by both platforms), but no Mac-specific search
  affordance (like a keyboard shortcut) is being added in this pass.
