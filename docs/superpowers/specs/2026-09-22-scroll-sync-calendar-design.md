# Native iOS App: Scroll-Synced Calendar Selection — Design

Date: 2026-09-22

## Background

Issue #101 (originally filed as a bug — "scrolling the list also moves the
day marker" — but clarified in conversation to be a **feature request**):
the user wants Fantastical-style behavior where scrolling the agenda list
vertically continuously updates which day is selected/highlighted in the
calendar grid above it (both week and month view), as if the list and grid
were synced. Today the relationship is one-directional: tapping a day in
`MonthGridView` scrolls `AgendaView` to that day (`ContentView.selectDate`
→ `ScrollRequest`); scrolling the list has no effect on the grid.

Year mode is out of scope — it's a fundamentally different, tap-to-jump
interaction (`YearView`), not a live list+grid pairing, and the user didn't
ask for it there.

## Decisions already made with the user

1. **Week view pages automatically** as the agenda scrolls across a week
   boundary — this is close to the core of "synced," since only 7 days are
   visible at once.
2. **Month view also pages automatically** as the agenda scrolls across a
   month boundary — matching Fantastical exactly. This is a deliberate,
   scroll-specific exception to the existing rule that a **tap** never
   pages the month grid (issue #96) — that rule is untouched for taps; this
   adds a second, independent rule for scroll.
3. Mechanism: iOS 17's `.scrollPosition(id:)` binding (the app's deployment
   target is already 17.0) rather than manual scroll-offset tracking —
   `AgendaView` is a plain SwiftUI `List` + `ScrollViewReader` today, not
   the manual-offset-math pattern the deprecated `mobile/` Expo app used.

## Architecture

### `AgendaView`: tracking scroll position

A new `@State private var topVisibleRowID: String?`, bound via
`.scrollPosition(id: $topVisibleRowID)` on the existing `List`. During the
same pass that already builds `rows` (`makeRows`), a parallel
`[String: Date]` lookup is built mapping every row's id (header, empty, and
item rows — `tail` maps to nothing) to the start-of-day `Date` it belongs
to. This is necessary because most of the time the top-of-viewport row is
an item row (the user is scrolled into the middle of a day's items), not a
header row, so resolving "which day is at the top" can't rely on header
rows alone.

`.onChange(of: topVisibleRowID)` resolves the id via that lookup and, after
a **~150ms debounce** (matching `YearView`'s existing debounce for its own
density recompute — same order of magnitude, same purpose: don't spam
updates while the user is actively flicking through the list), calls a new
callback prop:

```swift
let onDayInView: (Date) -> Void
```

This is the only new public surface on `AgendaView`.

### The feedback-loop guard (load-bearing)

Tapping a **neighboring-month day** in `MonthGridView` (a dimmed cell
showing an adjacent month's date, rendered per issue #96's "month grid
shows the neighbouring months' days") is defined to never page the grid —
but it does scroll the agenda there via the existing `ScrollRequest`
mechanism. Once that scroll lands, the new scroll-tracking mechanism would
see the neighboring-month day at the top of the viewport and, per decision
2 above (scroll pages month view), would auto-page the grid anyway —
silently overriding the tap-never-pages rule through the back door. This
is a correctness requirement, not UX polish.

Fix: `AgendaView` records a short suppression deadline
(`Date().addingTimeInterval(0.3)`, chosen because the existing
`scrollRequest` handler's `proxy.scrollTo` is an instant jump — not
wrapped in `withAnimation` — deferred only one runloop turn via
`DispatchQueue.main.async`, so 300ms comfortably covers the jump plus a
frame or two for `List` to settle and `.scrollPosition` to report the new
value) whenever a new `scrollRequest` arrives. While `Date()` is before
that deadline, `onDayInView` is not called. This guard is entirely
internal to `AgendaView` — `ContentView` never knows it exists.

### Wiring: week paging (free) vs. month paging (new, explicit)

`ContentView` receives `onDayInView` and always does
`selectedDate = date`.

- **Week mode needs nothing extra.** `MonthGridView.body` already computes
  `cells = MonthGrid.weekRow(containing: selectedDate)` when
  `mode == .week` (confirmed by reading the current source), so the row
  re-pages the instant `selectedDate` changes — scroll-driven week paging
  falls out of the existing architecture for free.
- **Month mode needs one new, explicit, scroll-only prop.**
  `MonthGridView.visibleMonth` is its own internal `@State` and already has
  a guarded `.onChange(of: selectedDate)` that updates it **only while
  `mode == .week`** (confirmed in source) — this is precisely the mechanism
  that keeps issue #96's "tap never pages in month mode" rule intact today.
  Reusing plain `selectedDate` changes to also drive month paging would
  silently break that rule for taps. So `MonthGridView` gains one new
  optional prop:

  ```swift
  let scrollPagingDate: Date?
  ```

  set by `ContentView` **only** from `onDayInView` (never from
  `onSelectDate`/a tap). A dedicated `.onChange(of: scrollPagingDate)`
  inside `MonthGridView` — structurally separate from anything a tap
  touches — does `visibleMonth = YearMonth(date: newValue)` when
  `mode == .month`. Taps continue through the existing `onSelectDate` /
  `selectedDate` path, completely untouched.

  This keeps the two trigger paths structurally incapable of
  cross-contaminating: a tap can never accidentally page month view (it
  never writes to `scrollPagingDate`), and scroll can never accidentally
  suppress itself (it never writes to the plain `onSelectDate` path).

## Edge cases & scope

- **Year mode:** untouched — `YearView` isn't part of this feature.
- **Initial load / scroll-to-today:** the existing `onAppear`/`itemCount`
  scroll-to-today logic already routes through `scrollRequest`, so it's
  covered by the same suppression guard with no special-casing.
- **Fast flicks:** the 150ms debounce means a rapid scroll-fling settles
  on wherever the list stops, not every day/month it flew past.
- **No new StarkKit code.** This is entirely SwiftUI wiring across
  `AgendaView`, `ContentView`, and `MonthGridView` — `CalendarMode`,
  `MonthGrid.weekRow`, `YearMonth` are all reused as-is, no new business
  logic to add or test at that layer.
- **Mac Catalyst:** no interaction with the Mac sidebar mode-picker
  (`CalendarSidebar`) — that only changes how `mode` itself is picked, not
  how `selectedDate`/`visibleMonth` respond to it. No `#if
  targetEnvironment(macCatalyst)` branching needed for this feature.

## Testing

No new StarkKit logic means no new Swift Testing unit tests — consistent
with how the drag bar / view-modes work shipped (SwiftUI wiring, verified
by building and manual testing, per the existing convention documented in
`CLAUDE.md`'s "Native iOS App" section). Manual verification:

- Scroll the agenda in week mode across a week boundary — the week row
  pages to match.
- Scroll the agenda in month mode across a month boundary — the grid
  pages to match.
- Tap a neighboring-month day (a dimmed cell) and confirm the grid does
  **not** page even though the agenda scrolls there (the regression this
  design specifically guards against).
- Rapid-flick the list and confirm no visible flicker/strobing through
  multiple months before it settles.
- Confirm the existing tap-to-scroll behavior (grid tap → agenda scrolls)
  is unaffected.

## Non-goals

- Year mode scroll-sync.
- Any change to `CalendarMode`, `MonthGrid`, or other StarkKit logic.
- Proactively loading additional months as the scroll position approaches
  the edge of the currently loaded window — the display window already
  spans -14/+60 days, and every rendered agenda row is by definition
  already inside the currently loaded range, so this feature never
  triggers a loading concern beyond what already exists.
