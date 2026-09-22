# Mac Catalyst Target (issue #100) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get the native Swift app (Stark, `ios/`) running as a Mac Catalyst build — same codebase, same bundle id, a resizable Mac window — with a sidebar mode-picker and Mac-appropriate recurrence controls replacing the two touch-only interactions that don't work well with a pointer. Storage stays local and independent per platform for now (no sync yet).

**Architecture:** Mac Catalyst is added as a second destination of the existing `Stark` app target (not a new target). `StarkKit` (all business logic) and almost every SwiftUI view are untouched and shared as-is. The only app-layer changes are `#if targetEnvironment(macCatalyst)` branches — the first platform-conditional code in this codebase — swapping `ModeHandle`'s drag gesture for a sidebar and the wheel-style recurrence pickers for a stepper/menu, plus a minimum window size.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM package `StarkKit` tested with Swift Testing (`import Testing`, `@Test`, `#expect`; never XCTest). Xcode project `ios/App/Stark/Stark.xcodeproj`.

**Spec:** `docs/superpowers/specs/2026-09-22-mac-catalyst-target-design.md`

**Issue:** https://github.com/caritos/todo-txt/issues/100

## Global Constraints

- **Working directory:** `/Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target` (a git worktree, branch `worktree-mac-catalyst-target`, fast-forwarded onto local `main` at commit `c1e23a4`). Use absolute paths; run Swift tests from its `ios/` directory (`swift test`).
- **Shell:** compound commands and heredocs may be rejected. Use plain single commands, the Write/Edit tools for files, `git -C <worktree>` and multiple `-m` flags for commits.
- **Commits:** stage specific paths only (never `git add -A`, `.` or `commit -a`). End every commit message with a separate `-m` paragraph: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Never push.
- **Logic goes in StarkKit, views are thin.** This plan adds no new business logic (nothing here needs a StarkKit test) — every task is Xcode-project configuration or SwiftUI view wiring, verified by building both destinations and (for StarkKit) confirming the existing test suite is unaffected.
- **Baseline:** `swift test` from `ios/` currently passes 321 tests in 31 suites. It must stay green, unchanged, after every task (this plan does not touch `Sources/StarkKit` or `Tests/StarkKitTests`).
- **iOS build check** (every task): `cd /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` must end in `** BUILD SUCCEEDED **`. This is the regression check — the iPhone build and behavior must never change.
- **Mac Catalyst build check** (Tasks 1-3): `cd /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` must end in `** BUILD SUCCEEDED **`.
- **Theme:** only `Colors.*`, `Spacing.*`, `Fonts.mono` from `Theme.swift`; no hardcoded hex, no new colors, no rounded corners (hard edges) anywhere, including new Mac-only views.
- **Do not touch `mobile/`** (the Expo app is deprecated) or the author's iPhone (no `xcrun devicectl`, no `deploy.sh` — this plan is Mac-only; there is no physical Mac to install onto, since Catalyst builds and runs directly on the development machine).
- **Storage is out of scope.** Do not add any iCloud/ubiquity-container/bookmark code in this plan — that is a separate, later spec/plan per issue #100. The Mac and iPhone builds are expected to show *different* local data after this plan; that is correct, not a bug.
- **Interactive verification (window resizing, clicking the sidebar, mouse/trackpad input, the day-rollover notification) is the controller's job, not an automated step** — a coding agent can build and launch the Mac app, but cannot click through its UI. Task 4 lists this checklist explicitly as a manual, controller-only step.

---

### Task 1: Enable the Mac Catalyst destination and size the window

**Files:**
- Modify: `ios/App/Stark/Stark.xcodeproj/project.pbxproj` (both `Debug` and `Release` `XCBuildConfiguration` blocks, currently at lines 255-289 and 290-324)
- Modify: `ios/App/Stark/Stark/StarkApp.swift`

**Interfaces:**
- No new types. Verified by the two build checks above; no StarkKit tests apply.

- [ ] **Step 1: Add the Catalyst platform and device family**

From `ios/App/Stark/Stark`, run:

```bash
cd /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target/ios/App/Stark
perl -pi -e 's/SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";/SUPPORTED_PLATFORMS = "iphoneos iphonesimulator maccatalyst";\n\t\t\t\tSUPPORTS_MACCATALYST = YES;/g' Stark.xcodeproj/project.pbxproj
perl -pi -e 's/TARGETED_DEVICE_FAMILY = 1;/TARGETED_DEVICE_FAMILY = "1,2";/g' Stark.xcodeproj/project.pbxproj
```

This must change exactly 4 lines in total (2 occurrences of `SUPPORTED_PLATFORMS` gaining a new `SUPPORTS_MACCATALYST` line after each, 2 occurrences of `TARGETED_DEVICE_FAMILY`) — one for `Debug`, one for `Release`. Verify:

```bash
grep -c "SUPPORTS_MACCATALYST = YES;" Stark.xcodeproj/project.pbxproj
```

Expected: `2`.

```bash
grep -c 'TARGETED_DEVICE_FAMILY = "1,2";' Stark.xcodeproj/project.pbxproj
```

Expected: `2`. If either count isn't 2, the `perl` command didn't match (check for accidental prior edits) — do not proceed until both are exactly 2.

Device family `2` (iPad idiom) must be added alongside `1` (iPhone) because Mac Catalyst runs the iPad idiom under the hood — this is a Catalyst technical requirement, not a decision to support iPad as its own target. No iPad-specific layout is being built (see Global Constraints in the spec's Non-goals).

- [ ] **Step 2: Verify both destinations build**

Run the iOS build check (Global Constraints) — expect `** BUILD SUCCEEDED **`.
Run the Mac Catalyst build check (Global Constraints) — expect `** BUILD SUCCEEDED **`. (This has already been validated to succeed with only the Step 1 change — no entitlements file is needed: `ENABLE_APP_SANDBOX = YES` and `ENABLE_HARDENED_RUNTIME = YES` are already present in both build configs, part of Xcode's newer build-setting-synthesized-entitlements mechanism, the same mechanism `GENERATE_INFOPLIST_FILE` uses for Info.plist.)

- [ ] **Step 3: Give the Mac window a sensible minimum size**

Read `ios/App/Stark/Stark/StarkApp.swift`. Find:

```swift
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(pending)
        }
    }
```

Replace with:

```swift
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(pending)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 480, minHeight: 520)
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .windowResizability(.contentSize)
        #endif
    }
```

Without this, an aggressively resized Mac window has no floor: `MonthGridView`/`YearView` use fixed-height rows (e.g. `rowHeight`, `cellSize`, 44pt chevron targets) that don't shrink with the window, so a too-small window would crush or clip the agenda area. `480x520` comfortably fits the sidebar (added in Task 2) plus a month grid and a few agenda rows; this is a starting value the controller can adjust after visually checking it in Task 4 — the number itself is not being unit-tested (there's nothing here for a test to assert; this is UI polish verified by eye).

- [ ] **Step 4: Verify both destinations still build**

Run both build checks (Global Constraints) — expect `** BUILD SUCCEEDED **` for both. Run `swift test` from `ios/` — expect 321 tests, all passing, unchanged (this task doesn't touch `Sources/StarkKit`).

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target add ios/App/Stark/Stark.xcodeproj/project.pbxproj ios/App/Stark/Stark/StarkApp.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target commit -m "feat(ios): enable the Mac Catalyst destination and size its window (#100)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Sidebar mode-picker on Mac, replacing `ModeHandle`

**Files:**
- Create: `ios/App/Stark/Stark/CalendarSidebar.swift`
- Modify: `ios/App/Stark/Stark/ContentView.swift`
- Modify: `ios/App/Stark/Stark/YearView.swift`

**Interfaces:**
- Consumes (existing): `CalendarMode` (`StarkKit`, unchanged — `.week`/`.month`/`.year`, `.title`).
- Produces: `CalendarSidebar(mode: Binding<CalendarMode>)` — a Mac-only `View`. Nothing outside `ContentView.swift` depends on it.
- No StarkKit changes, no new tests — this is SwiftUI wiring; the `CalendarMode` logic it drives is already tested (`CalendarModeTests`). Verified by both build checks; the sidebar's actual clicking behavior is confirmed in Task 4's manual checklist.

- [ ] **Step 1: Create `CalendarSidebar.swift`**

```swift
// ios/App/Stark/Stark/CalendarSidebar.swift
import SwiftUI
import StarkKit

/// Mac Catalyst's replacement for `ModeHandle`'s drag gesture: a sidebar list that selects
/// `CalendarMode` directly. `ModeHandle`'s drag/tap gesture has no pointer/hover affordance and
/// isn't a Mac-appropriate interaction (see the portability notes in the Mac Catalyst target
/// design doc), so on Mac the same `mode` state `ContentView` already owns is driven by picking
/// a row here instead. iPhone keeps using `ModeHandle`; this view is only ever built inside
/// `#if targetEnvironment(macCatalyst)` in `ContentView`.
struct CalendarSidebar: View {
    @Binding var mode: CalendarMode

    private static let modes: [CalendarMode] = [.week, .month, .year]

    var body: some View {
        List(selection: modeSelection) {
            ForEach(Self.modes, id: \.self) { candidate in
                Text(candidate.title)
                    .foregroundStyle(Colors.text)
                    .tag(candidate)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Stark")
    }

    /// `List(selection:)` requires an `Optional<CalendarMode>` binding (a sidebar list can have
    /// nothing selected); `mode` itself is always non-optional, so this adapts between the two
    /// without ever writing `nil` back into `mode`.
    private var modeSelection: Binding<CalendarMode?> {
        Binding(
            get: { mode },
            set: { newValue in
                guard let newValue else { return }
                mode = newValue
            }
        )
    }
}
```

- [ ] **Step 2: Wrap `ContentView`'s screen content and branch the container**

Read `ios/App/Stark/Stark/ContentView.swift`. Its current `body` is:

```swift
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = store.error {
                    Button {
                        store.error = nil
                    } label: {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Colors.text)
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Colors.accent)
                    }
                }
                ZStack {
                    VStack(spacing: 0) {
                        MonthGridView(today: today, mode: mode, selectedDate: selectedDate, onSelectDate: selectDate)
                        ModeHandle(mode: $mode)
                        Rectangle()
                            .fill(Colors.separator)
                            .frame(height: 1)
                        AgendaView(today: today, anchor: agendaAnchor, scrollRequest: scrollRequest, onSelect: { selectedItem = $0 })
                    }
                    // Hidden (not removed) in year mode: tearing the agenda down would lose its
                    // scroll position and, on coming back, scroll to today instead of the day
                    // picked in the year. Not tappable or readable by VoiceOver while hidden.
                    .opacity(mode == .year ? 0 : 1)
                    .allowsHitTesting(mode != .year)
                    .accessibilityHidden(mode == .year)

                    if mode == .year {
                        YearView(today: today, selectedDate: selectedDate, mode: $mode) { date in
                            selectDate(date)
                            withAnimation(.easeInOut(duration: 0.2)) { mode = .month }
                        }
                        .transition(.opacity)
                    }
                }
            }
            .background(Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                FlatToolbarButton(title: "Add", systemImage: "plus", placement: .primaryAction) { showAdd = true }
            }
            .sheet(isPresented: $showAdd) { AddItemView() }
            .sheet(item: $selectedItem) { item in EditItemView(item: item) }
            .task {
                // Load the wider window (includes the overdue lookback), not the display window.
                let range = AgendaWindow.loadRange(around: Date())
                store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    store.retryPendingWrites()
                    followCalendarDay()
                } else {
                    // The undo window's timer doesn't survive the app being suspended or
                    // killed, so commit any still-pending completions on the way out.
                    pending.flush()
                }
            }
            // Midnight, or the clock / timezone changed, while the app is in the foreground.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                followCalendarDay()
            }
        }
        .tint(Colors.accent)
        // The design is dark-only (Colors.* are dark-theme tokens); without this, system
        // sheets and Forms would render light with near-white text.
        .preferredColorScheme(.dark)
    }
```

Replace the whole `body` with this — the content of the old `NavigationStack` moves, unchanged except for one `#if` around the `ModeHandle` line, into a new `screenContent` computed property; `body` now branches the navigation container by platform:

```swift
    var body: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            NavigationSplitView {
                CalendarSidebar(mode: $mode)
            } detail: {
                screenContent
            }
            #else
            NavigationStack {
                screenContent
            }
            #endif
        }
        .tint(Colors.accent)
        // The design is dark-only (Colors.* are dark-theme tokens); without this, system
        // sheets and Forms would render light with near-white text.
        .preferredColorScheme(.dark)
    }

    /// The grid, drag bar (iPhone only — Mac drives `mode` from `CalendarSidebar` instead),
    /// separator and agenda, or the year overlay in year mode; plus every modifier that used to
    /// hang off the old single `NavigationStack` body (background, toolbar, sheets, load-on-
    /// appear, foreground/day-rollover handling). Identical between platforms except the missing
    /// `ModeHandle` row on Mac.
    private var screenContent: some View {
        VStack(spacing: 0) {
            if let error = store.error {
                Button {
                    store.error = nil
                } label: {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Colors.text)
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Colors.accent)
                }
            }
            ZStack {
                VStack(spacing: 0) {
                    MonthGridView(today: today, mode: mode, selectedDate: selectedDate, onSelectDate: selectDate)
                    #if !targetEnvironment(macCatalyst)
                    ModeHandle(mode: $mode)
                    #endif
                    Rectangle()
                        .fill(Colors.separator)
                        .frame(height: 1)
                    AgendaView(today: today, anchor: agendaAnchor, scrollRequest: scrollRequest, onSelect: { selectedItem = $0 })
                }
                // Hidden (not removed) in year mode: tearing the agenda down would lose its
                // scroll position and, on coming back, scroll to today instead of the day
                // picked in the year. Not tappable or readable by VoiceOver while hidden.
                .opacity(mode == .year ? 0 : 1)
                .allowsHitTesting(mode != .year)
                .accessibilityHidden(mode == .year)

                if mode == .year {
                    YearView(today: today, selectedDate: selectedDate, mode: $mode) { date in
                        selectDate(date)
                        withAnimation(.easeInOut(duration: 0.2)) { mode = .month }
                    }
                    .transition(.opacity)
                }
            }
        }
        .background(Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            FlatToolbarButton(title: "Add", systemImage: "plus", placement: .primaryAction) { showAdd = true }
        }
        .sheet(isPresented: $showAdd) { AddItemView() }
        .sheet(item: $selectedItem) { item in EditItemView(item: item) }
        .task {
            // Load the wider window (includes the overdue lookback), not the display window.
            let range = AgendaWindow.loadRange(around: Date())
            store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.retryPendingWrites()
                followCalendarDay()
            } else {
                // The undo window's timer doesn't survive the app being suspended or
                // killed, so commit any still-pending completions on the way out.
                pending.flush()
            }
        }
        // Midnight, or the clock / timezone changed, while the app is in the foreground.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            followCalendarDay()
        }
    }
```

Note what did **not** change: `YearView` is still shown in both platforms when `mode == .year` (it is the *content* of year mode, not the mode picker) — only its own embedded `ModeHandle` (Step 3, below) is Mac-conditional.

- [ ] **Step 3: Omit `YearView`'s embedded `ModeHandle` on Mac**

Read `ios/App/Stark/Stark/YearView.swift`. Find, near the end of `body`:

```swift
            ModeHandle(mode: $mode)
        }
        .background(Colors.background)
```

Replace with:

```swift
            #if !targetEnvironment(macCatalyst)
            ModeHandle(mode: $mode)
            #endif
        }
        .background(Colors.background)
```

`YearView`'s `ModeHandle` exists so a drag or a tap can return to month mode from inside year mode. On Mac the sidebar already does this (selecting "Week" or "Month" there), so this row would be a redundant, non-pointer-friendly control if left in.

- [ ] **Step 4: Verify both destinations build**

Run both build checks (Global Constraints) — expect `** BUILD SUCCEEDED **` for both. Run `swift test` from `ios/` — expect 321 tests, all passing, unchanged.

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target add ios/App/Stark/Stark/CalendarSidebar.swift ios/App/Stark/Stark/ContentView.swift ios/App/Stark/Stark/YearView.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target commit -m "feat(ios): sidebar mode-picker on Mac, replacing the drag bar (#100)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Mac-appropriate recurrence interval/unit controls

**Files:**
- Modify: `ios/App/Stark/Stark/CustomRepeatView.swift`

**Interfaces:**
- Consumes (existing): `$interval: State<Int>`, `$unit: State<RecurrenceRule.Frequency>` (both already defined in this file, unchanged). No new types.
- No StarkKit changes, no new tests — this is a control swap that writes the same `RecurrenceRule` fields the wheel pickers already did (verified by `buildRule()`, unchanged). Verified by both build checks; round-trip behavior is confirmed in Task 4's manual checklist.

- [ ] **Step 1: Branch the interval/unit row by platform**

Read `ios/App/Stark/Stark/CustomRepeatView.swift`. Find:

```swift
            Section {
                HStack {
                    Picker("Interval", selection: $interval) {
                        ForEach(1..<100, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()

                    Picker("Unit", selection: $unit) {
                        Text("day").tag(RecurrenceRule.Frequency.daily)
                        Text("week").tag(RecurrenceRule.Frequency.weekly)
                        Text("month").tag(RecurrenceRule.Frequency.monthly)
                        Text("year").tag(RecurrenceRule.Frequency.yearly)
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }
                .frame(height: 216)
            }
```

Replace with:

```swift
            Section {
                #if targetEnvironment(macCatalyst)
                HStack {
                    Stepper(value: $interval, in: 1..<100) {
                        Text("Every \(interval)").foregroundStyle(Colors.text)
                    }
                    Picker("Unit", selection: $unit) {
                        Text("day").tag(RecurrenceRule.Frequency.daily)
                        Text("week").tag(RecurrenceRule.Frequency.weekly)
                        Text("month").tag(RecurrenceRule.Frequency.monthly)
                        Text("year").tag(RecurrenceRule.Frequency.yearly)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                #else
                HStack {
                    Picker("Interval", selection: $interval) {
                        ForEach(1..<100, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()

                    Picker("Unit", selection: $unit) {
                        Text("day").tag(RecurrenceRule.Frequency.daily)
                        Text("week").tag(RecurrenceRule.Frequency.weekly)
                        Text("month").tag(RecurrenceRule.Frequency.monthly)
                        Text("year").tag(RecurrenceRule.Frequency.yearly)
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }
                .frame(height: 216)
                #endif
            }
```

The iPhone branch is byte-for-byte the original code — only the Mac branch is new. Both branches still write into the same `$interval`/`$unit` state, which `commit()` (unchanged, `.onChange(of: interval)` / `.onChange(of: unit)`, both still present below this section) turns into a `RecurrenceRule` exactly as before — this is a control swap, not a data-model change. The 216pt-tall `.pickerStyle(.wheel)` is iOS's `UIPickerView` minimum height requirement (see `CLAUDE.md`'s note on this exact constant); the Mac branch has no such constraint, so it doesn't need the `.frame(height: 216)`.

- [ ] **Step 2: Verify both destinations build**

Run both build checks (Global Constraints) — expect `** BUILD SUCCEEDED **` for both. Run `swift test` from `ios/` — expect 321 tests, all passing, unchanged.

- [ ] **Step 3: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target add ios/App/Stark/Stark/CustomRepeatView.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target commit -m "feat(ios): Mac-appropriate recurrence interval/unit controls (#100)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Final regression pass, docs, and the manual verification checklist

**Files:**
- Modify: `CLAUDE.md` (Native iOS App section)

**Interfaces:** None — this task adds no code, only documentation and verification.

- [ ] **Step 1: Full regression check**

Run both build checks (Global Constraints) — expect `** BUILD SUCCEEDED **` for both, with no new warnings from any of the six files this plan touched (`project.pbxproj`, `StarkApp.swift`, `CalendarSidebar.swift`, `ContentView.swift`, `YearView.swift`, `CustomRepeatView.swift`).

Run `swift test` from `ios/` — expect 321 tests in 31 suites, all passing, identical to the baseline in Global Constraints (this plan never touched `Sources/StarkKit` or `Tests/StarkKitTests`).

- [ ] **Step 2: Document the Mac Catalyst target in `CLAUDE.md`**

Read `CLAUDE.md`. In the "Native iOS App (`ios/`)" section, add one paragraph after the "Row hit-testing — never nest Buttons in a `List` row" paragraph:

```markdown
**Mac Catalyst target** (`CalendarSidebar`; issue #100): the app also builds and runs as a Mac Catalyst destination of the same `Stark` target (`SUPPORTED_PLATFORMS` includes `maccatalyst`, `TARGETED_DEVICE_FAMILY = "1,2"` — Catalyst requires the iPad idiom even though no iPad-specific layout exists). `StarkKit` and almost every view are shared unchanged; the only differences are gated by `#if targetEnvironment(macCatalyst)`, the first platform-conditional code in this codebase. On Mac, `ContentView` wraps its content in a `NavigationSplitView` with `CalendarSidebar` (a `List` selecting `CalendarMode` directly) instead of a plain `NavigationStack`, and both `ContentView` and `YearView` omit `ModeHandle` — its drag/tap gesture has no pointer/hover affordance, so the sidebar is the Mac-appropriate replacement for switching week/month/year. `CustomRepeatView`'s interval/unit pickers likewise swap `.pickerStyle(.wheel)` (an iOS `UIPickerView` touch-flick control) for a `Stepper` + `Picker(.menu)` on Mac; both branches still write the same `RecurrenceRule` fields. The window has a `480x520` minimum size (`StarkApp`, `.windowResizability(.contentSize)`) since the grid's fixed-height rows don't shrink with the window. **Storage is still local and independent per platform** — the Mac and iPhone builds show different data until a later, separate spec adds shared iCloud container storage (see issue #100). Distribution: Mac Catalyst is a second destination of the existing `com.caritos.todo-txt` App Store Connect record (Universal Purchase), not yet submitted.
```

- [ ] **Step 3: Commit the docs**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target add CLAUDE.md
git -C /Users/eladio/src/todo-txt/.claude/worktrees/mac-catalyst-target commit -m "docs: document the Mac Catalyst target (#100)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Manual verification checklist (controller only — not an automated step)**

A coding agent can build and launch the Mac Catalyst app but cannot click through its UI or judge visual layout. The controller runs the Mac Catalyst build (Xcode, destination "My Mac (Mac Catalyst)", or `xcodebuild ... -destination 'platform=macOS,variant=Mac Catalyst'` then open the built `.app` from `DerivedData`) and confirms, by hand:

- The sidebar shows Week / Month / Year; clicking each one drives the same agenda content the drag bar would on iPhone (the grid/agenda for Week and Month, the twelve-mini-month `YearView` for Year).
- Clicking a day in `YearView` still returns to Month and scrolls the agenda to that day (this path is unchanged code, but confirm it still works with the sidebar in place).
- The custom recurrence screen's `Stepper` + menu `Picker` set the same interval/unit an iPhone build's wheel pickers would (e.g., set "Every 3 weeks" on Mac, confirm the saved item's summary text and the underlying `RecurrenceRule` match what the iPhone wheel picker would have produced for the same input).
- Resizing the window, including toward the 480x520 minimum, doesn't crush or clip the grid or agenda.
- The day-rollover notification (`UIApplication.significantTimeChangeNotification`) actually fires on Mac: change the system clock forward past midnight (or wait) while the app is foregrounded, and confirm `today` advances (the highlighted "today" cell and section move) without a relaunch. This was flagged in the spec as unverified — record the outcome (works / doesn't fire) either in a follow-up issue comment on #100 or as a doc update, whichever the controller prefers.
- Add/Edit sheets, checkbox completion (the 2.5s undo window), and event outcome actions (Attended/Didn't Attend) all work with mouse/trackpad clicks, not just the touch interactions they were built for.

This checklist is the acceptance test for this plan — once it passes, issue #100's first sub-project (Mac Catalyst target) is done, and the shared-storage sub-project (separate spec/plan) can begin.

## Self-Review

- **Spec coverage:** Xcode project changes (SUPPORTED_PLATFORMS/SUPPORTS_MACCATALYST/TARGETED_DEVICE_FAMILY, no entitlements needed) → Task 1; sidebar mode-picker replacing `ModeHandle` on both `ContentView` and `YearView` → Task 2; Mac-appropriate recurrence controls → Task 3; window sizing → Task 1; distribution (documented, not submitted) → Task 4 docs; testing (build checks both destinations, `swift test` regression, manual checklist) → every task's Step verifying builds, Task 4 for the full manual checklist; non-goals (no shared storage, no Search feature, no App Store submission, no broader UI redesign, no iPad-specific layout) → called out explicitly in Global Constraints and Task 1's Step 1 note.
- **Placeholder scan:** no TBD/TODO; every code step shows the exact before/after Swift or the exact shell command; the window-size numbers (480x520) are stated as a starting value for the controller to adjust after visual inspection, not a placeholder — there is no "correct" value to compute, only one to look at.
- **Type consistency:** `CalendarSidebar(mode: Binding<CalendarMode>)` in Task 2 Step 1 matches its call site `CalendarSidebar(mode: $mode)` in Task 2 Step 2; `CalendarMode.title` (used in `CalendarSidebar`) matches the existing `CalendarMode.swift` definition (`Sources/StarkKit/Planner/CalendarMode.swift`) verified by reading the file before writing this plan.
- **Scope check:** single subsystem (get Stark running on Mac Catalyst); the dependent shared-storage subsystem is explicitly out of scope and left to a separate spec/plan, as decided during brainstorming.
