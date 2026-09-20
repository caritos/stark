# Event Attendance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user mark each occurrence of an event in the native iOS app as attended or skipped, persist it in the event's `.ics` file, and show it in the agenda.

**Architecture:** `Event` gains an `outcomes` list of (occurrence day, attended|skipped) records, serialized as `X-STARK-ATTENDED` / `X-STARK-SKIPPED` lines after `EXDATE`. `PlannerStore.setEventOutcome` edits it in place in whichever file holds the event. `AgendaItem.outcome` derives the state per occurrence; the row and the detail sheet render and edit it.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM package `StarkKit` tested with Swift Testing (`import Testing`, `@Test`, `#expect`; never XCTest).

**Spec:** `docs/superpowers/specs/2026-09-21-event-attendance-design.md`

## Global Constraints

- **Working directory:** `/Users/eladio/src/todo-txt/.claude/worktrees/event-attendance` (a git worktree, branch `worktree-event-attendance`). Use absolute paths; run Swift tests from its `ios/` directory (`swift test`).
- **Shell:** compound commands and heredocs may be rejected. Use plain single commands, the Write/Edit tools for files, `git -C <worktree>` and multiple `-m` flags for commits.
- **Commits:** stage specific paths only (never `git add -A`, `.` or `commit -a`). End every commit message with a separate `-m` paragraph: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Never push.
- **Logic goes in StarkKit, views are thin.** If it can be tested, it lives in `ios/Sources/StarkKit` with a Swift Testing test.
- **Tests first:** write the failing test, run it and see it fail for the stated reason, then implement.
- **Baseline:** `swift test` currently passes 221 tests. It must stay green after every task.
- **Day matching:** an occurrence matches a record by calendar day (`Calendar(identifier: .gregorian).isDate(_:inSameDayAs:)`), the same convention as `exceptionDates`.
- **Theme:** only `Colors.*`, `Spacing.*`, `Fonts.mono` from `Theme.swift`; no hardcoded hex, no new colours, no rounded corners.
- **Do not touch the author's phone** (no `xcrun devicectl`, no `deploy.sh`); the controller does the on-device check.
- **`Event`'s `Codable` conformance** is synthesized and nothing persists it (only `.ics`), so adding a stored property is safe.

---

### Task 1: Model + `.ics` round trip

**Files:**
- Modify: `ios/Sources/StarkKit/Models/Event.swift`
- Modify: `ios/Sources/StarkKit/ICS/ICSSerializer.swift`
- Modify: `ios/Sources/StarkKit/ICS/ICSParser.swift`
- Test: `ios/Tests/StarkKitTests/ICSSerializerTests.swift` (append inside the suite)
- Test: `ios/Tests/StarkKitTests/ICSParserTests.swift` (append inside the suite)

**Interfaces:**
- Produces (used by Tasks 2-4):
  - `public enum EventOutcome: String, Equatable, Codable, Sendable { case attended, skipped }`
  - `public struct EventOutcomeRecord: Equatable, Codable, Sendable { public var date: Date; public var outcome: EventOutcome; public init(date: Date, outcome: EventOutcome) }`
  - `Event.outcomes: [EventOutcomeRecord]`, a new **last** `init` parameter `outcomes: [EventOutcomeRecord] = []`.

- [ ] **Step 1: Write the failing serializer tests**

Append to `ICSSerializerTests` (before the suite's closing `}`):

```swift
    // MARK: - Event outcomes

    @Test("serializes attended and skipped marks after EXDATE, in order, byte for byte")
    func serializesEventOutcomes() {
        let event = Event(
            id: "evt-1",
            title: "Class",
            start: DateMath.date(from: "2026-09-20"),
            exceptionDates: [DateMath.date(from: "2026-10-04")],
            outcomes: [
                EventOutcomeRecord(date: DateMath.date(from: "2026-09-20"), outcome: .attended),
                EventOutcomeRecord(date: DateMath.date(from: "2026-09-27"), outcome: .skipped),
            ]
        )

        let text = ICSSerializer.serialize(event: event)

        #expect(text == [
            "BEGIN:VEVENT",
            "UID:evt-1",
            "SUMMARY:Class",
            "DTSTART:20260920T120000",
            "EXDATE:20261004T120000",
            "X-STARK-ATTENDED:20260920T120000",
            "X-STARK-SKIPPED:20260927T120000",
            "END:VEVENT",
        ].joined(separator: "\r\n"))
    }

    @Test("an all-day event's marks use VALUE=DATE like its EXDATE lines")
    func serializesAllDayEventOutcome() {
        let event = Event(
            id: "evt-2",
            title: "Trip",
            start: DateMath.date(from: "2026-09-21"),
            isAllDay: true,
            outcomes: [EventOutcomeRecord(date: DateMath.date(from: "2026-09-21"), outcome: .skipped)]
        )

        let text = ICSSerializer.serialize(event: event)

        #expect(text.contains("X-STARK-SKIPPED;VALUE=DATE:20260921"))
    }

    @Test("an event with no marks writes no X-STARK lines")
    func noOutcomesNoLines() {
        let text = ICSSerializer.serialize(event: Event(id: "evt-3", title: "Plain", start: DateMath.date(from: "2026-09-20")))
        #expect(!text.contains("X-STARK"))
    }
```

- [ ] **Step 2: Write the failing parser tests**

Append to `ICSParserTests` (before the suite's closing `}`; check the file's existing tests for how they call the parser and use the same call — it is `ICSParser.parse(_:)` returning `.events` / `.reminders`):

```swift
    // MARK: - Event outcomes

    @Test("marks survive serialize -> parse -> serialize byte for byte, timed and all-day")
    func outcomesRoundTrip() {
        let timed = Event(
            id: "evt-1",
            title: "Class",
            start: DateMath.date(from: "2026-09-20"),
            recurrence: RecurrenceRule(frequency: .weekly),
            exceptionDates: [DateMath.date(from: "2026-10-04")],
            outcomes: [
                EventOutcomeRecord(date: DateMath.date(from: "2026-09-20"), outcome: .attended),
                EventOutcomeRecord(date: DateMath.date(from: "2026-09-27"), outcome: .skipped),
            ]
        )
        let allDay = Event(
            id: "evt-2",
            title: "Trip",
            start: DateMath.date(from: "2026-09-21"),
            isAllDay: true,
            outcomes: [EventOutcomeRecord(date: DateMath.date(from: "2026-09-21"), outcome: .skipped)]
        )
        let text = ICSSerializer.serialize(events: [timed, allDay], reminders: [])

        let parsed = ICSParser.parse(text)

        #expect(parsed.events.count == 2)
        #expect(parsed.events[0].outcomes == timed.outcomes)
        #expect(parsed.events[1].outcomes.map(\.outcome) == [.skipped])
        #expect(ICSSerializer.serialize(events: parsed.events, reminders: parsed.reminders) == text)
    }

    @Test("unparseable dates and unknown X-STARK outcome names are ignored")
    func garbledOutcomesIgnored() {
        let text = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "BEGIN:VEVENT",
            "UID:evt-1",
            "SUMMARY:Class",
            "DTSTART:20260920T120000",
            "X-STARK-ATTENDED:notadate",
            "X-STARK-MAYBE:20260920T120000",
            "X-STARK-SKIPPED:20260921T120000",
            "END:VEVENT",
            "END:VCALENDAR",
            "",
        ].joined(separator: "\r\n")

        let parsed = ICSParser.parse(text)

        #expect(parsed.events.count == 1)
        #expect(parsed.events[0].outcomes.map(\.outcome) == [.skipped])
    }
```

- [ ] **Step 3: Run to verify failure**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/event-attendance/ios && swift test --filter "ICSSerializer|ICSParser"`
Expected: FAIL to compile — `EventOutcomeRecord` / `outcomes` not defined.

- [ ] **Step 4: Implement the model**

In `ios/Sources/StarkKit/Models/Event.swift`, add above `public struct Event`:

```swift
/// What the user did about one occurrence of an event.
public enum EventOutcome: String, Equatable, Codable, Sendable {
    case attended
    case skipped
}

/// One recorded outcome. `date` is the occurrence's start; records are matched to occurrences by
/// calendar day (like `exceptionDates`), so a later change of time-of-day keeps the mark.
public struct EventOutcomeRecord: Equatable, Codable, Sendable {
    public var date: Date
    public var outcome: EventOutcome

    public init(date: Date, outcome: EventOutcome) {
        self.date = date
        self.outcome = outcome
    }
}
```

In `Event`: add `public var outcomes: [EventOutcomeRecord]` after `exceptionDates`; add the last init parameter `outcomes: [EventOutcomeRecord] = []` and `self.outcomes = outcomes` in the initializer body.

- [ ] **Step 5: Implement serializer and parser**

In `ICSSerializer.serialize(event:)`, directly after the `for exdate in event.exceptionDates { … }` loop and before `lines.append("END:VEVENT")`:

```swift
        for record in event.outcomes {
            let name = record.outcome == .attended ? "X-STARK-ATTENDED" : "X-STARK-SKIPPED"
            lines.append("\(name)\(dateParam(event.isAllDay)):\(ICSDateFormat.format(record.date, allDay: event.isAllDay))")
        }
```

In `ICSParser`, add next to `exceptionDates(_:)`:

```swift
    /// `X-STARK-ATTENDED` / `X-STARK-SKIPPED` lines in file order, so parse -> serialize is
    /// byte-stable. Unparseable dates and unknown `X-STARK-*` names are ignored.
    private static func outcomes(_ block: [String]) -> [EventOutcomeRecord] {
        block.compactMap { line -> EventOutcomeRecord? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[line.startIndex..<colon].split(separator: ";").first.map(String.init) ?? ""
            let outcome: EventOutcome
            switch name {
            case "X-STARK-ATTENDED": outcome = .attended
            case "X-STARK-SKIPPED": outcome = .skipped
            default: return nil
            }
            guard let date = ICSDateFormat.parse(String(line[line.index(after: colon)...]))?.date else { return nil }
            return EventOutcomeRecord(date: date, outcome: outcome)
        }
    }
```

and in `parseEvent`, add `outcomes: outcomes(block)` after `exceptionDates: exceptionDates(block)` (with a comma on the previous line).

- [ ] **Step 6: Run to verify pass, then the full suite**

Run: `swift test --filter "ICSSerializer|ICSParser"` → PASS. Then `swift test` → all pass (221 + 5 new = 226).

If the byte-for-byte test fails only because `RecurrenceRule(frequency: .weekly)` encodes differently than expected, that is not part of the assertion (the round trip compares serializer output to itself); if the exact-bytes test's `DTSTART` differs from `20260920T120000`, `DateMath.date(from:)` is not noon — stop and report instead of editing the expectation.

- [ ] **Step 7: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/event-attendance add ios/Sources/StarkKit/Models/Event.swift ios/Sources/StarkKit/ICS/ICSSerializer.swift ios/Sources/StarkKit/ICS/ICSParser.swift ios/Tests/StarkKitTests/ICSSerializerTests.swift ios/Tests/StarkKitTests/ICSParserTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/event-attendance commit -m "feat(ios): event outcomes model and X-STARK-ATTENDED/SKIPPED ics lines" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `PlannerStore.setEventOutcome`

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/PlannerStore.swift` (add the method directly after `skipEvent(id:on:)`)
- Test: `ios/Tests/StarkKitTests/PlannerStoreTests.swift` (append inside the suite, after the skipEvent/skipReminder tests, before the suite's closing `}`)

**Interfaces:**
- Consumes: `EventOutcome`, `EventOutcomeRecord`, `Event.outcomes` (Task 1); the store's existing `recurringEvents`, `monthEvents`, `loadedMonths`, `persistRecurring()`, `persistMonth(_:)`, `rebuild()`.
- Produces: `public func setEventOutcome(id: String, on date: Date, outcome: EventOutcome?)` (used by Task 4).

- [ ] **Step 1: Write the failing tests**

Append to `PlannerStoreTests` (uses the suite's existing `makeStore()`, `start(_:around:)`, `Self.anchor`, `septRange`, `isoDays`):

```swift
    // MARK: - setEventOutcome

    @Test("setEventOutcome marks a one-off event, writes it to its month file, and survives a reload")
    @MainActor
    func setEventOutcomeOnOneOff() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-1", title: "Dinner", start: DateMath.date(from: "2026-09-17")))

        store.setEventOutcome(id: "evt-1", on: DateMath.date(from: "2026-09-17"), outcome: .attended)

        let live = try #require(store.events.first { $0.id == "evt-1" })
        #expect(live.outcomes == [EventOutcomeRecord(date: DateMath.date(from: "2026-09-17"), outcome: .attended)])
        let onDisk = try #require(try file.loadMonth(YearMonth(year: 2026, month0: 8)).events.first)
        #expect(onDisk.outcomes.map(\.outcome) == [.attended])
        let reloaded = PlannerStore(file: file)
        start(reloaded, around: Self.anchor)
        let persisted = try #require(reloaded.events.first { $0.id == "evt-1" })
        #expect(persisted.outcomes.map(\.outcome) == [.attended])
    }

    @Test("setEventOutcome marks single occurrences of a recurring event in recurring.ics without exdating them")
    @MainActor
    func setEventOutcomeOnRecurring() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-rec", title: "Weekly", start: DateMath.date(from: "2026-09-03"), recurrence: RecurrenceRule(frequency: .weekly)))

        store.setEventOutcome(id: "evt-rec", on: DateMath.date(from: "2026-09-10"), outcome: .skipped)
        store.setEventOutcome(id: "evt-rec", on: DateMath.date(from: "2026-09-17"), outcome: .attended)

        let onDisk = try #require(try file.loadRecurring().events.first { $0.id == "evt-rec" })
        #expect(onDisk.outcomes.map(\.outcome) == [.skipped, .attended])
        #expect(onDisk.exceptionDates.isEmpty)
        #expect(isoDays(OccurrenceExpander.expand(event: onDisk, in: septRange)) == ["2026-09-03", "2026-09-10", "2026-09-17", "2026-09-24"])
    }

    @Test("setEventOutcome replaces the mark for that day and nil clears it")
    @MainActor
    func setEventOutcomeReplacesAndClears() throws {
        let (store, file, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-1", title: "Dinner", start: DateMath.date(from: "2026-09-17")))
        let day = DateMath.date(from: "2026-09-17")

        store.setEventOutcome(id: "evt-1", on: day, outcome: .attended)
        store.setEventOutcome(id: "evt-1", on: day, outcome: .skipped)
        #expect(try #require(store.events.first).outcomes == [EventOutcomeRecord(date: day, outcome: .skipped)])

        store.setEventOutcome(id: "evt-1", on: day, outcome: nil)
        #expect(try #require(store.events.first).outcomes.isEmpty)
        let onDisk = try #require(try file.loadMonth(YearMonth(year: 2026, month0: 8)).events.first)
        #expect(onDisk.outcomes.isEmpty)

        store.setEventOutcome(id: "evt-1", on: day, outcome: nil)
        #expect(try #require(store.events.first).outcomes.isEmpty)
    }

    @Test("setEventOutcome is idempotent: the same state twice leaves one record")
    @MainActor
    func setEventOutcomeIsIdempotent() throws {
        let (store, _, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-1", title: "Dinner", start: DateMath.date(from: "2026-09-17")))
        let day = DateMath.date(from: "2026-09-17")

        store.setEventOutcome(id: "evt-1", on: day, outcome: .attended)
        let once = try #require(store.events.first)
        store.setEventOutcome(id: "evt-1", on: day, outcome: .attended)

        #expect(try #require(store.events.first) == once)
        #expect(once.outcomes.count == 1)
    }

    @Test("setEventOutcome matches by calendar day, not by exact time")
    @MainActor
    func setEventOutcomeMatchesByDay() throws {
        let (store, _, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-1", title: "Dinner", start: DateMath.date(from: "2026-09-17")))
        let noon = DateMath.date(from: "2026-09-17")
        let midnight = Calendar(identifier: .gregorian).startOfDay(for: noon)

        store.setEventOutcome(id: "evt-1", on: noon, outcome: .attended)
        store.setEventOutcome(id: "evt-1", on: midnight, outcome: .skipped)

        let outcomes = try #require(store.events.first).outcomes
        #expect(outcomes.count == 1)
        #expect(outcomes[0].outcome == .skipped)
    }

    @Test("setEventOutcome ignores an unknown id and leaves other events alone")
    @MainActor
    func setEventOutcomeUnknownId() throws {
        let (store, _, _) = makeStore()
        start(store, around: Self.anchor)
        store.addEvent(Event(id: "evt-1", title: "Dinner", start: DateMath.date(from: "2026-09-17")))
        let before = store.events

        store.setEventOutcome(id: "nope", on: DateMath.date(from: "2026-09-17"), outcome: .attended)

        #expect(store.events == before)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PlannerStore`
Expected: FAIL to compile — `setEventOutcome` not defined.

- [ ] **Step 3: Implement**

In `PlannerStore.swift`, directly after `skipEvent(id:on:)`:

```swift
    /// Records that the user attended or skipped one occurrence of an event, or clears the record
    /// (`outcome == nil`). The mark lives on the event itself (in `recurring.ics` for a series, in
    /// its month file for a one-off), so no copy is created and nothing is exdated: the occurrence
    /// stays in the agenda. Matched by calendar day. Idempotent: no-op (nothing written) for an
    /// unknown id, when that day already has this outcome, and when clearing an unmarked day.
    public func setEventOutcome(id: String, on date: Date, outcome: EventOutcome?) {
        let calendar = Calendar(identifier: .gregorian)

        func updated(_ event: Event) -> Event? {
            let existing = event.outcomes.first { calendar.isDate($0.date, inSameDayAs: date) }
            guard existing?.outcome != outcome else { return nil }
            var copy = event
            copy.outcomes.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
            if let outcome { copy.outcomes.append(EventOutcomeRecord(date: date, outcome: outcome)) }
            copy.outcomes.sort { $0.date < $1.date }
            return copy
        }

        if let index = recurringEvents.firstIndex(where: { $0.id == id }) {
            guard let copy = updated(recurringEvents[index]) else { return }
            recurringEvents[index] = copy
            persistRecurring()
            rebuild()
            return
        }
        for month in loadedMonths {
            guard let index = monthEvents[month]?.firstIndex(where: { $0.id == id }),
                  let source = monthEvents[month]?[index] else { continue }
            guard let copy = updated(source) else { return }
            monthEvents[month]?[index] = copy
            persistMonth(month)
            rebuild()
            return
        }
    }
```

If a private name differs from the above (e.g. the month dictionary), read `skipEvent`/`completeReminder` in the same file and use the names they use.

- [ ] **Step 4: Run to verify pass, then the full suite**

Run: `swift test --filter PlannerStore` → PASS; `swift test` → all pass (232 total).

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/event-attendance add ios/Sources/StarkKit/Planner/PlannerStore.swift ios/Tests/StarkKitTests/PlannerStoreTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/event-attendance commit -m "feat(ios): PlannerStore.setEventOutcome marks an event occurrence attended or skipped" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `AgendaItem.outcome` + `EventOutcomeActions`

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/AgendaBuilder.swift` (add `outcome` to `AgendaItem`)
- Create: `ios/Sources/StarkKit/Planner/EventOutcomeActions.swift`
- Test: `ios/Tests/StarkKitTests/AgendaBuilderTests.swift` (append inside the suite, before the closing `}`)
- Create test: `ios/Tests/StarkKitTests/EventOutcomeActionsTests.swift`

**Interfaces:**
- Consumes: `Event.outcomes`, `EventOutcome` (Task 1).
- Produces (used by Task 4):
  - `AgendaItem.outcome: EventOutcome?` (computed; `nil` for reminders and for unmarked/orphaned occurrences)
  - `public struct EventOutcomeActions: Equatable` with `init(outcome: EventOutcome?, isRecurring: Bool)` and Bool properties `showsAttended`, `showsDidntAttend`, `showsClear`, `showsRemoveOccurrence`.

- [ ] **Step 1: Write the failing agenda tests**

Append to `AgendaBuilderTests` (uses the suite's `build`, `d`, `iso` helpers; display range around 2026-09-20 is 2026-09-06 … 2026-11-19):

```swift
    // MARK: - Event outcome

    @Test("an event occurrence reports the outcome recorded for its own day only")
    func outcomePerOccurrence() {
        let event = Event(
            id: "e1",
            title: "Class",
            start: d("2026-09-25"),
            recurrence: RecurrenceRule(frequency: .weekly),
            outcomes: [
                EventOutcomeRecord(date: d("2026-10-02"), outcome: .attended),
                EventOutcomeRecord(date: d("2026-10-09"), outcome: .skipped),
            ]
        )

        let items = Array(build(events: [event]).prefix(4))

        #expect(items.map { iso($0.occurrence) } == ["2026-09-25", "2026-10-02", "2026-10-09", "2026-10-16"])
        #expect(items.map(\.outcome) == [nil, .attended, .skipped, nil])
    }

    @Test("a record for a day the event no longer occurs on matches nothing")
    func orphanedOutcomeIsIgnored() {
        let event = Event(
            id: "e1",
            title: "Dinner",
            start: d("2026-09-25"),
            outcomes: [EventOutcomeRecord(date: d("2026-09-26"), outcome: .attended)]
        )

        #expect(build(events: [event])[0].outcome == nil)
    }

    @Test("reminders never have an outcome")
    func reminderHasNoOutcome() {
        let reminder = Reminder(id: "r1", title: "Pay rent", dueDate: d("2026-09-27"))

        #expect(build(reminders: [reminder])[0].outcome == nil)
    }
```

- [ ] **Step 2: Write the failing actions tests**

Create `ios/Tests/StarkKitTests/EventOutcomeActionsTests.swift`:

```swift
// ios/Tests/StarkKitTests/EventOutcomeActionsTests.swift
import Testing
@testable import StarkKit

@Suite("EventOutcomeActions")
struct EventOutcomeActionsTests {
    @Test("an unmarked event offers both marks and no Clear")
    func unmarked() {
        let actions = EventOutcomeActions(outcome: nil, isRecurring: false)
        #expect(actions.showsAttended)
        #expect(actions.showsDidntAttend)
        #expect(!actions.showsClear)
    }

    @Test("an attended event hides Attended and offers Didn't Attend and Clear")
    func attended() {
        let actions = EventOutcomeActions(outcome: .attended, isRecurring: false)
        #expect(!actions.showsAttended)
        #expect(actions.showsDidntAttend)
        #expect(actions.showsClear)
    }

    @Test("a skipped event hides Didn't Attend and offers Attended and Clear")
    func skipped() {
        let actions = EventOutcomeActions(outcome: .skipped, isRecurring: false)
        #expect(actions.showsAttended)
        #expect(!actions.showsDidntAttend)
        #expect(actions.showsClear)
    }

    @Test("Remove This Occurrence is offered only for recurring events")
    func removeOccurrenceOnlyWhenRecurring() {
        #expect(EventOutcomeActions(outcome: nil, isRecurring: true).showsRemoveOccurrence)
        #expect(EventOutcomeActions(outcome: .attended, isRecurring: true).showsRemoveOccurrence)
        #expect(!EventOutcomeActions(outcome: nil, isRecurring: false).showsRemoveOccurrence)
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter "AgendaBuilder|EventOutcomeActions"`
Expected: FAIL to compile — `outcome` / `EventOutcomeActions` not defined.

- [ ] **Step 4: Implement**

In `AgendaBuilder.swift`, inside `AgendaItem`, after `isRecurring`:

```swift
    /// Events only: what the user recorded for *this* occurrence (matched by calendar day), or nil
    /// when nothing is recorded. Always nil for reminders. Derived, so it can never disagree with
    /// the event it came from.
    public var outcome: EventOutcome? {
        guard case .event(let event) = kind else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        return event.outcomes.first { calendar.isDate($0.date, inSameDayAs: occurrence) }?.outcome
    }
```

Create `ios/Sources/StarkKit/Planner/EventOutcomeActions.swift`:

```swift
// ios/Sources/StarkKit/Planner/EventOutcomeActions.swift

/// Which action buttons the event detail sheet shows, given the occurrence's current outcome.
/// Kept out of the view so it is testable.
public struct EventOutcomeActions: Equatable {
    public let showsAttended: Bool
    public let showsDidntAttend: Bool
    public let showsClear: Bool
    /// Drops this one occurrence from a recurring series (an exception date). A different action
    /// from "Didn't Attend", which keeps the occurrence visible.
    public let showsRemoveOccurrence: Bool

    public init(outcome: EventOutcome?, isRecurring: Bool) {
        showsAttended = outcome != .attended
        showsDidntAttend = outcome != .skipped
        showsClear = outcome != nil
        showsRemoveOccurrence = isRecurring
    }
}
```

- [ ] **Step 5: Run to verify pass, then the full suite**

Run: `swift test --filter "AgendaBuilder|EventOutcomeActions"` → PASS; `swift test` → all pass (239 total).

- [ ] **Step 6: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/event-attendance add ios/Sources/StarkKit/Planner/AgendaBuilder.swift ios/Sources/StarkKit/Planner/EventOutcomeActions.swift ios/Tests/StarkKitTests/AgendaBuilderTests.swift ios/Tests/StarkKitTests/EventOutcomeActionsTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/event-attendance commit -m "feat(ios): AgendaItem.outcome and the event detail sheet's EventOutcomeActions" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: App UI (row marker, detail sheet) + docs

**Files:**
- Modify: `ios/App/Stark/Stark/AgendaRow.swift`
- Modify: `ios/App/Stark/Stark/EditItemView.swift`
- Modify: `CLAUDE.md` (Native iOS App section)

**Interfaces:**
- Consumes: `AgendaItem.outcome` (Task 3), `EventOutcomeActions` (Task 3), `PlannerStore.setEventOutcome(id:on:outcome:)` (Task 2).
- No unit tests: these are visuals and a thin action wiring; the logic is already tested in Tasks 1-3. Verification is a clean build plus the controller's on-device check.

- [ ] **Step 1: Row marker and title (`AgendaRow.swift`)**

In `AgendaRowView`:

1. Add `private var isSkipped: Bool { item.outcome == .skipped }` next to `looksDone`.
2. Title: change to `.strikethrough(looksDone || isSkipped)` and `.foregroundStyle(looksDone || isSkipped ? Colors.textSecondary : Colors.text)`.
3. Replace the `.event:` case of `marker` with a switch on `item.outcome`:
   - `nil`: unchanged (`Rectangle().fill(Colors.accent).frame(width: 8, height: 8)`).
   - `.attended`: the same filled-accent-square-with-background-colour-`checkmark` view the completed reminder uses (extract that view into a private `checkedMarker` computed property and use it for both, rather than duplicating).
   - `.skipped`: `Rectangle().strokeBorder(Colors.checkboxBorder, lineWidth: 1.5)` with an overlay `Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Colors.textSecondary)`.
4. `accessibilitySummary`: after the existing `if looksDone { parts.append("completed") }`, add `if item.outcome == .attended { parts.append("attended") } else if item.outcome == .skipped { parts.append("didn't attend") }`.
5. Update the doc comment at the top of the file only if it now says events' markers are always the plain small square.

Do not touch `AgendaRowTargets` (events stay a single details button).

- [ ] **Step 2: Detail sheet (`EditItemView.swift`)**

1. Add `private var eventActions: EventOutcomeActions? { guard case .event = item.kind else { return nil }; return EventOutcomeActions(outcome: item.outcome, isRecurring: item.isRecurring) }`.
2. In the actions `Section`, before the existing Done/Undo/Skip buttons, for events only:

```swift
                    if let actions = eventActions {
                        if actions.showsAttended {
                            Button("Attended") { markOutcome(.attended) }.foregroundStyle(Colors.accent)
                        }
                        if actions.showsDidntAttend {
                            Button("Didn't Attend") { markOutcome(.skipped) }.foregroundStyle(Colors.accent)
                        }
                        if actions.showsClear {
                            Button("Clear") { markOutcome(nil) }.foregroundStyle(Colors.accent)
                        }
                        if actions.showsRemoveOccurrence {
                            Button("Remove This Occurrence") { skipOccurrence() }.foregroundStyle(Colors.accent)
                        }
                    }
```

3. The existing `if showsSkip { Button("Skip This Occurrence") … }` must now apply to **reminders only**: change `showsSkip` to `if case .reminder = item.kind { return item.isRecurring && !item.isCompleted }; return false`. `skipOccurrence()` keeps handling both kinds (events still call `store.skipEvent`).
4. Add the action:

```swift
    private func markOutcome(_ outcome: EventOutcome?) {
        guard case .event(let event) = item.kind else { return }
        store.setEventOutcome(id: event.id, on: item.occurrence, outcome: outcome)
        dismiss()
    }
```

Order in the section for an event: Attended, Didn't Attend, Clear, Remove This Occurrence, Delete. Reminders' section is unchanged.

- [ ] **Step 3: Build**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/event-attendance/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -15`
Expected: `** BUILD SUCCEEDED **`. Then `cd ../.. && swift test` (from `ios/`) → all 239 pass.

- [ ] **Step 4: Docs**

In `CLAUDE.md`, Native iOS App section, add one paragraph after the "Checkbox: 2.5 s undo window" paragraph:

> **Event attendance** (`Event.outcomes`, `PlannerStore.setEventOutcome`, `AgendaItem.outcome`, `EventOutcomeActions`): the user can mark each occurrence of an event *attended* or *skipped* from the detail sheet ("Attended" / "Didn't Attend" / "Clear"); the row shows a ✓ marker (attended) or a ✗ marker with a dimmed, struck-through title (skipped). The mark is stored on the event itself as one `X-STARK-ATTENDED:` / `X-STARK-SKIPPED:` line per occurrence (after the `EXDATE` lines; `;VALUE=DATE` for all-day events), in `recurring.ics` for a series and the month file for a one-off, so it never creates a copy and never removes the occurrence. Records are matched to occurrences by **calendar day** (like `exceptionDates`), so editing a time of day keeps them, while moving an event's start day orphans the old marks (harmless, not migrated). This is deliberately not the same as **"Remove This Occurrence"** (recurring events only, formerly "Skip This Occurrence"), which adds an exception date and makes the occurrence disappear. Reminders keep "Skip This Occurrence". The TypeScript converter never emits these lines (todo.txt has no equivalent).

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/event-attendance add ios/App/Stark/Stark/AgendaRow.swift ios/App/Stark/Stark/EditItemView.swift CLAUDE.md
git -C /Users/eladio/src/todo-txt/.claude/worktrees/event-attendance commit -m "feat(ios): show and set event attendance in the agenda row and detail sheet" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
