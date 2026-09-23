# Native App Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user search all their tasks and events by title/notes/location, from a new floating search button next to the existing Add button, with results opening the same edit sheet already used everywhere else.

**Architecture:** `PlannerFile` gains a way to enumerate which month files actually exist on disk (`availableMonths()`); `PlannerStore` gains `loadAllMonths()`, which loads every one of them, not just the agenda's display window. A new `SearchView` sheet does an unconditional case-insensitive substring match across `store.events`/`store.reminders` and reuses the existing `AgendaRowView`/`EditItemView` for display and editing — no new detail UI.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM package `StarkKit` tested with Swift Testing (`import Testing`, `@Test`, `#expect`; never XCTest).

**Spec:** `docs/superpowers/specs/2026-09-23-native-search-design.md`

## Global Constraints

- **Working directory:** `/Users/eladio/src/todo-txt/.claude/worktrees/native-search` (a git worktree, branch `worktree-native-search`, fast-forwarded onto local `main` at commit `a17cb12`). Use absolute paths; run Swift tests from its `ios/` directory (`swift test`).
- **Shell:** compound commands and heredocs may be rejected. Use plain single commands, the Write/Edit tools for files, `git -C <worktree>` and multiple `-m` flags for commits.
- **Commits:** stage specific paths only (never `git add -A`, `.` or `commit -a`). End every commit message with a separate `-m` paragraph: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` — this exact literal string regardless of which model executes a task.
- **Tests first for StarkKit work.** App-layer SwiftUI (`SearchView.swift`, `ContentView.swift`) has no dedicated automated tests in this codebase — it's verified by building both destinations and manual testing, matching every other view file in this repo.
- **Baseline:** `swift test` from `ios/` currently passes 340 tests in 33 suites. It must stay green after every task, growing only by the new tests this plan adds.
- **iOS build check** (every task touching `App/Stark`): `cd /Users/eladio/src/todo-txt/.claude/worktrees/native-search/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` must end in `** BUILD SUCCEEDED **`.
- **Mac Catalyst build check** (every task touching `App/Stark`): `cd /Users/eladio/src/todo-txt/.claude/worktrees/native-search/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` must end in `** BUILD SUCCEEDED **`.
- **Theme:** only `Colors.*`/`Spacing.*`/`Fonts.mono` from `Theme.swift`; no hardcoded hex; no rounded corners anywhere (hard edges) — including the new search button and search screen.
- **No filter chips / field picker in Search** — an unconditional match across all relevant fields, no UI to narrow it (considered and explicitly dropped during design).
- **Do not touch `mobile/`** (the Expo app is deprecated) or the author's iPhone (no `xcrun devicectl`, no `deploy.sh` — build-check + manual verification only; the controller deploys and verifies on the real device after this plan is merged).

---

### Task 1: `PlannerFile.availableMonths()` and `PlannerStore.loadAllMonths()`

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/PlannerFile.swift`
- Modify: `ios/Sources/StarkKit/Planner/PlannerStore.swift`
- Test: `ios/Tests/StarkKitTests/PlannerFileTests.swift`
- Test: `ios/Tests/StarkKitTests/PlannerStoreTests.swift`

**Interfaces:**
- Produces (used by Task 2): `PlannerFile.availableMonths() -> [YearMonth]` (public, no throws — returns `[]` rather than throwing when the directory can't be enumerated, since a missing directory is a normal "nothing saved yet" state, not an error). `PlannerStore.loadAllMonths() async` (public).
- No StarkKit type changes beyond these two new methods — `YearMonth`, `PlannerFile`, `PlannerStore`'s existing public surface is otherwise untouched.

- [ ] **Step 1: Write the failing `PlannerFile.availableMonths()` tests**

Read `ios/Tests/StarkKitTests/PlannerFileTests.swift` first to confirm its `makeTempDirs()` helper and surrounding style match what's shown below (it should — this file hasn't changed since it was last read during a previous plan in this repo).

Find:
```swift
    @Test("a save failure queues a pending write, retried later")
    func saveFailureQueuesPendingWrite() throws {
```

Insert directly before it:
```swift
    @Test("availableMonths lists every YYYY-MM.ics file, ignoring recurring.ics and non-ics files")
    func availableMonthsListsMonthFiles() throws {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)
        try file.saveMonth(
            YearMonth(year: 2026, month0: 0),
            events: [],
            reminders: [Reminder(title: "January reminder", dueDate: DateMath.date(from: "2026-01-05"))]
        )
        try file.saveMonth(
            YearMonth(year: 2025, month0: 11),
            events: [Event(title: "December event", start: DateMath.date(from: "2025-12-05"))],
            reminders: []
        )
        try file.saveRecurring(events: [], reminders: [])
        try "not an ics file".write(to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let months = Set(file.availableMonths())

        #expect(months == Set([YearMonth(year: 2026, month0: 0), YearMonth(year: 2025, month0: 11)]))
    }

    @Test("availableMonths returns empty when the directory doesn't exist yet")
    func availableMonthsEmptyWhenMissing() {
        let (directory, pending) = makeTempDirs()
        let file = PlannerFile(directory: directory, pendingDirectory: pending)

        #expect(file.availableMonths().isEmpty)
    }

```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/native-search/ios && swift test --filter "PlannerFileTests" 2>&1 | tail -20`
Expected: FAIL to compile — `value of type 'PlannerFile' has no member 'availableMonths'`.

- [ ] **Step 3: Implement `availableMonths()`**

Read `ios/Sources/StarkKit/Planner/PlannerFile.swift`. Find:
```swift
    public func saveMonth(_ month: YearMonth, events: [Event], reminders: [Reminder]) throws {
        try save(fileName: month.fileName, events: events, reminders: reminders)
    }
```

Insert directly after it:
```swift

    /// Every month file that exists in `directory`, discovered by filename pattern
    /// (`YYYY-MM.ics`) rather than assumed — the app has no other way to know which months
    /// have ever been saved, which Search needs in order to load everything rather than just
    /// the agenda's display window. Skips `recurring.ics` and anything that isn't a two-part
    /// `YYYY-MM` filename. Returns `[]` if `directory` doesn't exist yet or can't be
    /// enumerated (a normal state for a brand-new install, not an error).
    public func availableMonths() -> [YearMonth] {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url -> YearMonth? in
            let name = url.lastPathComponent
            guard name.hasSuffix(".ics"), name != "recurring.ics" else { return nil }
            let base = String(name.dropLast(4))
            let parts = base.split(separator: "-")
            guard parts.count == 2, let year = Int(parts[0]), let month1 = Int(parts[1]), (1...12).contains(month1) else {
                return nil
            }
            return YearMonth(year: year, month0: month1 - 1)
        }
    }
```

- [ ] **Step 4: Run to verify the `PlannerFile` tests pass**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/native-search/ios && swift test --filter "PlannerFileTests" 2>&1 | tail -20`
Expected: all `PlannerFileTests` pass, including the 2 new ones.

- [ ] **Step 5: Write the failing `PlannerStore.loadAllMonths()` tests**

Read `ios/Tests/StarkKitTests/PlannerStoreTests.swift` first — confirm the `makeStore()`/`start(_:around:)` helpers near the top of the file match what's used below (they should, unchanged from prior plans in this repo).

Find:
```swift
    @Test("deleting the only event in a month removes the month file instead of leaving an empty stub")
```

Insert directly before it:
```swift
    @Test("loadAllMonths loads a month outside the normal display window")
    @MainActor
    func loadAllMonthsLoadsEverything() async throws {
        let (store, file, _) = makeStore()
        // Far outside any reasonable display window, and written directly to disk (not via
        // the store), so nothing has loaded it yet.
        try file.saveMonth(
            YearMonth(year: 2020, month0: 0),
            events: [Event(title: "Old Event", start: DateMath.date(from: "2020-01-15"))],
            reminders: []
        )
        start(store, around: DateMath.date(from: "2026-09-01"))
        #expect(!store.events.map(\.title).contains("Old Event"))

        await store.loadAllMonths()

        #expect(store.events.map(\.title).contains("Old Event"))
    }

    @Test("loadAllMonths is a no-op the second time -- already-loaded months aren't re-read")
    @MainActor
    func loadAllMonthsSecondCallIsNoOp() async throws {
        let (store, file, _) = makeStore()
        try file.saveMonth(
            YearMonth(year: 2020, month0: 0),
            events: [Event(id: "old", title: "Old Event", start: DateMath.date(from: "2020-01-15"))],
            reminders: []
        )
        start(store, around: DateMath.date(from: "2026-09-01"))

        await store.loadAllMonths()
        let countAfterFirst = store.events.count
        await store.loadAllMonths()

        #expect(store.events.count == countAfterFirst)
    }

```

- [ ] **Step 6: Run to verify failure**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/native-search/ios && swift test --filter "PlannerStoreTests" 2>&1 | tail -20`
Expected: FAIL to compile — `value of type 'PlannerStore' has no member 'loadAllMonths'`.

- [ ] **Step 7: Implement `loadAllMonths()`**

Read `ios/Sources/StarkKit/Planner/PlannerStore.swift`. Find:
```swift
    public func loadMonth(_ month: YearMonth) {
```

Insert directly before it:
```swift
    /// Loads every month file that exists on disk, not just the months the agenda's display
    /// window touches -- Search needs the user's whole history, not just what's already in
    /// memory. Already-loaded months are skipped (`loadMonth`'s own guard). `await
    /// Task.yield()` between each file lets the main actor process other work (a loading
    /// indicator redrawing) between reads, rather than blocking solid until every file is
    /// read. Safe to call more than once per session: after the first call every month is
    /// already in `loadedMonths`, so later calls are a fast no-op loop.
    public func loadAllMonths() async {
        for month in file.availableMonths() where !loadedMonths.contains(month) {
            loadMonth(month)
            await Task.yield()
        }
    }

```

- [ ] **Step 8: Run to verify the `PlannerStore` tests pass**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/native-search/ios && swift test --filter "PlannerStoreTests" 2>&1 | tail -20`
Expected: all `PlannerStoreTests` pass, including the 2 new ones.

- [ ] **Step 9: Run the full suite**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/native-search/ios && swift test 2>&1 | tail -6`
Expected: 344 tests in 33 suites, all passing (340 baseline + 4 new).

- [ ] **Step 10: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/native-search add ios/Sources/StarkKit/Planner/PlannerFile.swift ios/Sources/StarkKit/Planner/PlannerStore.swift ios/Tests/StarkKitTests/PlannerFileTests.swift ios/Tests/StarkKitTests/PlannerStoreTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/native-search commit -m "feat(ios): PlannerFile.availableMonths and PlannerStore.loadAllMonths for full-history search" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `SearchView` and its floating entry point

**Files:**
- Create: `ios/App/Stark/Stark/SearchView.swift`
- Modify: `ios/App/Stark/Stark/ContentView.swift`

**Interfaces:**
- Consumes (Task 1): `PlannerStore.loadAllMonths() async`.
- Consumes (existing): `AgendaItem(kind:occurrence:displayDate:isOverdue:)`, `AgendaRowView(item:)`, `EditItemView(item:)`, `FlatToolbarButton`, `Colors`/`Spacing`/`Fonts` from `Theme.swift`.
- No new StarkKit or test changes — this task is entirely SwiftUI wiring, verified by both build checks and by the manual checklist in Task 3.

- [ ] **Step 1: Create `SearchView.swift`**

```swift
// ios/App/Stark/Stark/SearchView.swift
import SwiftUI
import StarkKit

/// Full-history text search over titles, notes, and locations. Unlike the agenda, which only
/// ever shows what's currently loaded (today's display window, plus whatever's been scrolled
/// or tapped into), this screen loads every month file that exists on disk the first time it
/// appears (`PlannerStore.loadAllMonths()`), so a search can find anything ever saved.
///
/// One unconditional match across every relevant field, no filter/field picker -- considered
/// during design (a Fantastical-style Title/Notes/Location/All row) and dropped for
/// simplicity.
struct SearchView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isLoadingHistory = true
    @State private var selectedItem: AgendaItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search", text: $query)
                    .foregroundStyle(Colors.text)
                    .padding(Spacing.sm)
                    .background(Colors.separator)
                    .padding(Spacing.md)

                if isLoadingHistory {
                    Spacer()
                    ProgressView()
                        .tint(Colors.accent)
                    Spacer()
                } else if query.isEmpty {
                    Spacer()
                } else {
                    List {
                        ForEach(results) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                AgendaRowView(item: item)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparatorTint(Colors.separator)
                            .listRowBackground(Colors.background)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Colors.background)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                FlatToolbarButton(title: "Close", placement: .cancellationAction) { dismiss() }
            }
            .task {
                await store.loadAllMonths()
                isLoadingHistory = false
            }
            .sheet(item: $selectedItem) { item in EditItemView(item: item) }
        }
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
    }

    /// Every event/reminder matching `query`, sorted by date. Built directly from
    /// `store.events`/`store.reminders` (not through occurrence expansion, unlike the agenda)
    /// -- a search result represents the item's own master record, one row per stored
    /// event/reminder, not per calendar occurrence.
    private var results: [AgendaItem] {
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        var matches: [AgendaItem] = []
        for event in store.events where matches(event, needle: needle) {
            matches.append(AgendaItem(kind: .event(event), occurrence: event.start, displayDate: event.start, isOverdue: false))
        }
        for reminder in store.reminders where matches(reminder, needle: needle) {
            let date = reminder.dueDate ?? Date()
            matches.append(AgendaItem(kind: .reminder(reminder), occurrence: date, displayDate: date, isOverdue: false))
        }
        return matches.sorted { $0.displayDate < $1.displayDate }
    }

    private func matches(_ event: Event, needle: String) -> Bool {
        event.title.lowercased().contains(needle)
            || (event.notes?.lowercased().contains(needle) ?? false)
            || (event.location?.lowercased().contains(needle) ?? false)
    }

    private func matches(_ reminder: Reminder, needle: String) -> Bool {
        reminder.title.lowercased().contains(needle)
            || (reminder.notes?.lowercased().contains(needle) ?? false)
    }
}
```

- [ ] **Step 2: Wire the floating search button into `ContentView`**

Read `ios/App/Stark/Stark/ContentView.swift`. Find:
```swift
    @State private var showAdd = false
```

Replace with:
```swift
    @State private var showAdd = false
    @State private var showSearch = false
```

Find:
```swift
        .overlay(alignment: .bottomTrailing) { addButton }
```

Replace with:
```swift
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: Spacing.sm) {
                searchButton
                addButton
            }
            .padding(Spacing.lg)
        }
```

Find:
```swift
        .sheet(isPresented: $showAdd) { AddItemView() }
```

Replace with:
```swift
        .sheet(isPresented: $showAdd) { AddItemView() }
        .sheet(isPresented: $showSearch) { SearchView() }
```

Find:
```swift
    /// Square (hard-edged, matching the rest of the app), accent-filled, no shadow or glass
    /// effect — flat like `FlatToolbarButton`. 56pt is the usual floating-action-button minimum
    /// touch target, padded off the corner so it never sits flush against the screen edge.
    private var addButton: some View {
        Button {
            showAdd = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Colors.background)
                .frame(width: 56, height: 56)
                .background(Colors.accent)
        }
        .buttonStyle(.plain)
        .padding(Spacing.lg)
        .accessibilityLabel("Add")
    }
```

Replace with:
```swift
    /// Square (hard-edged, matching the rest of the app), accent-filled, no shadow or glass
    /// effect — flat like `FlatToolbarButton`. 56pt is the usual floating-action-button minimum
    /// touch target. Padding off the screen corner now lives on the HStack wrapping this and
    /// `searchButton` together, not on each button individually (that would double the gap
    /// between them).
    private var addButton: some View {
        Button {
            showAdd = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Colors.background)
                .frame(width: 56, height: 56)
                .background(Colors.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
    }

    /// Same square/flat/accent style as `addButton`, magnifying-glass glyph, positioned to its
    /// left in the bottom-trailing HStack.
    private var searchButton: some View {
        Button {
            showSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Colors.background)
                .frame(width: 56, height: 56)
                .background(Colors.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
    }
```

- [ ] **Step 3: Verify both destinations build**

Run the iOS build check (Global Constraints) — expect `** BUILD SUCCEEDED **`.
Run the Mac Catalyst build check (Global Constraints) — expect `** BUILD SUCCEEDED **`.
Run `swift test` from `ios/` — expect 344 tests, all passing, unchanged (this task doesn't touch `Sources/StarkKit` or `Tests/StarkKitTests`).

- [ ] **Step 4: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/native-search add ios/App/Stark/Stark/SearchView.swift ios/App/Stark/Stark/ContentView.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/native-search commit -m "feat(ios): full-history search, opened from a floating button next to Add" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Final regression pass, docs, and the manual verification checklist

**Files:**
- Modify: `CLAUDE.md` (Native iOS App section)

**Interfaces:** None — this task adds no code, only documentation and verification.

- [ ] **Step 1: Full regression check**

Run both build checks (Global Constraints) — expect `** BUILD SUCCEEDED **` for both, with no new warnings from the files this plan touched (`PlannerFile.swift`, `PlannerStore.swift`, `SearchView.swift`, `ContentView.swift`).

Run `swift test` from `ios/` — expect 344 tests in 33 suites, all passing.

- [ ] **Step 2: Document the feature in `CLAUDE.md`**

Read `CLAUDE.md`. In the "Native iOS App (`ios/`)" section, add one paragraph after the "Scroll-synced calendar selection" paragraph (i.e. directly before the "Repeat End and event URL" paragraph):

```markdown
**Search** (`SearchView`, `PlannerFile.availableMonths`, `PlannerStore.loadAllMonths`): a second floating button next to Add opens full-history text search — unlike the agenda, which only shows what's currently loaded (today's display window plus whatever's been scrolled/tapped into), Search loads every month file that exists on disk the first time it appears, so it can find anything ever saved, not just what's nearby in time. `availableMonths()` discovers which month files exist by filename pattern (the app previously had no way to enumerate them at all); `loadAllMonths()` loads each one not already in memory, yielding to the main actor between files so a loading indicator can animate rather than the UI freezing. One unconditional case-insensitive substring match across title, notes, and location (events) or title and notes (reminders) — no field picker (a Fantastical-style Title/Notes/Location/All row was considered and dropped for simplicity). Results reuse `AgendaRowView` for display and open the existing `EditItemView` on tap, built directly from the matched `Event`/`Reminder` (not through occurrence expansion) — one row per stored record, and editing a recurring result edits its master series, same as everywhere else in the app.
```

- [ ] **Step 3: Commit the docs**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/native-search add CLAUDE.md
git -C /Users/eladio/src/todo-txt/.claude/worktrees/native-search commit -m "docs: document native app search" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Manual verification checklist (controller only — not an automated step)**

A coding agent can build the app but cannot type into a real search field or judge loading-indicator smoothness. The controller runs the app (simulator or device) and confirms, by hand:

- Tapping the new magnifying-glass button (left of Add) opens Search.
- The first time Search opens, a loading indicator shows briefly, then the search field is usable.
- Typing a query that matches an event/reminder's title, notes, or location shows it in results; typing something that matches nothing shows an empty list, not an error.
- Tapping a result opens the same edit sheet as tapping it in the agenda would, with the same fields.
- Editing and saving a result from Search reflects correctly back in the agenda after closing Search.
- Closing Search and reopening it is instant (no second loading delay) within the same app session.
- On the real device, with the author's full real dataset (thousands of lines), confirm the first-open loading time is reasonable and the app doesn't appear to hang.

This checklist is the acceptance test for this plan.

## Self-Review

- **Spec coverage:** `availableMonths()`/`loadAllMonths()` → Task 1; floating search button next to Add, same style → Task 2; search TextField + results reusing `AgendaRowView` → Task 2; loading state on first open → Task 2 (`isLoadingHistory`) + Task 3 checklist; unconditional title+notes+location/title+notes matching, no filter chips → Task 2 (`matches` functions) + Global Constraints; results open `EditItemView` via a directly-constructed `AgendaItem` → Task 2; error handling reuses `loadMonth`'s existing behavior → Task 1 (no new error-handling code needed, `loadMonth` unchanged); testing (StarkKit TDD, app-layer build+manual) → every task's steps, Task 3 for the full manual checklist; docs → Task 3.
- **Placeholder scan:** no TBD/TODO; every code step shows the exact before/after Swift or the exact new file content.
- **Type consistency:** `PlannerFile.availableMonths() -> [YearMonth]` (Task 1, produced) matches its consumption in `PlannerStore.loadAllMonths()` (`for month in file.availableMonths()`, same task). `PlannerStore.loadAllMonths() async` (Task 1, produced) matches its consumption in `SearchView.body`'s `.task { await store.loadAllMonths() }` (Task 2). `AgendaItem(kind:occurrence:displayDate:isOverdue:)` matches the existing public initializer confirmed by reading `AgendaBuilder.swift` during plan authoring. `AgendaRowView(item:)` and `EditItemView(item:)` match their existing initializers, confirmed the same way.
- **Scope check:** single subsystem (search), no filter-chip UI (explicitly out of scope per the spec's own reconsideration), no Mac-specific search affordances, no StarkKit changes beyond the two new methods.
