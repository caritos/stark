# Completion History and Carried-Over Misses Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A repeating reminder shows one open row carrying its *first* unresolved miss (daily included), completions and attendance record when they happened, and the detail sheet shows how often and how late an item is done.

**Architecture:** All logic stays in `ios/Sources/StarkKit` (tested with Swift Testing); views only render. `buildAgendaItems` picks the oldest miss and folds today's occurrence into it; `PlannerStore` resolves the whole carried set at once and stamps timestamps; a new pure `CompletionHistory` computes stats; `AgendaRowView`/`EditItemView` render them.

**Tech Stack:** Swift, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), SwiftPM (`cd ios && swift test`).

**Spec:** `docs/superpowers/specs/2026-10-14-completion-history-design.md`

## Global Constraints

- Tests use Swift Testing, never XCTest; run with `cd ios && swift test`.
- Never put logic in a view; anything testable goes in StarkKit.
- Never build inclusive day-range bounds from `DateMath.date(from:)` (it is local noon); use start of day / last second of day with a gregorian `Calendar`.
- `completedDate` keeps meaning *due occurrence date* (Weekly Review depends on it). The real tick time is the new `completedAt`.
- `buildAgendaItems` may use `today` only for the overdue cut-off and lookback (`densityCounts` shortcut depends on it).
- Old `.ics` files must parse unchanged; new properties are optional and omitted when nil so existing fixtures stay byte-identical.
- Never push; commit locally only (user instruction). Commit message ends with:
  `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01Wc7PQcwEXFMGDDnwtxHwNa`.
- Lookback is `AgendaWindow.overdueLookbackDays` (90).

## Review Focus

- A daily item missed for 90+ days: label reads "90+ days overdue", row still resolves cleanly (Task 2/5).
- Completing the carried row twice (double tap / pending timer after Done): one completed copy, one set of exdates (Task 3).
- Undo of a completed copy clears `completedAt` and the item reappears once, not twice (Task 3).
- Old completed copies with no `seriesID`/`completedAt`: history falls back to title, shows no timestamp, doesn't crash (Task 4).
- A completed copy whose done day equals its due day shows no "done" note (Task 5).
- Two different reminders with the same title: history merges them only for copies lacking `seriesID`; documented limitation (Task 4).

---

### Task 1: Timestamps and series link in the model and `.ics`

**Files:**
- Modify: `ios/Sources/StarkKit/Models/Reminder.swift`
- Modify: `ios/Sources/StarkKit/Models/Event.swift` (`EventOutcomeRecord`)
- Modify: `ios/Sources/StarkKit/ICS/ICSSerializer.swift`
- Modify: `ios/Sources/StarkKit/ICS/ICSParser.swift`
- Test: `ios/Tests/StarkKitTests/ICSRoundTripTests.swift` (create if no suitable file; check `ls ios/Tests/StarkKitTests | grep -i ics` first and append to the existing ICS test suite if one exists)

**Interfaces:**
- Produces: `Reminder.completedAt: Date?`, `Reminder.seriesID: String?` (both default nil in `init`, appended as last init params), `EventOutcomeRecord.recordedAt: Date?` (init param `recordedAt: Date? = nil`).
- Format: reminder lines `X-STARK-COMPLETED-AT:<ICS datetime>` and `X-STARK-SERIES:<id>` (after `COMPLETED`); event lines `X-STARK-ATTENDED[;VALUE=DATE][;X-RECORDED=<ICS datetime>]:<date>`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import StarkKit

@Suite("ICS completion timestamps")
struct ICSCompletionTimestampTests {
    private func stamp(_ iso: String, h: Int, m: Int) -> Date {
        let c = DateMath.components(iso)
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: h, minute: m))!
    }

    @Test("a completed reminder's completedAt and seriesID round-trip")
    func reminderRoundTrip() {
        let r = Reminder(id: "c1", title: "Walk", dueDate: stamp("2026-10-07", h: 9, m: 0), isCompleted: true,
                         completedDate: stamp("2026-10-07", h: 9, m: 0),
                         completedAt: stamp("2026-10-14", h: 10, m: 59), seriesID: "master")
        let text = ICSSerializer.serialize(events: [], reminders: [r])
        let parsed = ICSParser.parse(text).reminders
        #expect(parsed == [r])
    }

    @Test("an attended mark's recordedAt round-trips, timed and all-day")
    func outcomeRoundTrip() {
        let timed = Event(id: "e1", title: "Gym", start: stamp("2026-10-13", h: 7, m: 0),
                          outcomes: [EventOutcomeRecord(date: stamp("2026-10-13", h: 7, m: 0), outcome: .attended,
                                                        recordedAt: stamp("2026-10-14", h: 8, m: 5))])
        let allDay = Event(id: "e2", title: "Trip", start: DateMath.date(from: "2026-10-13"), isAllDay: true,
                           outcomes: [EventOutcomeRecord(date: DateMath.date(from: "2026-10-13"), outcome: .skipped,
                                                         recordedAt: stamp("2026-10-14", h: 8, m: 5))])
        let parsed = ICSParser.parse(ICSSerializer.serialize(events: [timed, allDay], reminders: [])).events
        #expect(parsed == [timed, allDay])
    }

    @Test("files without the new properties parse with nil timestamps and re-serialize identically")
    func oldFilesUnchanged() {
        let r = Reminder(id: "c2", title: "Old", dueDate: stamp("2026-09-01", h: 9, m: 0), isCompleted: true,
                         completedDate: stamp("2026-09-01", h: 9, m: 0))
        let e = Event(id: "e3", title: "Old event", start: stamp("2026-09-01", h: 9, m: 0),
                      outcomes: [EventOutcomeRecord(date: stamp("2026-09-01", h: 9, m: 0), outcome: .attended)])
        let text = ICSSerializer.serialize(events: [e], reminders: [r])
        #expect(!text.contains("X-STARK-COMPLETED-AT"))
        #expect(!text.contains("X-RECORDED"))
        let parsed = ICSParser.parse(text)
        #expect(parsed.reminders[0].completedAt == nil)
        #expect(parsed.reminders[0].seriesID == nil)
        #expect(parsed.events[0].outcomes[0].recordedAt == nil)
        #expect(ICSSerializer.serialize(events: parsed.events, reminders: parsed.reminders) == text)
    }
}
```

(If the parser entry point is not `ICSParser.parse(_:)` returning `(events:reminders:)`, read `ICSParser.swift` top and adapt the call; the assertions stay.)

- [ ] **Step 2: Run to verify failure**

Run: `cd ios && swift test --filter ICSCompletionTimestampTests`
Expected: compile FAIL (`completedAt`/`seriesID`/`recordedAt` undefined).

- [ ] **Step 3: Implement**

`Reminder.swift`: add `public var completedAt: Date?` and `public var seriesID: String?`; append `completedAt: Date? = nil, seriesID: String? = nil` to `init` and assign.

`Event.swift`: in `EventOutcomeRecord` add `public var recordedAt: Date?`; init `init(date: Date, outcome: EventOutcome, recordedAt: Date? = nil)`.

`ICSSerializer.swift` reminder: after the `COMPLETED` line add
```swift
if let at = reminder.completedAt { lines.append("X-STARK-COMPLETED-AT:\(ICSDateFormat.format(at, allDay: false))") }
if let series = reminder.seriesID { lines.append("X-STARK-SERIES:\(series.filter { !$0.isNewline })") }
```
Event outcomes loop: build the name with an optional recorded parameter:
```swift
let recorded = record.recordedAt.map { ";X-RECORDED=\(ICSDateFormat.format($0, allDay: false))" } ?? ""
lines.append("\(name)\(dateParam(event.isAllDay))\(recorded):\(ICSDateFormat.format(record.date, allDay: event.isAllDay))")
```

`ICSParser.swift` `outcomes(_:)`: parse the `X-RECORDED=` parameter out of the part before the colon:
```swift
let head = String(line[line.startIndex..<colon])
let recordedAt = head.split(separator: ";").compactMap { part -> Date? in
    guard part.hasPrefix("X-RECORDED=") else { return nil }
    return ICSDateFormat.parse(String(part.dropFirst("X-RECORDED=".count)))?.date
}.first
return EventOutcomeRecord(date: date, outcome: outcome, recordedAt: recordedAt)
```
`parseReminder`: pass `completedAt: props["X-STARK-COMPLETED-AT"].flatMap { ICSDateFormat.parse($0)?.date }, seriesID: props["X-STARK-SERIES"]`.

- [ ] **Step 4: Run to verify pass**

Run: `cd ios && swift test`
Expected: all pass (existing fixtures byte-identical).

- [ ] **Step 5: Commit**

```bash
git add ios && git commit -m "feat(ios): completedAt, seriesID and recordedAt in the model and .ics"
```

---

### Task 2: One open row carrying the first miss (daily included)

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/AgendaBuilder.swift`
- Create: `ios/Sources/StarkKit/Planner/OverdueLabel.swift`
- Test: `ios/Tests/StarkKitTests/AgendaBuilderTests.swift`, `ios/Tests/StarkKitTests/OverdueLabelTests.swift` (create)

**Interfaces:**
- Produces: `OverdueLabel.text(daysOverdue: Int, lookbackDays: Int = AgendaWindow.overdueLookbackDays) -> String` ("1 day overdue", "7 days overdue", "90+ days overdue" when `daysOverdue >= lookbackDays`); `AgendaItem.daysOverdue(today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int?` (nil when not overdue; whole days between start of `occurrence` and start of `today`, min 1).

- [ ] **Step 1: Write failing tests**

In `AgendaBuilderTests.swift` (fixture today = Sun 2026-09-20 10:00; `d(_:)`, `build(reminders:)`, `iso`, `todayStart` exist):

```swift
@Test("a daily reminder missed for several days shows one overdue row dated at the FIRST miss")
func dailyCarriesFirstMiss() {
    // Due daily from Sep 14; today Sep 20 has its own occurrence, folded in.
    let r = Reminder(id: "d", title: "Walk", dueDate: d("2026-09-14"), recurrence: RecurrenceRule(frequency: .daily))
    let open = build(reminders: [r]).filter { $0.displayDate == todayStart }
    #expect(open.count == 1)
    #expect(open[0].isOverdue)
    #expect(iso(open[0].occurrence) == "2026-09-14")
    #expect(open[0].daysOverdue(today: today) == 6)
}

@Test("a weekly reminder with several misses carries the oldest one")
func weeklyCarriesFirstMiss() {
    let r = Reminder(id: "w", title: "Review", dueDate: d("2026-08-31"), recurrence: RecurrenceRule(frequency: .weekly))
    let overdue = build(reminders: [r]).filter(\.isOverdue)
    #expect(overdue.count == 1)
    #expect(iso(overdue[0].occurrence) == "2026-08-31")
}

@Test("a recurring reminder with no miss and an occurrence today shows it normally")
func noMissShowsTodayNormally() {
    let r = Reminder(id: "d", title: "Walk", dueDate: d("2026-09-20"), recurrence: RecurrenceRule(frequency: .daily))
    let items = build(reminders: [r]).filter { iso($0.displayDate) == "2026-09-20" }
    #expect(items.count == 1)
    #expect(!items[0].isOverdue)
}
```
Replace/rewrite the existing tests that assert the old rules: `weeklyOnlyLatestMissedIsOverdue` (now first miss = 2026-08-31, `missed dropped` assertion removed), `monthlyOnlyLatestMissedIsOverdue` (first miss in lookback), the daily-misses-dropped test(s) (now one overdue row at the first miss), and `weeklyOccurrenceTodayFoldsIntoOverdueRow` (occurrence is now the first miss).

`OverdueLabelTests.swift`:
```swift
import Testing
@testable import StarkKit

@Suite("OverdueLabel")
struct OverdueLabelTests {
    @Test("singular, plural and capped")
    func text() {
        #expect(OverdueLabel.text(daysOverdue: 1) == "1 day overdue")
        #expect(OverdueLabel.text(daysOverdue: 7) == "7 days overdue")
        #expect(OverdueLabel.text(daysOverdue: 90) == "90+ days overdue")
        #expect(OverdueLabel.text(daysOverdue: 400) == "90+ days overdue")
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter "AgendaBuilder|OverdueLabel"`: new tests FAIL / compile error.

- [ ] **Step 3: Implement**

`AgendaBuilder.swift` overdue selection becomes:
```swift
let overdueOccurrences: [Date]
if reminder.recurrence == nil {
    overdueOccurrences = missed
} else {
    // One open row per series, carrying the OLDEST unresolved miss so the row says how long it
    // has really been open. Daily included (a missed day is exactly what the user wants to see).
    overdueOccurrences = missed.min().map { [$0] } ?? []
}
```
Today's row is appended only when `overdueOccurrences.isEmpty` (drop the `|| .daily` clause). Update the doc comment block above `buildAgendaItems` to describe first-miss, daily included, today folded in.

`OverdueLabel.swift`:
```swift
import Foundation

public enum OverdueLabel {
    public static func text(daysOverdue: Int, lookbackDays: Int = AgendaWindow.overdueLookbackDays) -> String {
        if daysOverdue >= lookbackDays { return "\(lookbackDays)+ days overdue" }
        return daysOverdue == 1 ? "1 day overdue" : "\(daysOverdue) days overdue"
    }
}

extension AgendaItem {
    /// Whole calendar days from the missed occurrence to `today`, or nil when not overdue.
    public func daysOverdue(today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int? {
        guard isOverdue else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: occurrence), to: calendar.startOfDay(for: today)).day ?? 1
        return max(1, days)
    }
}
```

- [ ] **Step 4: Run** — `swift test --filter "AgendaBuilder|OverdueLabel"` PASS. Other suites (PlannerStore, density, weekly review) may now fail; they are fixed in Task 3, so only require the filtered run here and note failures.

- [ ] **Step 5: Commit** — `git commit -am "feat(ios): carry the first miss on the single open row, daily included"` (add new files).

---

### Task 3: Resolve the carried set and stamp completion times

**Files:**
- Modify: `ios/Sources/StarkKit/Planner/PlannerStore.swift` (`completeReminder`, `skipReminder`, `earlierMissedOccurrences`, `uncompleteReminder`, `setEventOutcome`)
- Test: `ios/Tests/StarkKitTests/PlannerStoreTests.swift`, `ios/Tests/StarkKitTests/PendingCompletionsTests.swift`

**Interfaces:**
- Consumes: Task 1 fields; Task 2 first-miss rule.
- Produces: `completeReminder(id:on:today:now:)`, `skipReminder(id:on:today:)`, `setEventOutcome(id:on:outcome:now:)` — `now: Date = Date()` stamps `completedAt` / `recordedAt`. Completed copy gets `seriesID = master.id`, `completedAt = now`.

Rule: resolving occurrence `D` (day before `today`) exdates `D`, every un-exdated occurrence in the lookback **after** `D` strictly before today, and today's occurrence, for ALL recurring frequencies (daily included). Resolving `D` on or after today clears nothing extra.

- [ ] **Step 1: Write failing tests** (inside the existing weekly-store suite that has `fixedToday` = Sun 2026-09-20 10:00, `makeStore()`, `start(_:around:)`, `dt(_:hour:minute:)`, `overdueDays`, `upcomingDays`):

```swift
@Test("completing the carried first miss clears every later miss and today's occurrence")
@MainActor
func completeFirstMissClearsRest() throws {
    let (store, _, _) = makeStore()
    start(store, around: fixedToday)
    store.addReminder(Reminder(id: "rem-d", title: "Walk", dueDate: dt("2026-09-14", hour: 9, minute: 0), recurrence: RecurrenceRule(frequency: .daily)))
    #expect(overdueDays(store) == ["2026-09-14"])
    let now = dt("2026-09-20", hour: 10, minute: 59)

    store.completeReminder(id: "rem-d", on: dt("2026-09-14", hour: 9, minute: 0), today: fixedToday, now: now)

    #expect(overdueDays(store).isEmpty)
    #expect(upcomingDays(store).first == "2026-09-21")
    let copies = store.reminders.filter(\.isCompleted)
    #expect(copies.count == 1)
    #expect(copies[0].completedAt == now)
    #expect(copies[0].seriesID == "rem-d")
    #expect(copies[0].dueDate == dt("2026-09-14", hour: 9, minute: 0))
    let master = try #require(store.reminders.first { $0.id == "rem-d" })
    #expect(isoDays(master.exceptionDates).sorted() == ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19", "2026-09-20"])
}

@Test("completing the same carried miss twice adds one copy and one set of exceptions")
@MainActor
func completeTwiceIsIdempotent() throws {
    let (store, _, _) = makeStore()
    start(store, around: fixedToday)
    store.addReminder(Reminder(id: "rem-d", title: "Walk", dueDate: dt("2026-09-14", hour: 9, minute: 0), recurrence: RecurrenceRule(frequency: .daily)))
    let day = dt("2026-09-14", hour: 9, minute: 0)
    store.completeReminder(id: "rem-d", on: day, today: fixedToday)
    store.completeReminder(id: "rem-d", on: day, today: fixedToday)
    #expect(store.reminders.filter(\.isCompleted).count == 1)
}

@Test("skipping the carried first miss clears the rest and makes no copy")
@MainActor
func skipFirstMissClearsRest() throws {
    let (store, _, _) = makeStore()
    start(store, around: fixedToday)
    store.addReminder(Reminder(id: "rem-d", title: "Walk", dueDate: dt("2026-09-14", hour: 9, minute: 0), recurrence: RecurrenceRule(frequency: .daily)))
    store.skipReminder(id: "rem-d", on: dt("2026-09-14", hour: 9, minute: 0), today: fixedToday)
    #expect(overdueDays(store).isEmpty)
    #expect(store.reminders.filter(\.isCompleted).isEmpty)
}

@Test("undoing a completed copy clears completedAt")
@MainActor
func undoClearsCompletedAt() throws {
    let (store, _, _) = makeStore()
    start(store, around: fixedToday)
    store.addReminder(Reminder(id: "rem-w", title: "Trash", dueDate: dt("2026-09-13", hour: 9, minute: 0), recurrence: RecurrenceRule(frequency: .weekly)))
    store.completeReminder(id: "rem-w", on: dt("2026-09-13", hour: 9, minute: 0), today: fixedToday, now: fixedToday)
    let copy = try #require(store.reminders.first { $0.isCompleted })
    store.uncompleteReminder(id: copy.id)
    let reopened = try #require(store.reminders.first { $0.id == copy.id })
    #expect(reopened.completedAt == nil)
    #expect(!reopened.isCompleted)
}

@Test("marking an event attended stamps recordedAt; clearing removes the record")
@MainActor
func attendedStampsRecordedAt() throws {
    let (store, _, _) = makeStore()
    start(store, around: fixedToday)
    store.addEvent(Event(id: "e", title: "Gym", start: dt("2026-09-19", hour: 7, minute: 0)))
    store.setEventOutcome(id: "e", on: dt("2026-09-19", hour: 7, minute: 0), outcome: .attended, now: fixedToday)
    let event = try #require(store.events.first { $0.id == "e" })
    #expect(event.outcomes.first?.recordedAt == fixedToday)
    store.setEventOutcome(id: "e", on: dt("2026-09-19", hour: 7, minute: 0), outcome: nil, now: fixedToday)
    #expect(try #require(store.events.first { $0.id == "e" }).outcomes.isEmpty)
}
```
Update existing tests that encode the old rules (all in the weekly-store suite, fixture Sundays from Aug 30, today Sep 20): the overdue row is now `2026-08-30`; after completing/skipping it the master's exception dates are `2026-08-30, 09-06, 09-13, 09-20`; `upcomingDays` starts `2026-09-27`; "a daily recurring reminder gets no extra exceptions" now clears the later misses like any other series; `completingTodayClearsEarlierMisses` (added in 326b7f0) and `resolvingOverdueAlsoClearsTodaysOccurrence` should be adapted to resolve the *first* miss. In `PendingCompletionsTests` the weekly case's expected exception count follows the same rule (first miss + all later misses + today). Delete tests that assert a *latest*-miss semantics with no replacement value.

- [ ] **Step 2: Run to verify failure** — `swift test --filter PlannerStore`: compile FAIL (`now:`), then behavior FAIL.

- [ ] **Step 3: Implement**

In `PlannerStore`: rename `earlierMissedOccurrences(of:before:today:)` → `carriedOccurrences(of:from:today:)`:
```swift
/// Everything a resolved carried row must clear besides the occurrence itself: every
/// un-exdated occurrence strictly after `date`'s day up to and including today. Empty unless
/// `date`'s day is before today (resolving today or a future occurrence clears nothing extra).
private func carriedOccurrences(of reminder: Reminder, from date: Date, today: Date) -> [Date] {
    guard reminder.recurrence != nil else { return [] }
    let calendar = Calendar(identifier: .gregorian)
    let todayStart = calendar.startOfDay(for: today)
    let dateStart = calendar.startOfDay(for: date)
    guard dateStart < todayStart,
          let after = calendar.date(byAdding: .day, value: 1, to: dateStart),
          let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1),
          after <= todayEnd else { return [] }
    return OccurrenceExpander.expand(reminder: reminder, in: after...todayEnd)
}
```
Use it in `completeReminder` and `skipReminder` (append the result to `exceptionDates` exactly as the old earlier-misses were). Add `now: Date = Date()` to `completeReminder`; set `completedCopy.completedAt = now` and `completedCopy.seriesID = recurringReminders[index].id`; for the one-off in-place branch also set `completedAt = now`. `uncompleteReminder`: also `completedAt = nil`. `setEventOutcome(..., now: Date = Date())`: build the record with `recordedAt: now`. Update the doc comments on both functions to the new rule.

- [ ] **Step 4: Run** — `cd ios && swift test` all PASS (fix any remaining old-rule test per the Step 1 list).

- [ ] **Step 5: Commit** — `git commit -am "feat(ios): resolving the carried row clears later misses and today; stamp completion times"`

---

### Task 4: `CompletionHistory` stats

**Files:**
- Create: `ios/Sources/StarkKit/Planner/CompletionHistory.swift`
- Test: `ios/Tests/StarkKitTests/CompletionHistoryTests.swift`

**Interfaces:**
- Produces:
```swift
public struct CompletionEntry: Equatable {
    public let due: Date        // the occurrence's due date (Reminder.dueDate / EventOutcomeRecord.date)
    public let done: Date?      // completedAt / recordedAt; nil for old records
    public let daysLate: Int    // whole days done-day minus due-day, min 0; 0 when done is nil
}
public struct CompletionHistory: Equatable {
    public let entries: [CompletionEntry]        // newest first by (done ?? due)
    public let doneLast30: Int
    public let doneLast90: Int
    public let lateLast90: Int                   // entries with daysLate > 0 in the last 90 days
    public let lastDone: Date?                   // (done ?? due) of the newest entry
    public let averageGapDays: Double?           // nil with < 2 entries
    public let longestGapDays: Int?              // nil with < 2 entries
    public static func forReminder(_ reminder: Reminder, among reminders: [Reminder], today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> CompletionHistory
    public static func forEvent(_ event: Event, today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> CompletionHistory
}
```
Series match: `masterID = reminder.seriesID ?? (reminder.recurrence != nil ? reminder.id : nil)`; include `r.isCompleted` where `r.seriesID == masterID`, or `r.seriesID == nil && r.title == reminder.title`. Events: records with `.attended`. Gaps are calendar-day differences between consecutive entries' (done ?? due) days, one entry per calendar day (two completions the same day count once for gaps). "Last N days" = `(done ?? due)` day within `[today - N, today]`.

- [ ] **Step 1: Failing tests**

```swift
import Testing
import Foundation
@testable import StarkKit

@Suite("CompletionHistory")
struct CompletionHistoryTests {
    private let today = DateMath.date(from: "2026-10-14")
    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }
    private func copy(due: String, done: String?, series: String? = "m", title: String = "Walk") -> Reminder {
        Reminder(id: UUID().uuidString, title: title, dueDate: d(due), isCompleted: true, completedDate: d(due),
                 completedAt: done.map(d), seriesID: series)
    }
    private let master = Reminder(id: "m", title: "Walk", dueDate: DateMath.date(from: "2026-09-01"), recurrence: RecurrenceRule(frequency: .daily))

    @Test("counts, last done, gaps and lateness for a series")
    func stats() {
        let all = [master,
                   copy(due: "2026-10-14", done: "2026-10-14"),
                   copy(due: "2026-10-11", done: "2026-10-12"),   // made up a day late
                   copy(due: "2026-10-07", done: "2026-10-07")]
        let h = CompletionHistory.forReminder(master, among: all, today: today)
        #expect(h.entries.count == 3)
        #expect(h.doneLast30 == 3)
        #expect(h.lateLast90 == 1)
        #expect(h.entries[1].daysLate == 1)
        #expect(h.lastDone == d("2026-10-14"))
        #expect(h.longestGapDays == 5)          // Oct 7 -> Oct 12
        #expect(h.averageGapDays == 3.5)        // (5 + 2) / 2
    }

    @Test("old copies without seriesID match by title; other titles and series are excluded")
    func titleFallback() {
        let all = [master,
                   copy(due: "2026-10-10", done: nil, series: nil),
                   copy(due: "2026-10-09", done: "2026-10-09", series: "other"),
                   copy(due: "2026-10-08", done: nil, series: nil, title: "Different")]
        let h = CompletionHistory.forReminder(master, among: all, today: today)
        #expect(h.entries.count == 1)
        #expect(h.entries[0].done == nil)
        #expect(h.entries[0].daysLate == 0)
    }

    @Test("fewer than two entries gives no gaps; none gives no lastDone")
    func sparse() {
        let none = CompletionHistory.forReminder(master, among: [master], today: today)
        #expect(none.lastDone == nil && none.averageGapDays == nil && none.longestGapDays == nil)
        let one = CompletionHistory.forReminder(master, among: [master, copy(due: "2026-10-01", done: "2026-10-01")], today: today)
        #expect(one.averageGapDays == nil && one.lastDone == d("2026-10-01"))
        #expect(one.doneLast30 == 1)
    }

    @Test("events: only attended marks count, recordedAt feeds lateness")
    func events() {
        let e = Event(id: "e", title: "Gym", start: d("2026-10-01"), recurrence: RecurrenceRule(frequency: .daily), outcomes: [
            EventOutcomeRecord(date: d("2026-10-12"), outcome: .attended, recordedAt: d("2026-10-13")),
            EventOutcomeRecord(date: d("2026-10-13"), outcome: .skipped),
            EventOutcomeRecord(date: d("2026-10-14"), outcome: .attended),
        ])
        let h = CompletionHistory.forEvent(e, today: today)
        #expect(h.entries.count == 2)
        #expect(h.lateLast90 == 1)
        #expect(h.longestGapDays == 2)          // Oct 13 -> Oct 14 is 1; (done ?? due): 13, 14 -> gap 1
    }
}
```
(Correct the last assertion when running: with entries on days Oct 13 and Oct 14 the gap is 1 — set `longestGapDays == 1`; the inline comment states the arithmetic.)

- [ ] **Step 2: Run** — `swift test --filter CompletionHistory`: compile FAIL.

- [ ] **Step 3: Implement** `CompletionHistory.swift` per the interface above. Core:
```swift
private static func build(_ raw: [(due: Date, done: Date?)], today: Date, calendar: Calendar) -> CompletionHistory {
    let entries = raw.map { r -> CompletionEntry in
        let late = r.done.map { max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: r.due), to: calendar.startOfDay(for: $0)).day ?? 0) } ?? 0
        return CompletionEntry(due: r.due, done: r.done, daysLate: late)
    }.sorted { ($0.done ?? $0.due) > ($1.done ?? $1.due) }
    let todayStart = calendar.startOfDay(for: today)
    func within(_ days: Int, _ e: CompletionEntry) -> Bool {
        let day = calendar.startOfDay(for: e.done ?? e.due)
        guard let from = calendar.date(byAdding: .day, value: -days, to: todayStart) else { return false }
        return day >= from && day <= todayStart
    }
    let uniqueDays = Array(Set(entries.map { calendar.startOfDay(for: $0.done ?? $0.due) })).sorted()
    let gaps = zip(uniqueDays, uniqueDays.dropFirst()).map {
        calendar.dateComponents([.day], from: $0, to: $1).day ?? 0
    }
    return CompletionHistory(
        entries: entries,
        doneLast30: entries.filter { within(30, $0) }.count,
        doneLast90: entries.filter { within(90, $0) }.count,
        lateLast90: entries.filter { within(90, $0) && $0.daysLate > 0 }.count,
        lastDone: entries.first.map { $0.done ?? $0.due },
        averageGapDays: gaps.isEmpty ? nil : Double(gaps.reduce(0, +)) / Double(gaps.count),
        longestGapDays: gaps.max()
    )
}
```
`forReminder` / `forEvent` map their records to `(due, done)` per the series-match rule and call `build`.

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit** — `git add -A ios && git commit -m "feat(ios): CompletionHistory stats"`

---

### Task 5: Views, docs, device check

**Files:**
- Modify: `ios/App/Stark/Stark/AgendaRow.swift` (`timeLine`, completed note), `ios/App/Stark/Stark/AgendaView.swift` (pass `today` to rows), `ios/App/Stark/Stark/EditItemView.swift` (History section), `ios/App/Stark/Stark/SearchView.swift` and `WeeklyReviewView.swift` (row call sites)
- Create: `ios/Sources/StarkKit/Planner/CompletionNote.swift`
- Test: `ios/Tests/StarkKitTests/CompletionNoteTests.swift`
- Modify: `CLAUDE.md` (Overdue and completion semantics paragraph, Weekly Review limitation)

**Interfaces:**
- Produces: `AgendaItem.completionNote: String?` — for a completed reminder whose `completedAt` day differs from its `dueDate` day: `"done Oct 14"`; otherwise nil. `AgendaRowView(item:isPending:today:)` with `var today: Date? = nil` (nil → no days-overdue suffix, so Search/Weekly Review call sites keep compiling).

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
@testable import StarkKit

@Suite("CompletionNote")
struct CompletionNoteTests {
    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }
    private func item(due: String, at: String?) -> AgendaItem {
        let r = Reminder(id: "r", title: "T", dueDate: d(due), isCompleted: true, completedDate: d(due), completedAt: at.map(d))
        return AgendaItem(kind: .reminder(r), occurrence: d(due), displayDate: d(due), isOverdue: false)
    }
    @Test("shown only when done on a different day than due")
    func note() {
        #expect(item(due: "2026-10-13", at: "2026-10-14").completionNote == "done Oct 14")
        #expect(item(due: "2026-10-14", at: "2026-10-14").completionNote == nil)
        #expect(item(due: "2026-10-14", at: nil).completionNote == nil)
    }
}
```

- [ ] **Step 2: Run** — compile FAIL.

- [ ] **Step 3: Implement**

`CompletionNote.swift`:
```swift
import Foundation

extension AgendaItem {
    /// "done Oct 14" for a completed reminder finished on a different calendar day than it was due.
    public var completionNote: String? {
        guard case .reminder(let r) = kind, r.isCompleted, let at = r.completedAt, let due = r.dueDate else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        guard !calendar.isDate(at, inSameDayAs: due) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return "done \(formatter.string(from: at))"
    }
}
```
`AgendaRowView`: add `var today: Date? = nil`; in `timeLine` for an overdue reminder use
```swift
var text = AgendaFormat.overdueLabel(item.occurrence)
if let today, let days = item.daysOverdue(today: today) { text += " · \(OverdueLabel.text(daysOverdue: days))" }
return (text, true)
```
and, for a completed reminder, show `item.completionNote` as the time line (secondary colour) when non-nil and no time line already. `AgendaView` passes `today: today` at its `AgendaRowView(item:isPending:)` call (line ~201). `EditItemView`: add `.task { await store.loadAllMonths() }` if absent, compute `CompletionHistory.forReminder(reminder, among: store.reminders, today: Date())` / `forEvent`, and render a "History" `Section` (only when `entries` non-empty) with rows: "Last 30 days: N", "Last 90 days: N (L late)", "Last done: <date>", "Average gap: X days", "Longest gap: N days", then up to 10 entries "Due Oct 13 · done Oct 14 (1 day late)". Use the existing list-row styling in that file; mono font, `Colors.textSecondary` for labels.

`CLAUDE.md`: replace "keeps only their *latest* miss; daily recurring misses are dropped entirely" and the "one overdue row keeping the missed date" text with the first-miss rule, add `completedAt`/`seriesID`/`recordedAt`, `CompletionHistory`, and drop the Weekly Review "no timestamps" limitation wording (still due-based).

- [ ] **Step 4: Verify**

Run: `cd ios && swift test` → all pass. Then `xcodebuild -project App/Stark/Stark.xcodeproj -scheme Stark -destination 'generic/platform=iOS' build` (or `ios/App/deploy.sh` with the phone connected) → builds. Device check list (state results honestly, mark what was not exercised): daily item missed 2+ days shows first-miss date + "N days overdue"; ticking it leaves no second row and no resurfacing next day; completed row shows "done <date>" when late; detail sheet History renders counts.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(ios): days-overdue label, done note and history section; docs"`

---

## Self-Review

- **Spec coverage:** §1 first miss/daily/fold/label → Task 2 + row in Task 5; §2 resolve set + idempotency → Task 3; §3 data → Task 1 (+stamping Task 3, pending path via `completeReminder` default `now`); §4 history + row note → Tasks 4, 5; §5 testing → each task. Out of scope items untouched.
- **Types:** `completedAt`, `seriesID`, `recordedAt`, `daysOverdue(today:)`, `OverdueLabel.text`, `CompletionHistory.forReminder/forEvent`, `completionNote` are named identically across tasks.
- **Known risk:** Task 3 flips several existing test expectations; the implementer must re-derive values from the rule, not loosen assertions.
