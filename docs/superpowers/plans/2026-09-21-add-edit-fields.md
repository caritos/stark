# Add/Edit Fields (All day, Notes, Location, Priority) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the native iOS app's add and edit screens the fields the user liked in Fantastical's task sheet: an **All day** toggle (reminders and events), **Notes** (reminders and events), **Location** (events), and a three-level **Priority** picker (reminders), with priority shown as `!` marks on the agenda row.

**Architecture:** All decisions that can be tested live in small pure `StarkKit` types (`ReminderPriority`, `FormFields`, `Event.rescheduled(to:allDay:)`, `AgendaItem.priority`); the SwiftUI screens only bind state to them. No data-model or `.ics` format change: `Reminder.notes/priority`, `Event.notes/location/isAllDay` and their `.ics` lines already exist.

**Tech Stack:** Swift 6 / SwiftUI, SwiftPM package `StarkKit` tested with Swift Testing (`import Testing`, `@Test`, `#expect`; never XCTest).

**Design (approved in conversation 2026-09-21, bounded change — no separate spec):**
- **All day** toggle under the date on add and edit, for both kinds. On = date-only: the date picker shows the date only, the item is stored at start of day (the model already treats midnight as "date only" for reminders; events set `isAllDay`, written as `;VALUE=DATE`). Off = date and time as today. Existing items start with the toggle set from their data (`event.isAllDay`; reminder due date at exactly midnight). The stored date/time state is not mutated by the toggle, only normalised on save, so toggling on then off restores the time that was picked. A timed event turned all-day loses its `end`; all-day turned timed has no `end`; an unchanged all-day multi-day event keeps its (shifted) `end`.
- **Notes**: multi-line field on add and edit for reminders and events; blank text is saved as no note. **Location**: events only, same blank rule.
- **Priority**: reminders only (events never carry a priority — same product rule as the Expo app). Picker None / `!` / `!!` / `!!!`, mapped like Apple Reminders: `!` low = `PRIORITY:9`, `!!` medium = 5, `!!!` high = 1, None writes no line. An existing value maps to the nearest level for display (1-4 high, 5 medium, 6-9 low, anything else none) and is rewritten only if the user changes the level. The row shows the marks in the accent colour before the title of an incomplete reminder (a prefix survives truncation). Sort order is unchanged.
- **Out of scope:** undated reminders, lists, location-based reminders, natural-language quick add, sorting by priority, an Expo-app change, the TypeScript converter.

## Global Constraints

- **Working directory:** `/Users/eladio/src/todo-txt/.claude/worktrees/add-edit-fields` (a git worktree, branch `worktree-add-edit-fields`). Use absolute paths; run Swift tests from its `ios/` directory (`swift test`).
- **Shell:** compound commands and heredocs may be rejected. Use plain single commands, the Write/Edit tools for files, `git -C <worktree>` and multiple `-m` flags for commits.
- **Commits:** stage specific paths only (never `git add -A`, `.` or `commit -a`). End every commit message with a separate `-m` paragraph: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Never push.
- **Logic goes in StarkKit, views are thin.** If it can be tested, it lives in `ios/Sources/StarkKit` with a Swift Testing test.
- **Tests first** for StarkKit work: write the failing test, run it and see it fail for the stated reason, then implement.
- **Baseline:** `swift test` currently passes 239 tests (three env-gated parity tests are skipped by design). It must stay green after every task.
- **Theme:** only `Colors.*`, `Spacing.*`, `Fonts.mono` from `Theme.swift`; no hardcoded hex, no new colours, no rounded corners.
- **Do not touch the author's phone** (no `xcrun devicectl`, no `deploy.sh`); the controller does the on-device check.
- **App build check** (Tasks 2 and 3): `cd /Users/eladio/src/todo-txt/.claude/worktrees/add-edit-fields/ios/App/Stark && xcodebuild -project Stark.xcodeproj -scheme Stark -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5` must end in `** BUILD SUCCEEDED **`.

---

### Task 1: Pure StarkKit helpers

**Files:**
- Create: `ios/Sources/StarkKit/Models/ReminderPriority.swift`
- Create: `ios/Sources/StarkKit/Models/FormFields.swift`
- Modify: `ios/Sources/StarkKit/Models/Event.swift` (add `rescheduled(to:allDay:)`)
- Modify: `ios/Sources/StarkKit/Planner/AgendaBuilder.swift` (add `AgendaItem.priority`)
- Create tests: `ios/Tests/StarkKitTests/ReminderPriorityTests.swift`, `ios/Tests/StarkKitTests/FormFieldsTests.swift`, `ios/Tests/StarkKitTests/EventRescheduleTests.swift`
- Modify test: `ios/Tests/StarkKitTests/AgendaBuilderTests.swift` (append inside the suite before its closing `}`)

**Interfaces:**
- Produces (used by Tasks 2-3):
  - `public enum ReminderPriority: Int, CaseIterable, Equatable, Sendable { case none, low, medium, high }` with `init(icalValue: Int?)`, `var icalValue: Int?`, `var marks: String`, `var pickerLabel: String`, `static func updated(original: Int?, chosen: ReminderPriority) -> Int?`
  - `public enum FormFields` with `static func trimmedOrNil(_ text: String) -> String?`, `static func normalizedStart(_ date: Date, allDay: Bool) -> Date`, `static func isAllDay(_ date: Date) -> Bool`
  - `Event.rescheduled(to date: Date, allDay: Bool) -> Event`
  - `AgendaItem.priority: ReminderPriority` (`.none` for events and unprioritised reminders)

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/StarkKitTests/ReminderPriorityTests.swift`:

```swift
// ios/Tests/StarkKitTests/ReminderPriorityTests.swift
import Testing
@testable import StarkKit

@Suite("ReminderPriority")
struct ReminderPriorityTests {
    @Test("each level writes the Apple Reminders iCal value; none writes nothing")
    func icalValues() {
        #expect(ReminderPriority.none.icalValue == nil)
        #expect(ReminderPriority.low.icalValue == 9)
        #expect(ReminderPriority.medium.icalValue == 5)
        #expect(ReminderPriority.high.icalValue == 1)
    }

    @Test("an existing iCal value maps to the nearest level")
    func bucketsExistingValues() {
        #expect(ReminderPriority(icalValue: nil) == .none)
        #expect(ReminderPriority(icalValue: 0) == .none)
        #expect(ReminderPriority(icalValue: 1) == .high)
        #expect(ReminderPriority(icalValue: 4) == .high)
        #expect(ReminderPriority(icalValue: 5) == .medium)
        #expect(ReminderPriority(icalValue: 6) == .low)
        #expect(ReminderPriority(icalValue: 9) == .low)
        #expect(ReminderPriority(icalValue: 10) == .none)
        #expect(ReminderPriority(icalValue: -3) == .none)
    }

    @Test("every level survives a write-then-read round trip")
    func roundTrip() {
        for level in ReminderPriority.allCases {
            #expect(ReminderPriority(icalValue: level.icalValue) == level)
        }
    }

    @Test("marks and picker labels")
    func labels() {
        #expect(ReminderPriority.none.marks == "")
        #expect(ReminderPriority.low.marks == "!")
        #expect(ReminderPriority.medium.marks == "!!")
        #expect(ReminderPriority.high.marks == "!!!")
        #expect(ReminderPriority.none.pickerLabel == "None")
        #expect(ReminderPriority.high.pickerLabel == "!!!")
    }

    @Test("an untouched level keeps the original value; a changed level writes the new one")
    func updatedKeepsOriginalWhenUnchanged() {
        #expect(ReminderPriority.updated(original: 3, chosen: .high) == 3)
        #expect(ReminderPriority.updated(original: 0, chosen: .none) == 0)
        #expect(ReminderPriority.updated(original: nil, chosen: .none) == nil)
        #expect(ReminderPriority.updated(original: 3, chosen: .low) == 9)
        #expect(ReminderPriority.updated(original: 3, chosen: .none) == nil)
        #expect(ReminderPriority.updated(original: nil, chosen: .medium) == 5)
    }
}
```

Create `ios/Tests/StarkKitTests/FormFieldsTests.swift`:

```swift
// ios/Tests/StarkKitTests/FormFieldsTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("FormFields")
struct FormFieldsTests {
    private let cal = Calendar(identifier: .gregorian)

    @Test("trimmedOrNil trims outer whitespace, keeps inner newlines, and turns blank into nil")
    func trimmedOrNil() {
        #expect(FormFields.trimmedOrNil("  hi \n") == "hi")
        #expect(FormFields.trimmedOrNil("a\nb") == "a\nb")
        #expect(FormFields.trimmedOrNil("   \n ") == nil)
        #expect(FormFields.trimmedOrNil("") == nil)
    }

    @Test("normalizedStart moves an all-day date to the start of its day and leaves a timed one alone")
    func normalizedStart() {
        let noon = DateMath.date(from: "2026-09-20")
        #expect(FormFields.normalizedStart(noon, allDay: true) == cal.startOfDay(for: noon))
        #expect(FormFields.normalizedStart(noon, allDay: false) == noon)
    }

    @Test("isAllDay is true exactly at local midnight")
    func isAllDay() {
        let noon = DateMath.date(from: "2026-09-20")
        #expect(FormFields.isAllDay(cal.startOfDay(for: noon)))
        #expect(!FormFields.isAllDay(noon))
        #expect(!FormFields.isAllDay(cal.startOfDay(for: noon).addingTimeInterval(60)))
    }
}
```

Create `ios/Tests/StarkKitTests/EventRescheduleTests.swift`:

```swift
// ios/Tests/StarkKitTests/EventRescheduleTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("Event.rescheduled")
struct EventRescheduleTests {
    private let cal = Calendar(identifier: .gregorian)

    private func at(_ iso: String, _ hour: Int, _ minute: Int = 0) -> Date {
        let c = DateMath.components(iso)
        return cal.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute))!
    }

    @Test("a timed event made all-day starts at midnight and drops its end")
    func timedToAllDay() {
        let event = Event(id: "e", title: "Class", start: at("2026-09-20", 9), end: at("2026-09-20", 10))

        let result = event.rescheduled(to: at("2026-09-20", 15), allDay: true)

        #expect(result.isAllDay)
        #expect(result.start == cal.startOfDay(for: at("2026-09-20", 15)))
        #expect(result.end == nil)
    }

    @Test("an all-day event made timed takes the chosen time and has no end")
    func allDayToTimed() {
        let event = Event(id: "e", title: "Trip", start: cal.startOfDay(for: at("2026-09-20", 12)), isAllDay: true)

        let result = event.rescheduled(to: at("2026-09-20", 14, 30), allDay: false)

        #expect(!result.isAllDay)
        #expect(result.start == at("2026-09-20", 14, 30))
        #expect(result.end == nil)
    }

    @Test("a timed event that stays timed keeps its duration when moved")
    func timedStaysTimed() {
        let event = Event(id: "e", title: "Class", start: at("2026-09-20", 9), end: at("2026-09-20", 10))

        let result = event.rescheduled(to: at("2026-09-21", 11), allDay: false)

        #expect(result.start == at("2026-09-21", 11))
        #expect(result.end == at("2026-09-21", 12))
        #expect(!result.isAllDay)
    }

    @Test("an all-day multi-day event that stays all-day keeps its end, shifted by the same days")
    func allDayStaysAllDay() {
        let start = cal.startOfDay(for: at("2026-09-20", 12))
        let end = cal.startOfDay(for: at("2026-09-22", 12))
        let event = Event(id: "e", title: "Trip", start: start, end: end, isAllDay: true)

        let result = event.rescheduled(to: cal.startOfDay(for: at("2026-09-21", 12)), allDay: true)

        #expect(result.isAllDay)
        #expect(result.start == cal.startOfDay(for: at("2026-09-21", 12)))
        #expect(result.end == cal.startOfDay(for: at("2026-09-23", 12)))
    }

    @Test("every other field is preserved")
    func otherFieldsPreserved() {
        let event = Event(
            id: "e", title: "Class", notes: "n", start: at("2026-09-20", 9), location: "Room 4",
            recurrence: RecurrenceRule(frequency: .weekly),
            exceptionDates: [at("2026-09-27", 9)],
            outcomes: [EventOutcomeRecord(date: at("2026-09-20", 9), outcome: .attended)]
        )

        let result = event.rescheduled(to: at("2026-09-20", 9), allDay: true)

        #expect(result.id == "e")
        #expect(result.title == "Class")
        #expect(result.notes == "n")
        #expect(result.location == "Room 4")
        #expect(result.recurrence == event.recurrence)
        #expect(result.exceptionDates == event.exceptionDates)
        #expect(result.outcomes == event.outcomes)
    }
}
```

Append to `AgendaBuilderTests` (before the suite's closing `}`; uses the suite's `build` and `d` helpers):

```swift
    // MARK: - Priority

    @Test("a reminder's agenda item reports its priority level; events and unprioritised reminders report none")
    func agendaItemPriority() {
        let high = Reminder(id: "r1", title: "A", dueDate: d("2026-09-25"), priority: 1)
        let plain = Reminder(id: "r2", title: "B", dueDate: d("2026-09-26"))
        let event = Event(id: "e1", title: "C", start: d("2026-09-27"))

        let items = build(events: [event], reminders: [high, plain])

        #expect(items.map(\.title) == ["A", "B", "C"])
        #expect(items.map(\.priority) == [.high, .none, .none])
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/eladio/src/todo-txt/.claude/worktrees/add-edit-fields/ios && swift test --filter "ReminderPriority|FormFields|Event.rescheduled|AgendaBuilder"`
Expected: FAIL to compile — `ReminderPriority`, `FormFields`, `rescheduled`, `priority` not defined.

- [ ] **Step 3: Implement**

Create `ios/Sources/StarkKit/Models/ReminderPriority.swift`:

```swift
// ios/Sources/StarkKit/Models/ReminderPriority.swift

/// The three priority levels the UI offers (plus none), mapped like Apple Reminders onto the
/// iCal `PRIORITY` value stored in the `.ics`: low 9, medium 5, high 1 (1 is the highest in iCal).
public enum ReminderPriority: Int, CaseIterable, Equatable, Sendable {
    case none, low, medium, high

    /// The value written to `PRIORITY`; nil means no line is written.
    public var icalValue: Int? {
        switch self {
        case .none: return nil
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }

    /// Maps any stored iCal value to the nearest level: 1-4 high, 5 medium, 6-9 low, else none.
    public init(icalValue: Int?) {
        guard let value = icalValue else { self = .none; return }
        switch value {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    /// "", "!", "!!" or "!!!" — what the agenda row shows before the title.
    public var marks: String {
        String(repeating: "!", count: rawValue)
    }

    /// The segmented picker's label.
    public var pickerLabel: String {
        self == .none ? "None" : marks
    }

    /// The value to store after the user edits: the original is kept untouched while the chosen
    /// level still matches it (an imported `PRIORITY:3` stays 3), otherwise the chosen level's
    /// value is written.
    public static func updated(original: Int?, chosen: ReminderPriority) -> Int? {
        ReminderPriority(icalValue: original) == chosen ? original : chosen.icalValue
    }
}
```

Create `ios/Sources/StarkKit/Models/FormFields.swift`:

```swift
// ios/Sources/StarkKit/Models/FormFields.swift
import Foundation

/// Small pure helpers the add/edit screens share, kept out of the views so they are testable.
public enum FormFields {
    /// The text with outer whitespace/newlines trimmed, or nil when nothing is left.
    public static func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// An all-day item is stored at the start of its day; a timed one is stored as picked.
    public static func normalizedStart(_ date: Date, allDay: Bool) -> Date {
        allDay ? Calendar(identifier: .gregorian).startOfDay(for: date) : date
    }

    /// True when the date is exactly local midnight — the model's "date only" marker for reminders.
    public static func isAllDay(_ date: Date) -> Bool {
        Calendar(identifier: .gregorian).startOfDay(for: date) == date
    }
}
```

In `Event.swift`, after `settingStart(_:)` (inside the struct):

```swift
    /// A copy moved to `date` and switched to all-day or timed. An all-day item is stored at the
    /// start of its day. Switching between all-day and timed drops `end` (a timed range makes no
    /// sense as all-day and vice versa); an event that keeps its kind keeps its duration, as
    /// `settingStart(_:)` does. Every other field is left untouched.
    public func rescheduled(to date: Date, allDay: Bool) -> Event {
        var copy = settingStart(FormFields.normalizedStart(date, allDay: allDay))
        if allDay != isAllDay { copy.end = nil }
        copy.isAllDay = allDay
        return copy
    }
```

In `AgendaBuilder.swift`, inside `AgendaItem`, after `outcome`:

```swift
    /// Reminders only: the priority level shown as `!` marks on the row. `.none` for events and
    /// for reminders without a priority.
    public var priority: ReminderPriority {
        guard case .reminder(let reminder) = kind else { return .none }
        return ReminderPriority(icalValue: reminder.priority)
    }
```

- [ ] **Step 4: Run to verify pass, then the full suite**

Run: `swift test --filter "ReminderPriority|FormFields|Event.rescheduled|AgendaBuilder"` → PASS; then `swift test` → all pass (239 + 15 = 254; three env-gated tests skipped).

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/add-edit-fields add ios/Sources/StarkKit/Models/ReminderPriority.swift ios/Sources/StarkKit/Models/FormFields.swift ios/Sources/StarkKit/Models/Event.swift ios/Sources/StarkKit/Planner/AgendaBuilder.swift ios/Tests/StarkKitTests/ReminderPriorityTests.swift ios/Tests/StarkKitTests/FormFieldsTests.swift ios/Tests/StarkKitTests/EventRescheduleTests.swift ios/Tests/StarkKitTests/AgendaBuilderTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/add-edit-fields commit -m "feat(ios): priority levels, form-field helpers and Event.rescheduled" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Add and Edit screens

**Files:**
- Modify: `ios/App/Stark/Stark/AddItemView.swift`
- Modify: `ios/App/Stark/Stark/EditItemView.swift`

**Interfaces:**
- Consumes (Task 1): `FormFields.trimmedOrNil`, `FormFields.normalizedStart`, `FormFields.isAllDay`, `Event.rescheduled(to:allDay:)`, `ReminderPriority` (`allCases`, `pickerLabel`, `icalValue`, `init(icalValue:)`, `updated(original:chosen:)`).
- No unit tests: SwiftUI wiring only; the logic is tested in Task 1. Verify with the app build check plus `swift test`.

- [ ] **Step 1: `AddItemView.swift`**

Add state: `@State private var allDay = false`, `@State private var notes = ""`, `@State private var location = ""`, `@State private var priority: ReminderPriority = .none`.

In the `Form`, replace the single `DatePicker(kind == .event ? "Start" : "Due", selection: $date)` line with:

```swift
                DatePicker(kind == .event ? "Start" : "Due", selection: $date,
                           displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                Toggle("All day", isOn: $allDay)
```

After the Repeat `NavigationLink`, add (inside the `Form`):

```swift
                if kind == .event {
                    TextField("Location", text: $location)
                }
                if kind == .reminder {
                    Picker("Priority", selection: $priority) {
                        ForEach(ReminderPriority.allCases, id: \.self) { Text($0.pickerLabel) }
                    }
                    .pickerStyle(.segmented)
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(1...6)
```

Replace `add()`'s body so the created items carry the new fields:

```swift
    private func add() {
        let start = FormFields.normalizedStart(date, allDay: allDay)
        switch kind {
        case .event:
            store.addEvent(Event(
                title: title,
                notes: FormFields.trimmedOrNil(notes),
                start: start,
                isAllDay: allDay,
                location: FormFields.trimmedOrNil(location),
                recurrence: recurrence
            ))
        case .reminder:
            store.addReminder(Reminder(
                title: title,
                notes: FormFields.trimmedOrNil(notes),
                dueDate: start,
                priority: priority.icalValue,
                recurrence: recurrence
            ))
        }
        dismiss()
    }
```

- [ ] **Step 2: `EditItemView.swift`**

1. Add state next to the existing ones: `@State private var allDay: Bool`, `@State private var notes: String`, `@State private var location: String`, `@State private var priority: ReminderPriority`; and stored constants `private let initialAllDay: Bool`.
2. In `init(item:)`, compute per kind and set the states:
   - event: `allDay = event.isAllDay`, `notes = event.notes ?? ""`, `location = event.location ?? ""`, `priority = .none`.
   - reminder: `allDay = reminder.dueDate.map(FormFields.isAllDay) ?? false`, `notes = reminder.notes ?? ""`, `location = ""`, `priority = ReminderPriority(icalValue: reminder.priority)`.
   Initialise them with `_allDay = State(initialValue: …)` etc. and `initialAllDay = …`, alongside the existing `_title`/`_date`/`_recurrence` initialisation (declare local `let`s in each switch case like the existing `startDate` / `startRecurrence`).
3. Replace the date picker and remove the now-unused `isAllDayEvent`: the picker becomes `DatePicker(dateLabel, selection: $date, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])` followed by `Toggle("All day", isOn: $allDay)`. Delete the `dateComponents` and `isAllDayEvent` computed properties.
4. In the first `Section`, after the Repeat `NavigationLink`, add the same Location (events only), Priority (reminders only, segmented) and Notes fields as in Step 1.
5. `save()`:

```swift
    private func save() {
        switch item.kind {
        case .event(let event):
            // `rescheduled` keeps the duration for a timed event that stays timed, drops `end`
            // when switching between all-day and timed, and preserves every other field.
            var updated = event.rescheduled(to: date, allDay: allDay)
            updated.title = trimmedTitle
            updated.recurrence = recurrence
            updated.notes = FormFields.trimmedOrNil(notes)
            updated.location = FormFields.trimmedOrNil(location)
            store.updateEvent(updated)
        case .reminder(let reminder):
            var updated = reminder
            updated.title = trimmedTitle
            // A reminder with no due date stays that way unless the user picked one.
            if reminder.dueDate != nil || date != initialDate || allDay != initialAllDay {
                updated.dueDate = FormFields.normalizedStart(date, allDay: allDay)
            }
            updated.recurrence = recurrence
            updated.notes = FormFields.trimmedOrNil(notes)
            updated.priority = ReminderPriority.updated(original: reminder.priority, chosen: priority)
            store.updateReminder(updated)
        }
        dismiss()
    }
```

6. Update the file's header doc comment: the editable fields are now title, date, all-day, repeat, notes, location (events) and priority (reminders).

- [ ] **Step 3: Verify**

Run the app build check (see Global Constraints) → `** BUILD SUCCEEDED **`, no new warnings from these two files. Run `swift test` from `ios/` → all pass (254).

- [ ] **Step 4: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/add-edit-fields add ios/App/Stark/Stark/AddItemView.swift ios/App/Stark/Stark/EditItemView.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/add-edit-fields commit -m "feat(ios): all-day toggle, notes, location and priority on the add and edit screens" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Priority marks on the agenda row + docs

**Files:**
- Modify: `ios/App/Stark/Stark/AgendaRow.swift`
- Modify: `CLAUDE.md` (Native iOS App section)

**Interfaces:**
- Consumes (Task 1): `AgendaItem.priority`, `ReminderPriority.marks`.

- [ ] **Step 1: Row (`AgendaRow.swift`, visuals only)**

1. Replace the title `Text(item.title)…` in the text column with an `HStack(alignment: .firstTextBaseline, spacing: Spacing.xs)` holding an optional marks label and the existing title (keep the title's existing `.strikethrough(...)` and `.foregroundStyle(...)` modifiers exactly as they are):

```swift
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    if showsPriorityMarks {
                        Text(item.priority.marks)
                            .font(Fonts.mono(14))
                            .foregroundStyle(Colors.accent)
                    }
                    Text(item.title)
                        .strikethrough(looksDone || hasOutcome)
                        .foregroundStyle(looksDone || hasOutcome ? Colors.textSecondary : Colors.text)
                }
```

2. Add `private var showsPriorityMarks: Bool { item.priority != .none && !looksDone }` next to `hasOutcome`. (Marks are a prefix so they survive truncation, as the Expo birthday badge does; hidden once the reminder looks done.)
3. `accessibilitySummary`: after the title is appended and before the location, add `if showsPriorityMarks { parts.append("\(priorityWord) priority") }` with `private var priorityWord: String` returning "high"/"medium"/"low" for `.high`/`.medium`/`.low` (and "" for none).
4. Update the file's header doc comment to mention the priority marks before the title.

- [ ] **Step 2: Docs**

In `CLAUDE.md`, Native iOS App section, add one paragraph after the "Event attendance" paragraph:

> **Add/edit fields** (`AddItemView`, `EditItemView`; logic in `ReminderPriority`, `FormFields`, `Event.rescheduled(to:allDay:)`): both screens have an **All day** toggle (date-only: reminders store start-of-day — the model's "no time" marker — and events set `isAllDay`; the toggle only normalises on save, so turning it on then off restores the picked time; switching an event between all-day and timed drops its `end`), **Notes** (reminders and events; blank saves as none), **Location** (events) and a three-level **Priority** picker (reminders only — events never carry a priority): `!` low = `PRIORITY:9`, `!!` medium = 5, `!!!` high = 1, None writes no line. An existing value maps to the nearest level (1-4 high, 5 medium, 6-9 low) and is only rewritten if the level is changed (`ReminderPriority.updated`). The agenda row shows the marks in the accent colour as a prefix before an incomplete reminder's title; sorting does not use priority. Undated reminders, lists and location-based reminders are deliberately not built (an undated reminder would be invisible: the agenda only lists dated items).

- [ ] **Step 3: Verify**

App build check → `** BUILD SUCCEEDED **`; `swift test` from `ios/` → all pass (254).

- [ ] **Step 4: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/add-edit-fields add ios/App/Stark/Stark/AgendaRow.swift CLAUDE.md
git -C /Users/eladio/src/todo-txt/.claude/worktrees/add-edit-fields commit -m "feat(ios): show priority marks on the agenda row and document the new fields" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
