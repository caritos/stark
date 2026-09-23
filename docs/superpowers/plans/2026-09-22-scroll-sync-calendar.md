# Scroll-Synced Calendar Selection (issue #101) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scrolling the agenda list continuously updates which day is selected/highlighted in the calendar grid above it — in week mode the week row pages to follow, in month mode the month grid pages to follow — matching Fantastical's synced list+calendar behavior. Tapping a grid day keeps working exactly as before.

**Architecture:** `AgendaView` tracks which row is at the top of its `List` via iOS 17's `.scrollPosition(id:)`, resolves that row to a day via a new row→day lookup, and (after a 150ms debounce, matching `YearView`'s existing debounce idiom) reports it through a new `onDayInView` callback — suppressed for 300ms after a tap-driven `scrollRequest`, so a tap's own resulting scroll can never be mistaken for a user scroll. `ContentView` always updates `selectedDate` from that callback (which alone makes week mode page, since `MonthGridView` already derives its week row from `selectedDate`) and separately sets a new `scrollPagingDate` prop that `MonthGridView` uses to page `visibleMonth` — but only in month mode, and structurally separate from the existing tap path, so a tap can never accidentally page month view.

**Tech Stack:** Swift 6 / SwiftUI (`.scrollPosition(id:)`, iOS 17+), SwiftPM package `StarkKit` (untouched by this plan) tested with Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-22-scroll-sync-calendar-design.md`

**Issue:** https://github.com/caritos/todo-txt/issues/101

## Global Constraints

- **Working directory:** `/Users/eladio/src/todo-txt/.claude/worktrees/scroll-sync-calendar` (a git worktree, branch `worktree-scroll-sync-calendar`, fast-forwarded onto local `main` at commit `2fdb1dc`). Use absolute paths; run Swift tests from its `ios/` directory (`swift test`).
- **Shell:** compound commands and heredocs may be rejected. Use plain single commands, the Write/Edit tools for files, `git -C <worktree>` and multiple `-m` flags for commits.
- **Commits:** stage specific paths only (never `git add -A`, `.` or `commit -a`). End every commit message with a separate `-m` paragraph: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` — this exact literal string regardless of which model executes a task (a prior plan in this repo had an implementer substitute its own model name here, caught in review and fixed via `commit --amend`). Never push.
- **No new StarkKit logic.** This plan is entirely SwiftUI wiring across `AgendaView.swift`, `ContentView.swift`, and `MonthGridView.swift` — do not touch `ios/Sources/StarkKit` or `ios/Tests/StarkKitTests`.
- **Baseline:** `swift test` from `ios/` currently passes 321 tests in 31 suites. It must stay green, unchanged, after every task.
- **iOS build check** (every task): `cd /Users/eladio/src/todo-txt/.claude/worktrees/scroll-sync-calendar/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` must end in `** BUILD SUCCEEDED **`.
- **Mac Catalyst build check** (every task — this repo also ships a Mac Catalyst destination of the same target; nothing in this plan is platform-conditional, but every touched file must still compile there): `cd /Users/eladio/src/todo-txt/.claude/worktrees/scroll-sync-calendar/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` must end in `** BUILD SUCCEEDED **`.
- **Theme:** only `Colors.*`/`Spacing.*`/`Fonts.mono` from `Theme.swift` — not applicable to this plan's changes (no new UI elements, only data-flow wiring), but no exceptions either.
- **Existing behavior to preserve exactly:** tap-to-scroll (grid tap → agenda scrolls to that day) must keep working unchanged; a tap on a neighboring-month day must still never page the month grid (issue #96) even though the resulting scroll lands on that day in the agenda.
- **Do not touch `mobile/`** (the Expo app is deprecated) or the author's iPhone (no `xcrun devicectl`, no `deploy.sh` — build-check + manual verification only, matching this repo's established convention for SwiftUI-wiring-only changes).

---

### Task 1: `AgendaView` reports the day scrolled into view

**Files:**
- Modify: `ios/App/Stark/Stark/AgendaView.swift`

**Interfaces:**
- Produces (used by Task 2): a new property `let onDayInView: (Date) -> Void = { _ in }` on `AgendaView` (defaulted, so this task's change alone still compiles with `AgendaView`'s one existing call site in `ContentView.swift` unchanged — Task 2 passes a real closure).
- No StarkKit changes, no new tests — this is SwiftUI wiring verified by both build checks; the debounce/guard logic is confirmed by reading the diff and by Task 3's manual checklist (Task 2 is what actually makes the callback observable in the UI, so this task's own build check is the only automated verification available for it in isolation).

- [ ] **Step 1: Add the row→day lookup**

Read `ios/App/Stark/Stark/AgendaView.swift`. Directly after the existing `makeRows` function (which ends just before the `// MARK: Scrolling` comment), add a new function that mirrors `makeRows`'s exact id-generation logic (so it never invents an id that doesn't actually exist as a row):

```swift
    /// Maps every row id `makeRows` can produce back to the day it belongs to, so
    /// `.scrollPosition`'s reported top-of-viewport id can be resolved to a day. Mirrors
    /// `makeRows`'s exact branching (an `.empty` row only exists for a bare day, i.e. one with
    /// no items) so it never invents an id that isn't actually a row.
    private func makeRowDayLookup(_ sections: [AgendaDay]) -> [String: Date] {
        var lookup: [String: Date] = [:]
        for section in sections {
            lookup[Self.headerID(section.day)] = section.day
            if section.items.isEmpty {
                lookup["empty-\(Int(section.day.timeIntervalSince1970))"] = section.day
            } else {
                for item in section.items {
                    lookup[item.id] = section.day
                }
            }
        }
        return lookup
    }
```

- [ ] **Step 2: Add the new state and the callback property**

In the same file, find:

```swift
    let today: Date
    let anchor: Date
    let scrollRequest: ScrollRequest?
    let onSelect: (AgendaItem) -> Void
```

Replace with:

```swift
    let today: Date
    let anchor: Date
    let scrollRequest: ScrollRequest?
    let onSelect: (AgendaItem) -> Void
    /// Called (debounced, and suppressed for 300ms after a tap-driven `scrollRequest`) with the
    /// day whose row is at the top of the list, as the user scrolls. Defaulted so existing call
    /// sites compile unchanged; `ContentView` passes a real closure to drive calendar paging
    /// (issue #101). Never called as a side effect of `scrollRequest`'s own programmatic scroll —
    /// see `scrollSuppressUntil`.
    let onDayInView: (Date) -> Void = { _ in }
```

Find:

```swift
    @State private var hasSettled = false
```

Replace with:

```swift
    @State private var hasSettled = false
    /// The row id `.scrollPosition` reports as being at the top of the visible list.
    @State private var topVisibleRowID: String?
    /// While `Date()` is before this, `topVisibleRowID` changes are ignored — covers a
    /// tap-driven `scrollRequest`'s own (instant, unanimated) `proxy.scrollTo` jump, so it can
    /// never be mistaken for a user scroll and cause an unwanted grid page (issue #96: a tap on
    /// a neighbouring-month day must never page the month grid, even though it does scroll the
    /// agenda there).
    @State private var scrollSuppressUntil = Date.distantPast
```

- [ ] **Step 3: Compute the lookup in `body` and bind `.scrollPosition`**

Find:

```swift
    var body: some View {
        let now = today
        let todayStart = Self.calendar.startOfDay(for: now)
        let sections = makeSections(now: now)
        let rows = makeRows(sections, todayStart: todayStart)
        let itemCount = sections.reduce(0) { $0 + $1.items.count }
```

Replace with:

```swift
    var body: some View {
        let now = today
        let todayStart = Self.calendar.startOfDay(for: now)
        let sections = makeSections(now: now)
        let rows = makeRows(sections, todayStart: todayStart)
        let itemCount = sections.reduce(0) { $0 + $1.items.count }
        let rowDayLookup = makeRowDayLookup(sections)
```

Find:

```swift
                .listStyle(.plain)
```

Replace with:

```swift
                .listStyle(.plain)
                .scrollPosition(id: $topVisibleRowID)
```

- [ ] **Step 4: Suppress tracking during a tap-driven scroll, and report debounced changes**

Find:

```swift
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    hasSettled = true
                    let target = Self.calendar.startOfDay(for: request.date)
                    // The exact day's header; falls back to the first section after it
                    // (else the last) if it is somehow missing from the window.
                    guard let section = sections.first(where: { $0.day >= target }) ?? sections.last else { return }
                    scroll(proxy, to: Self.headerID(section.day))
                }
```

Replace with:

```swift
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    hasSettled = true
                    scrollSuppressUntil = Date().addingTimeInterval(0.3)
                    let target = Self.calendar.startOfDay(for: request.date)
                    // The exact day's header; falls back to the first section after it
                    // (else the last) if it is somehow missing from the window.
                    guard let section = sections.first(where: { $0.day >= target }) ?? sections.last else { return }
                    scroll(proxy, to: Self.headerID(section.day))
                }
                // Debounced (matches YearView's own 150ms debounce for its density recompute):
                // `.task(id:)` cancels the previous wait whenever `topVisibleRowID` changes
                // again before it fires, so a fast scroll reports only where it settles.
                .task(id: topVisibleRowID) {
                    guard let topVisibleRowID else { return }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    guard Date() >= scrollSuppressUntil else { return }
                    guard let day = rowDayLookup[topVisibleRowID] else { return }
                    onDayInView(day)
                }
```

- [ ] **Step 5: Verify both destinations build**

Run the iOS build check (Global Constraints) — expect `** BUILD SUCCEEDED **`.
Run the Mac Catalyst build check (Global Constraints) — expect `** BUILD SUCCEEDED **`.
Run `swift test` from `ios/` — expect 321 tests, all passing, unchanged (this task doesn't touch `Sources/StarkKit`).

- [ ] **Step 6: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/scroll-sync-calendar add ios/App/Stark/Stark/AgendaView.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/scroll-sync-calendar commit -m "feat(ios): AgendaView reports the day scrolled into view (#101)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Wire scroll-driven selection into week and month paging

**Files:**
- Modify: `ios/App/Stark/Stark/ContentView.swift`
- Modify: `ios/App/Stark/Stark/MonthGridView.swift`

**Interfaces:**
- Consumes (Task 1): `AgendaView`'s `onDayInView: (Date) -> Void` property.
- Produces: `MonthGridView` gains `let scrollPagingDate: Date?`, a required parameter — this task updates `MonthGridView`'s one existing call site (in `ContentView.swift`) in the same commit, so there is no default needed.
- No StarkKit changes, no new tests — verified by both build checks; behavior (paging vs. not paging) is confirmed in Task 3's manual checklist.

- [ ] **Step 1: `MonthGridView` gains `scrollPagingDate` and pages `visibleMonth` from it, month mode only**

Read `ios/App/Stark/Stark/MonthGridView.swift`. Find:

```swift
    let mode: CalendarMode
    let selectedDate: Date
    let onSelectDate: (Date) -> Void
```

Replace with:

```swift
    let mode: CalendarMode
    let selectedDate: Date
    let onSelectDate: (Date) -> Void
    /// Set by `ContentView` only from `AgendaView.onDayInView` (never from a tap) — pages
    /// `visibleMonth` to follow the agenda's scroll position, but only in month mode. Structurally
    /// separate from `selectedDate`/`onSelectDate` (the tap path) so a tap can never accidentally
    /// page the month grid (issue #96), and a scroll can never accidentally suppress itself
    /// (issue #101).
    let scrollPagingDate: Date?
```

Find:

```swift
        // In week mode the week row follows the selection, possibly into another month (the
        // chevrons, a day tap, the midnight follow). In month mode a selection never pages.
        .onChange(of: selectedDate) { _, _ in
            guard mode == .week else { return }
            syncVisibleMonthToSelection()
        }
    }
```

Replace with:

```swift
        // In week mode the week row follows the selection, possibly into another month (the
        // chevrons, a day tap, the midnight follow). In month mode a plain selection never pages.
        .onChange(of: selectedDate) { _, _ in
            guard mode == .week else { return }
            syncVisibleMonthToSelection()
        }
        // Scroll-driven paging (issue #101): unlike a plain selection, this pages the month grid
        // — a deliberate, scroll-only exception to "a tap never pages the month view" (issue #96).
        .onChange(of: scrollPagingDate) { _, newValue in
            guard mode == .month, let newValue else { return }
            visibleMonth = YearMonth(date: newValue)
            loadVisibleMonths()
        }
    }
```

Update the struct's doc comment to mention the new behavior. Find:

```swift
/// In `.week` mode (the collapsed state) the grid is one row: the Sunday-first week of
/// `selectedDate`, drawn with the same cells. The title is the selected day's month and the
/// chevrons step the selection by a week (through `onSelectDate`, so the agenda follows) instead
/// of paging months. `visibleMonth` follows the selected day's month while in week mode and when
/// returning to month, so the density snapshot and the store's loaded months always cover the
/// week on screen (the week lies inside its month's 6-row grid). In `.month` mode selecting a day
/// never changes `visibleMonth`.
```

Replace with:

```swift
/// In `.week` mode (the collapsed state) the grid is one row: the Sunday-first week of
/// `selectedDate`, drawn with the same cells. The title is the selected day's month and the
/// chevrons step the selection by a week (through `onSelectDate`, so the agenda follows) instead
/// of paging months. `visibleMonth` follows the selected day's month while in week mode and when
/// returning to month, so the density snapshot and the store's loaded months always cover the
/// week on screen (the week lies inside its month's 6-row grid). In `.month` mode a plain
/// selection (a tap) never changes `visibleMonth` — but `scrollPagingDate` does (issue #101),
/// since scrolling the agenda is deliberately allowed to page the month grid even though tapping
/// it is not.
```

- [ ] **Step 2: `ContentView` wires both new callbacks**

Read `ios/App/Stark/Stark/ContentView.swift`. Find:

```swift
    /// How much calendar the grid shows. Always starts as the month grid; not persisted.
    @State private var mode: CalendarMode = .month
```

Replace with:

```swift
    /// How much calendar the grid shows. Always starts as the month grid; not persisted.
    @State private var mode: CalendarMode = .month
    /// The day last reported by `AgendaView.onDayInView` (issue #101) — read only by
    /// `MonthGridView`'s `scrollPagingDate`, to page the month grid as the agenda scrolls.
    @State private var scrollPagingDate: Date?
```

Find:

```swift
                    MonthGridView(today: today, mode: mode, selectedDate: selectedDate, onSelectDate: selectDate)
```

Replace with:

```swift
                    MonthGridView(today: today, mode: mode, selectedDate: selectedDate, onSelectDate: selectDate, scrollPagingDate: scrollPagingDate)
```

Find:

```swift
                    AgendaView(today: today, anchor: agendaAnchor, scrollRequest: scrollRequest, onSelect: { selectedItem = $0 })
```

Replace with:

```swift
                    AgendaView(today: today, anchor: agendaAnchor, scrollRequest: scrollRequest, onSelect: { selectedItem = $0 }, onDayInView: dayScrolledIntoView)
```

Find:

```swift
    /// A day was tapped in the month grid: scroll the agenda to that day's header. A day outside
```

Insert a new method directly before it (same indentation level, i.e. before the `private func selectDate` doc comment and declaration):

```swift
    /// A day scrolled into view at the top of the agenda list (`AgendaView.onDayInView`,
    /// issue #101). Always updates the highlighted/selected day — which alone makes week mode
    /// page, since `MonthGridView` already derives its week row from `selectedDate` — and
    /// separately reports it as `scrollPagingDate`, which `MonthGridView` uses to page the month
    /// grid (month mode only). Never issues a new `scrollRequest`: the agenda is already scrolled
    /// there by the user, so re-scrolling it here would fight the user's own scroll.
    private func dayScrolledIntoView(_ date: Date) {
        selectedDate = date
        scrollPagingDate = date
    }

```

- [ ] **Step 3: Verify both destinations build**

Run the iOS build check (Global Constraints) — expect `** BUILD SUCCEEDED **` for both.
Run the Mac Catalyst build check (Global Constraints) — expect `** BUILD SUCCEEDED **` for both.
Run `swift test` from `ios/` — expect 321 tests, all passing, unchanged.

- [ ] **Step 4: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/scroll-sync-calendar add ios/App/Stark/Stark/ContentView.swift ios/App/Stark/Stark/MonthGridView.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/scroll-sync-calendar commit -m "feat(ios): scroll-driven week/month paging, tap path untouched (#101)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Final regression pass, docs, and the manual verification checklist

**Files:**
- Modify: `CLAUDE.md` (Native iOS App section)

**Interfaces:** None — this task adds no code, only documentation and verification.

- [ ] **Step 1: Full regression check**

Run both build checks (Global Constraints) — expect `** BUILD SUCCEEDED **` for both, with no new warnings from the three files this plan touched (`AgendaView.swift`, `ContentView.swift`, `MonthGridView.swift`).

Run `swift test` from `ios/` — expect 321 tests in 31 suites, all passing, identical to the baseline in Global Constraints (this plan never touched `Sources/StarkKit` or `Tests/StarkKitTests`).

- [ ] **Step 2: Document the feature in `CLAUDE.md`**

Read `CLAUDE.md`. In the "Native iOS App (`ios/`)" section, add one paragraph after the "Week / month / year modes with a drag bar" paragraph (i.e. directly before the "Repeat End and event URL" paragraph):

```markdown
**Scroll-synced calendar selection** (`AgendaView.onDayInView`, `MonthGridView.scrollPagingDate`; issue #101): scrolling the agenda continuously updates which day is selected in the grid, in both week and month mode — matching Fantastical. `AgendaView` tracks the row at the top of its list via `.scrollPosition(id:)` (iOS 17+), resolves it to a day via a row→day lookup that mirrors `makeRows`'s own id logic, and reports it (150ms-debounced, matching `YearView`'s density-recompute debounce) through `onDayInView` — suppressed for 300ms after a tap-driven `scrollRequest`, so a tap's own resulting scroll (e.g. tapping a neighbouring-month day, which scrolls the agenda there without paging the grid — issue #96) can never be mistaken for a user scroll and page the grid by mistake. `ContentView` always updates `selectedDate` from `onDayInView` (which alone pages week mode, since the week row already derives from `selectedDate`) and separately sets `scrollPagingDate`, which `MonthGridView` uses to page `visibleMonth` — but only in month mode, and only from this scroll-only property, never from a plain `selectedDate` change. This means scrolling and tapping now deliberately differ in month mode: scrolling pages the grid, tapping still never does (issue #96's rule is unchanged for taps). Year mode is unaffected — this feature doesn't touch `YearView`.
```

- [ ] **Step 3: Commit the docs**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/scroll-sync-calendar add CLAUDE.md
git -C /Users/eladio/src/todo-txt/.claude/worktrees/scroll-sync-calendar commit -m "docs: document scroll-synced calendar selection (#101)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Manual verification checklist (controller only — not an automated step)**

A coding agent can build the app but cannot scroll a real list or judge whether paging feels right. The controller runs the app (simulator or device) and confirms, by hand:

- In week mode, scrolling the agenda down into next week pages the week row to match; scrolling back up pages it back.
- In month mode, scrolling the agenda into next month pages the grid to that month; scrolling back pages it back.
- Tapping a neighboring-month day (a dimmed cell in the month grid) still does **not** page the grid, even though the agenda scrolls there — this is the regression Task 1's suppression guard specifically protects against.
- Tapping a day still scrolls the agenda to it, exactly as before (the existing tap-to-scroll path is unaffected).
- Rapid-flicking the list settles on wherever it stops, without visibly flickering/strobing through several months on the way.
- Year mode is unaffected (its own drag-bar/tap-to-jump behavior is unchanged).

This checklist is the acceptance test for this plan.

## Self-Review

- **Spec coverage:** scroll-position tracking + row→day lookup + 150ms debounce → Task 1; 300ms tap-scroll suppression guard → Task 1; `onDayInView` callback → Task 1 (produced), Task 2 (consumed); week paging (free, via `selectedDate`) → Task 2; month paging via `scrollPagingDate`, structurally separate from the tap path → Task 2; edge cases (neighboring-month tap must not page, year mode unaffected, no proactive month loading) → Task 2's design + Task 3's manual checklist; testing (both build destinations, `swift test` regression, manual checklist) → every task's build-check steps, Task 3 for the full manual checklist; docs → Task 3.
- **Placeholder scan:** no TBD/TODO; every code step shows the exact before/after Swift.
- **Type consistency:** `onDayInView: (Date) -> Void` (Task 1, produced) matches its consumption in Task 2 (`onDayInView: dayScrolledIntoView` where `dayScrolledIntoView(_ date: Date)`); `scrollPagingDate: Date?` (Task 2, `MonthGridView`) matches its producer in the same task (`ContentView`'s `@State private var scrollPagingDate: Date?`, passed as `scrollPagingDate: scrollPagingDate`).
- **Scope check:** single subsystem (scroll-driven calendar selection), no StarkKit changes, no year-mode or Mac-Catalyst-specific work — matches the spec's stated non-goals exactly.
