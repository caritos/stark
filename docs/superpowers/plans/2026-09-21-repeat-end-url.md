# Repeat End and Event URL (issue #97) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two more pieces of Fantastical's New Event sheet in the native iOS app: a **Repeat End** row (Never / On Date / After N times) for recurring events and reminders, and a **URL** field on events (with an Open Link button in the edit sheet).

**Architecture:** Pure StarkKit pieces (`RepeatEnd`, `RecurrenceRule.withoutEnd`, `Event.url` with its `URL:` `.ics` line) carry the decisions; the add/edit screens keep the end as separate form state because the repeat picker replaces the whole rule (it would wipe an end) and applies the end on save. Alerts are a separate later design.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM package `StarkKit` tested with Swift Testing (`import Testing`, `@Test`, `#expect`; never XCTest).

**Issue:** https://github.com/caritos/todo-txt/issues/97 (Fantastical's New Event sheet: a "Repeat End" row under Repeat once Repeat is not Never, and a URL field above Notes; the Repeat End picker's own screenshots are among the issue's two broken images, so its options are our choice).

**Design (approved in conversation 2026-09-21):**
- **Repeat End**: a row below Repeat, shown only while Repeat is not Never, on add and edit, for events and reminders. Options: **Never**, **On Date** (a date picker), **After N times** (a stepper, 1 or more). The row's value shows "Never", "Dec 31, 2026" or "10 times". `RecurrenceRule.count`/`until` already exist and the `.ics` codec (`COUNT=`, date-only `UNTIL=`) and `OccurrenceExpander` already honour them — this is screens plus a small pure type.
- **Why separate state**: `RepeatPickerView`'s presets replace the whole `recurrence` (dropping `count`/`until`), and its checkmark compares whole rules. So the screens hold `recurrence` with the end stripped (`RecurrenceRule.withoutEnd`) plus a `RepeatEnd` state, and apply it on save (`RepeatEnd.applied(to:)`). Opening an item and saving it unchanged must leave its rule exactly as it was. Choosing Repeat = Never resets the end to Never.
- **End date rules**: stored date-only at the start of its day (`UNTIL` is date-only); the date picker's range starts at the start day; when the start moves past an end date the end moves to the start's day (`RepeatEnd.clamped(toStartOn:)`); `afterCount` is at least 1.
- **URL (events only)**: `Event.url: String?` (last init parameter, default nil), written as a plain, unescaped `URL:` line **after `LOCATION` and before `RRULE`** (RFC 5545 URI value: no TEXT escaping), with any CR/LF stripped so a pasted value can never inject a property line. The parser reads `URL` (also `URL;VALUE=URI`). An event without a URL writes no line, so existing files and the migration golden fixtures stay byte-identical. Blank saves as none (`FormFields.trimmedOrNil`). The edit sheet shows **Open Link** when the URL parses with an `http`/`https` scheme. Reminders get no URL.
- **Out of scope:** Alerts (own design later), a URL on reminders, showing the URL on the agenda row, time zones, calendars, natural-language quick add, changing the repeat presets.

## Global Constraints

- **Working directory:** `/Users/eladio/src/todo-txt/.claude/worktrees/repeat-end-url` (a git worktree, branch `worktree-repeat-end-url`). Use absolute paths; run Swift tests from its `ios/` directory (`swift test`).
- **Shell:** compound commands and heredocs may be rejected. Use plain single commands, the Write/Edit tools for files, `git -C <worktree>` and multiple `-m` flags for commits.
- **Commits:** stage specific paths only (never `git add -A`, `.` or `commit -a`). End every commit message with a separate `-m` paragraph: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Never push.
- **Logic goes in StarkKit, views are thin.** If it can be tested, it lives in `ios/Sources/StarkKit` with a Swift Testing test.
- **Tests first** for StarkKit work: write the failing test, run it and see it fail for the stated reason, then implement.
- **Baseline:** `swift test` currently passes 304 tests (three env-gated parity tests are skipped by design; `PendingCompletionsTests.liveSchedulerRunsAndCancels` is a real-time test that can flake right after an xcodebuild — rerun it alone if it fails). It must stay green after every task.
- **`.ics` format:** exactly what `ICSSerializer` writes (CRLF, property order UID, SUMMARY, DTSTART, DTEND, DESCRIPTION, LOCATION, **URL**, RRULE, EXDATE, X-STARK-*). The migration golden fixtures (`shared/tests/fixtures/ics/expected/`, checked by `ExportFixtureTests`) must keep passing unchanged.
- **Theme:** only `Colors.*`, `Spacing.*`, `Fonts.mono` from `Theme.swift`; no hardcoded hex, no new colours, no rounded corners (hard edges).
- **Do not touch the author's phone** (no `xcrun devicectl`, no `deploy.sh`); the controller does the on-device check.
- **App build check** (Task 2): `cd /Users/eladio/src/todo-txt/.claude/worktrees/repeat-end-url/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` must end in `** BUILD SUCCEEDED **`.

---

### Task 1: `RepeatEnd`, `withoutEnd` and `Event.url` (StarkKit)

**Files:**
- Create: `ios/Sources/StarkKit/Models/RepeatEnd.swift`
- Modify: `ios/Sources/StarkKit/Models/Event.swift` (add `url`)
- Modify: `ios/Sources/StarkKit/ICS/ICSSerializer.swift`, `ios/Sources/StarkKit/ICS/ICSParser.swift`
- Create tests: `ios/Tests/StarkKitTests/RepeatEndTests.swift`
- Modify tests: `ios/Tests/StarkKitTests/ICSSerializerTests.swift`, `ios/Tests/StarkKitTests/ICSParserTests.swift`, `ios/Tests/StarkKitTests/EventScheduleTests.swift` (append inside each suite)

**Interfaces:**
- Produces (used by Task 2):
  - `public enum RepeatEnd: Equatable, Sendable { case never, onDate(Date), afterCount(Int) }` with `init(rule: RecurrenceRule?)`, `func applied(to rule: RecurrenceRule?) -> RecurrenceRule?`, `func clamped(toStartOn start: Date) -> RepeatEnd`, `var summary: String`.
  - `RecurrenceRule.withoutEnd: RecurrenceRule` (count and until cleared).
  - `Event.url: String?` (new **last** `init` parameter `url: String? = nil`), the `URL:` line.

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/StarkKitTests/RepeatEndTests.swift`:

```swift
// ios/Tests/StarkKitTests/RepeatEndTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("RepeatEnd")
struct RepeatEndTests {
    private let cal = Calendar(identifier: .gregorian)

    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }
    private func midnight(_ iso: String) -> Date { cal.startOfDay(for: d(iso)) }

    @Test("reads the end off a rule: count, until, or never")
    func reading() {
        #expect(RepeatEnd(rule: nil) == .never)
        #expect(RepeatEnd(rule: RecurrenceRule(frequency: .weekly)) == .never)
        #expect(RepeatEnd(rule: RecurrenceRule(frequency: .weekly, count: 10)) == .afterCount(10))
        #expect(RepeatEnd(rule: RecurrenceRule(frequency: .weekly, until: midnight("2026-12-31"))) == .onDate(midnight("2026-12-31")))
    }

    @Test("a nonsensical count reads as never")
    func nonsenseCount() {
        #expect(RepeatEnd(rule: RecurrenceRule(frequency: .weekly, count: 0)) == .never)
        #expect(RepeatEnd(rule: RecurrenceRule(frequency: .weekly, count: -3)) == .never)
    }

    @Test("applying replaces any earlier end and keeps every other part of the rule")
    func applying() throws {
        let base = RecurrenceRule(frequency: .weekly, interval: 2, byDay: [.monday])

        let onDate = try #require(RepeatEnd.onDate(d("2026-12-31")).applied(to: base))
        #expect(onDate.until == midnight("2026-12-31"))
        #expect(onDate.count == nil)
        #expect(onDate.frequency == .weekly)
        #expect(onDate.interval == 2)
        #expect(onDate.byDay == [.monday])

        let withUntil = RecurrenceRule(frequency: .weekly, until: midnight("2026-10-01"))
        let counted = try #require(RepeatEnd.afterCount(5).applied(to: withUntil))
        #expect(counted.count == 5)
        #expect(counted.until == nil)

        let withCount = RecurrenceRule(frequency: .weekly, count: 8)
        let never = try #require(RepeatEnd.never.applied(to: withCount))
        #expect(never.count == nil)
        #expect(never.until == nil)
    }

    @Test("a count below 1 is applied as 1, and applying to no rule gives no rule")
    func clampAndNil() throws {
        let base = RecurrenceRule(frequency: .daily)
        #expect(try #require(RepeatEnd.afterCount(0).applied(to: base)).count == 1)
        #expect(RepeatEnd.never.applied(to: nil) == nil)
        #expect(RepeatEnd.onDate(d("2026-12-31")).applied(to: nil) == nil)
        #expect(RepeatEnd.afterCount(3).applied(to: nil) == nil)
    }

    @Test("opening a rule and applying its own end to its stripped self is a no-op")
    func unchangedRoundTrip() {
        let rules: [RecurrenceRule?] = [
            nil,
            RecurrenceRule(frequency: .weekly),
            RecurrenceRule(frequency: .weekly, interval: 2, count: 10),
            RecurrenceRule(frequency: .daily, until: midnight("2026-12-31")),
            RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .fourth, weekday: .friday)], until: midnight("2027-03-01")),
        ]
        for rule in rules {
            let end = RepeatEnd(rule: rule)
            #expect(end.applied(to: rule?.withoutEnd) == rule)
        }
    }

    @Test("withoutEnd clears count and until only")
    func withoutEnd() {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, byDay: [.monday], count: 4)
        let stripped = rule.withoutEnd
        #expect(stripped.count == nil)
        #expect(stripped.until == nil)
        #expect(stripped.frequency == .weekly)
        #expect(stripped.interval == 2)
        #expect(stripped.byDay == [.monday])
    }

    @Test("an end date before the start's day moves up to the start's day; later dates and other ends are untouched")
    func clamping() {
        let start = d("2026-09-20")
        #expect(RepeatEnd.onDate(midnight("2026-09-01")).clamped(toStartOn: start) == .onDate(midnight("2026-09-20")))
        #expect(RepeatEnd.onDate(midnight("2026-09-20")).clamped(toStartOn: start) == .onDate(midnight("2026-09-20")))
        #expect(RepeatEnd.onDate(midnight("2026-12-31")).clamped(toStartOn: start) == .onDate(midnight("2026-12-31")))
        #expect(RepeatEnd.never.clamped(toStartOn: start) == .never)
        #expect(RepeatEnd.afterCount(3).clamped(toStartOn: start) == .afterCount(3))
    }

    @Test("summary strings")
    func summaries() {
        #expect(RepeatEnd.never.summary == "Never")
        #expect(RepeatEnd.afterCount(1).summary == "1 time")
        #expect(RepeatEnd.afterCount(10).summary == "10 times")
        #expect(RepeatEnd.onDate(midnight("2026-12-31")).summary == "Dec 31, 2026")
    }
}
```

Append to `ICSSerializerTests` (inside the suite):

```swift
    // MARK: - Event URL

    @Test("serializes an event URL after LOCATION and before RRULE, unescaped")
    func serializesEventURL() {
        let event = Event(
            id: "evt-1",
            title: "Call",
            start: DateMath.date(from: "2026-09-20"),
            location: "Room",
            recurrence: RecurrenceRule(frequency: .weekly),
            url: "https://example.com/a?b=1,2;c"
        )

        let text = ICSSerializer.serialize(event: event)

        #expect(text.contains("\r\nURL:https://example.com/a?b=1,2;c\r\n"))
        let location = text.range(of: "LOCATION:")?.lowerBound
        let url = text.range(of: "URL:")?.lowerBound
        let rrule = text.range(of: "RRULE:")?.lowerBound
        #expect(location != nil && url != nil && rrule != nil)
        #expect(location! < url! && url! < rrule!)
    }

    @Test("a URL can never inject a property line: CR and LF are stripped")
    func urlCannotInjectLines() {
        let event = Event(id: "evt-1", title: "Call", start: DateMath.date(from: "2026-09-20"), url: "https://a.com\r\nX-EVIL:1")

        let text = ICSSerializer.serialize(event: event)

        #expect(!text.contains("\r\nX-EVIL"))
        #expect(text.contains("URL:https://a.comX-EVIL:1"))
    }

    @Test("an event without a URL writes no URL line")
    func noURLNoLine() {
        let text = ICSSerializer.serialize(event: Event(id: "evt-1", title: "Plain", start: DateMath.date(from: "2026-09-20")))
        #expect(!text.contains("URL:"))
    }
```

Append to `ICSParserTests` (inside the suite; use the file's existing `ICSParser.parse` call shape):

```swift
    // MARK: - Event URL

    @Test("reads an event URL, with or without a VALUE=URI parameter, keeping colons inside the value")
    func readsEventURL() {
        func parse(_ line: String) -> Event? {
            let text = [
                "BEGIN:VCALENDAR", "VERSION:2.0",
                "BEGIN:VEVENT", "UID:e", "SUMMARY:Call", "DTSTART:20260920T120000", line, "END:VEVENT",
                "END:VCALENDAR", "",
            ].joined(separator: "\r\n")
            return ICSParser.parse(text).events.first
        }

        #expect(parse("URL:https://example.com/x:y?z=1")?.url == "https://example.com/x:y?z=1")
        #expect(parse("URL;VALUE=URI:https://example.com/x:y")?.url == "https://example.com/x:y")
        #expect(parse("SUMMARY2:nothing")?.url == nil)
    }

    @Test("an event URL survives serialize -> parse -> serialize byte for byte")
    func urlRoundTrip() {
        let event = Event(
            id: "e", title: "Call", start: DateMath.date(from: "2026-09-20"), location: "Room",
            recurrence: RecurrenceRule(frequency: .weekly), url: "https://example.com/a?b=1,2;c"
        )
        let text = ICSSerializer.serialize(events: [event], reminders: [])

        let parsed = ICSParser.parse(text)

        #expect(parsed.events.first?.url == "https://example.com/a?b=1,2;c")
        #expect(ICSSerializer.serialize(events: parsed.events, reminders: parsed.reminders) == text)
    }
```

Append to `EventScheduleTests` (inside the suite), extending the "every other field is preserved" idea to `url`:

```swift
    @Test("scheduling keeps the URL")
    func keepsURL() {
        let event = Event(id: "e", title: "Call", start: at("2026-09-20", 9), url: "https://example.com")

        #expect(event.scheduled(start: at("2026-09-20", 10), end: at("2026-09-20", 11), allDay: false).url == "https://example.com")
        #expect(event.scheduled(start: at("2026-09-20", 10), end: nil, allDay: true).url == "https://example.com")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/repeat-end-url/ios && swift test --filter "RepeatEndTests|ICSSerializerTests|ICSParserTests|EventScheduleTests"`
Expected: FAIL to compile — `RepeatEnd`, `withoutEnd`, `Event.url` not defined.

- [ ] **Step 3: Implement**

Create `ios/Sources/StarkKit/Models/RepeatEnd.swift`:

```swift
// ios/Sources/StarkKit/Models/RepeatEnd.swift
import Foundation

extension RecurrenceRule {
    /// The rule with its end (`count` and `until`) cleared. The add/edit screens keep the end
    /// separately (`RepeatEnd`) because the repeat picker replaces the whole rule.
    public var withoutEnd: RecurrenceRule {
        var copy = self
        copy.count = nil
        copy.until = nil
        return copy
    }
}

/// When a recurring item stops repeating: never, after a date, or after a number of occurrences.
/// Maps onto `RecurrenceRule.until` (date-only, inclusive) and `RecurrenceRule.count`.
public enum RepeatEnd: Equatable, Sendable {
    case never
    case onDate(Date)
    case afterCount(Int)

    /// Reads a rule's end. A count below 1 is nonsense and reads as `.never`; if a rule somehow
    /// has both, the date wins (an RRULE may not carry both).
    public init(rule: RecurrenceRule?) {
        if let until = rule?.until {
            self = .onDate(until)
        } else if let count = rule?.count, count >= 1 {
            self = .afterCount(count)
        } else {
            self = .never
        }
    }

    /// `rule` with this end applied, replacing any earlier end; nil stays nil. An end date is
    /// stored at the start of its day (`UNTIL` is date-only) and a count is at least 1. Applying an
    /// item's own end to its `withoutEnd` rule gives back the original rule exactly.
    public func applied(to rule: RecurrenceRule?) -> RecurrenceRule? {
        guard var result = rule?.withoutEnd else { return nil }
        switch self {
        case .never:
            break
        case .onDate(let date):
            result.until = Calendar(identifier: .gregorian).startOfDay(for: date)
        case .afterCount(let count):
            result.count = max(count, 1)
        }
        return result
    }

    /// An end date earlier than the day the item starts moves up to that day; every other end is
    /// returned unchanged.
    public func clamped(toStartOn start: Date) -> RepeatEnd {
        guard case .onDate(let date) = self else { return self }
        let calendar = Calendar(identifier: .gregorian)
        let startDay = calendar.startOfDay(for: start)
        return calendar.startOfDay(for: date) < startDay ? .onDate(startDay) : self
    }

    /// The Repeat End row's value: "Never", "Dec 31, 2026", "1 time", "10 times".
    public var summary: String {
        switch self {
        case .never:
            return "Never"
        case .onDate(let date):
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        case .afterCount(let count):
            return count == 1 ? "1 time" : "\(count) times"
        }
    }
}
```

In `Event.swift`: add `public var url: String?` after `outcomes`, add the **last** `init` parameter `url: String? = nil` and `self.url = url`.

In `ICSSerializer.serialize(event:)`, directly after the `LOCATION` line and before the `RRULE` line:

```swift
        // A URI value: no TEXT escaping (a comma or semicolon is part of the URL). CR/LF are
        // stripped so a pasted value can never start a new property line.
        if let url = event.url {
            lines.append("URL:\(url.filter { !$0.isNewline })")
        }
```

In `ICSParser.parseEvent`, add `url: props["URL"]` (the property dictionary already handles `URL;VALUE=URI` because it splits the name at the first `;`, and keeps colons in the value because it splits at the first `:`); place it as the last argument matching `Event.init`'s new last parameter.

- [ ] **Step 4: Run to verify pass, then the full suite**

Run: `swift test --filter "RepeatEndTests|ICSSerializerTests|ICSParserTests|EventScheduleTests|ExportFixtureTests"` → PASS (the migration fixtures still round-trip byte for byte); then `swift test` → all pass (304 + 14 = 318; three env-gated tests skipped). If a date/format expectation in a snippet is off (for example the `PositionalDay` initializer shape or the summary date format), fix the snippet minimally, keep the asserted behaviour, and report the correction.

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/repeat-end-url add ios/Sources/StarkKit/Models/RepeatEnd.swift ios/Sources/StarkKit/Models/Event.swift ios/Sources/StarkKit/ICS/ICSSerializer.swift ios/Sources/StarkKit/ICS/ICSParser.swift ios/Tests/StarkKitTests/RepeatEndTests.swift ios/Tests/StarkKitTests/ICSSerializerTests.swift ios/Tests/StarkKitTests/ICSParserTests.swift ios/Tests/StarkKitTests/EventScheduleTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/repeat-end-url commit -m "feat(ios): RepeatEnd, RecurrenceRule.withoutEnd and Event.url with its URL: line (#97)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Add/Edit screens, Repeat End picker, docs

**Files:**
- Create: `ios/App/Stark/Stark/RepeatEndPickerView.swift`
- Modify: `ios/App/Stark/Stark/AddItemView.swift`, `ios/App/Stark/Stark/EditItemView.swift`
- Modify: `CLAUDE.md` (Native iOS App section)

**Interfaces:**
- Consumes (Task 1): `RepeatEnd` (`init(rule:)`, `applied(to:)`, `clamped(toStartOn:)`, `summary`), `RecurrenceRule.withoutEnd`, `Event.url`, `FormFields.trimmedOrNil`. Existing: `RepeatPickerView`, the add/edit screens' `date`/`recurrence` state and `.onChange(of: date)` end-shift.
- No unit tests (SwiftUI wiring; the logic is tested in Task 1). Verify with the app build check plus `swift test`.

- [ ] **Step 1: `RepeatEndPickerView.swift` (new)**

`RepeatEndPickerView(end: Binding<RepeatEnd>, startDate: Date)`: a `List` styled like `RepeatPickerView` (hard edges, `Colors.text`, an accent checkmark on the selected row), title "Repeat End", three rows:
- **Never** — sets `end = .never`.
- **On Date** — sets `end = .onDate(<current end date, or the start's day if none>)`; when selected, the row (or one directly below it) shows a `DatePicker("Ends", selection:, in: startDay..., displayedComponents: .date)` bound to the end date (`startDay` = the start date's start of day); each change stores `.onDate(date)` (the value is normalised on save by `RepeatEnd.applied`).
- **After N Times** — sets `end = .afterCount(<current count, or 10 if none>)`; when selected, a `Stepper` (range 1...999, label showing "N time(s)" via `RepeatEnd.afterCount(n).summary`) bound to the count.
The selected row is the one matching the current case. Only `Colors.*`/`Spacing.*`/`Fonts.mono`; no rounded shapes.

- [ ] **Step 2: `AddItemView.swift`**

1. State: `@State private var repeatEnd: RepeatEnd = .never`, `@State private var url = ""`.
2. Below the Repeat `NavigationLink`, only while `recurrence != nil`: a `NavigationLink` to `RepeatEndPickerView(end: $repeatEnd, startDate: date)` whose label is "Repeat End" with `repeatEnd.summary` (secondary colour) on the right, in the same style as the Repeat row.
3. `.onChange(of: recurrence)`: when it becomes nil, `repeatEnd = .never`. In the existing `.onChange(of: date)`, also `repeatEnd = repeatEnd.clamped(toStartOn: newValue)` (an end date never precedes the start's day).
4. Events only: below Location, a `TextField("URL", text: $url)` with `.keyboardType(.URL)`, `.textInputAutocapitalization(.never)`, `.autocorrectionDisabled()`.
5. `add()`: pass `recurrence: repeatEnd.applied(to: recurrence)` for both kinds, and `url: FormFields.trimmedOrNil(url)` for events.

- [ ] **Step 3: `EditItemView.swift`**

1. State: `@State private var repeatEnd: RepeatEnd`, `@State private var url: String`. In `init(item:)`: `_recurrence = State(initialValue: startRecurrence?.withoutEnd)`, `_repeatEnd = State(initialValue: RepeatEnd(rule: startRecurrence))`, and `url` = the event's URL or "" (reminders: "").
2. The same Repeat End row (only while `recurrence != nil`), the same `.onChange` rules for `recurrence` (reset to `.never` when nil) and `date` (clamp), and the same events-only URL field with the same keyboard settings.
3. `save()`: both branches set `updated.recurrence = repeatEnd.applied(to: recurrence)`; the event branch also sets `updated.url = FormFields.trimmedOrNil(url)`. Opening an item and saving it unchanged must leave its rule and URL as they were (the Task 1 round-trip test covers the rule).
4. Events: an **Open Link** button in the actions section, shown when the trimmed URL parses with `URL(string:)` to a URL whose scheme is `http` or `https`; it calls `@Environment(\.openURL)` (styled `Colors.accent` like the other actions; it does not dismiss).
5. Update the file's header doc comment: editable fields now also include Repeat End and (events) URL.

- [ ] **Step 4: Docs**

In `CLAUDE.md`, Native iOS App section, add one paragraph after the "Week / month / year modes" paragraph:

> **Repeat End and event URL** (`RepeatEnd`, `RecurrenceRule.withoutEnd`, `Event.url`, `RepeatEndPickerView`; issue #97): a **Repeat End** row (Never / On Date / After N Times) appears under Repeat on add and edit, for events and reminders, only while Repeat is not Never. It maps onto `RecurrenceRule.until` (stored date-only at the start of its day, inclusive) and `count` (at least 1), which the `.ics` codec and `OccurrenceExpander` already honoured. **The screens hold the end as separate state** (`RepeatEnd`) and keep `recurrence` stripped of it (`withoutEnd`), applying it on save (`applied(to:)`), because `RepeatPickerView`'s presets replace the whole rule (which would wipe an end) and its checkmark compares whole rules; opening an item and saving it unchanged leaves its rule identical (pinned by `RepeatEndTests.unchangedRoundTrip`). Choosing Repeat = Never resets the end; an end date earlier than the start's day moves up to it (`clamped(toStartOn:)`). **Events have a URL** (`Event.url`, a plain unescaped `URL:` line after `LOCATION` and before `RRULE`, CR/LF stripped so a pasted value cannot inject a property line; no line when blank, so existing files and the migration fixtures are byte-identical); the edit sheet shows **Open Link** for an `http`/`https` URL. Reminders have no URL. Alerts, time zones and calendars are deliberately not built.

- [ ] **Step 5: Verify**

App build check → `** BUILD SUCCEEDED **`, no new warnings from the edited files; `swift test` from `ios/` → all pass (318).

- [ ] **Step 6: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/repeat-end-url add ios/App/Stark/Stark/RepeatEndPickerView.swift ios/App/Stark/Stark/AddItemView.swift ios/App/Stark/Stark/EditItemView.swift CLAUDE.md
git -C /Users/eladio/src/todo-txt/.claude/worktrees/repeat-end-url commit -m "feat(ios): Repeat End picker and an event URL on the add and edit screens (#97)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
