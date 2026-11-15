// ios/Tests/StarkKitTests/ItemRepositoryContractTests.swift
import Testing
import Foundation
@testable import StarkKit

/// What a contract run needs from an implementation: the repository, one writable event calendar,
/// one writable reminder list, one read-only calendar, and a way to count stored items.
struct RepositoryHarness {
    let repository: any ItemRepository
    let calendarID: String
    let listID: String
    let readOnlyCalendarID: String
    let itemCount: @Sendable () async -> Int
    /// The repository's clock reading (what "now" is for completions). A real implementation passes `Date()`.
    let now: Date
    /// Every stored reminder, including completed copies (`Reminder.id` is the identifier).
    let reminders: @Sendable () async -> [Reminder]
    /// Moves one occurrence of an event series (`original` is its occurrence date) to `newStart`,
    /// as Apple Calendar's "this event only" edit does, and returns the detached occurrence's own
    /// ref (EventKit: the series id plus `/RID=`). A detached occurrence keeps its ORIGINAL date.
    let detachOccurrence: @Sendable (_ series: AppleItemRef, _ original: Date, _ newStart: Date) async throws -> AppleItemRef
    /// The start of every occurrence of the series in `range` (a detached one at its new start), sorted.
    let eventStarts: @Sendable (_ series: AppleItemRef, _ range: ClosedRange<Date>) async -> [Date]
}

/// The behaviour every `ItemRepository` must have. Task 6 runs the same checks against the
/// EventKit implementation by passing its own factory.
enum ItemRepositoryContract {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let daily = RecurrenceRule(frequency: .daily)

    static func addGetRoundTrip(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let new = NewEvent(title: "Lunch", notes: "n", start: start, end: start.addingTimeInterval(3600),
                           location: "Cafe", url: "https://example.com")
        let ref = try await h.repository.addEvent(new, calendarID: h.calendarID)
        let event = try #require(try await h.repository.details(ref).event)
        #expect(event.title == "Lunch")
        #expect(event.notes == "n")
        #expect(event.location == "Cafe")
        #expect(event.url == "https://example.com")
        #expect(event.start == start)
        #expect(event.end == start.addingTimeInterval(3600))
        #expect(event.recurrence == nil)

        let rref = try await h.repository.addReminder(
            NewReminder(title: "Call", due: start, dueHasTime: false, priority: 1, url: "https://r.example"),
            listID: h.listID)
        let d = try await h.repository.details(rref)
        #expect(d.reminder?.title == "Call")
        // Date-only drops the time of day: EventKit stores day components, so it reads back as
        // local midnight (Stark's own date-only marker).
        #expect(d.reminder?.dueDate == Calendar.current.startOfDay(for: start))
        #expect(d.reminder?.priority == 1)
        #expect(d.dueHasTime == false)
        #expect(d.reminderURL == "https://r.example")
        #expect(d.isWritable)
        #expect(d.calendarID == h.listID)
    }

    static func patchChangesOnlyPatchedFields(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let ref = try await h.repository.addEvent(
            NewEvent(title: "Gym", notes: "n", start: start, end: start.addingTimeInterval(3600),
                     location: "Home", recurrence: daily), calendarID: h.calendarID)
        try await h.repository.update(ref, event: EventPatch(title: "Gym 2", location: .clear))
        let e = try #require(try await h.repository.details(ref).event)
        #expect(e.title == "Gym 2")
        #expect(e.location == nil)
        #expect(e.notes == "n")
        #expect(e.start == start)
        #expect(e.end == start.addingTimeInterval(3600))
        #expect(e.recurrence == daily)

        let rref = try await h.repository.addReminder(
            NewReminder(title: "Pay", notes: "x", due: start, priority: 5, recurrence: daily), listID: h.listID)
        try await h.repository.update(rref, reminder: ReminderPatch(priority: .set(1)))
        let r = try #require(try await h.repository.details(rref).reminder)
        #expect(r.title == "Pay")
        #expect(r.notes == "x")
        #expect(r.priority == 1)
        #expect(r.dueDate == start)
        #expect(r.recurrence == daily)
    }

    static func clearRemovesRecurrence(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let ref = try await h.repository.addEvent(
            NewEvent(title: "Gym", start: start, recurrence: daily), calendarID: h.calendarID)
        try await h.repository.update(ref, event: EventPatch(recurrence: .clear))
        #expect(try await h.repository.details(ref).event?.recurrence == nil)
        try await h.repository.update(ref, event: EventPatch(recurrence: .set(RecurrenceRule(frequency: .weekly))))
        #expect(try await h.repository.details(ref).event?.recurrence?.frequency == .weekly)
    }

    static func deleteWholeSeries(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let ref = try await h.repository.addEvent(
            NewEvent(title: "Gym", start: start, recurrence: daily), calendarID: h.calendarID)
        try await h.repository.delete(ref)
        await #expect(throws: ItemRepositoryError.notFound) { _ = try await h.repository.details(ref) }
        await #expect(throws: ItemRepositoryError.notFound) { try await h.repository.delete(ref) }
    }

    static func deleteOccurrenceKeepsOthers(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let ref = try await h.repository.addEvent(
            NewEvent(title: "Gym", start: start, recurrence: daily), calendarID: h.calendarID)
        let second = start.addingTimeInterval(86_400)
        try await h.repository.deleteOccurrence(ref, on: second)
        // Read from the store's own occurrences: `details` carries no exception dates for Apple.
        let occurrences = await h.eventStarts(ref, start...start.addingTimeInterval(3 * 86_400))
        #expect(occurrences.contains(start))
        #expect(!occurrences.contains(second))
        #expect(occurrences.contains(start.addingTimeInterval(2 * 86_400)))
    }

    /// Deleting a detached occurrence by its own ref removes exactly that occurrence. It keeps its
    /// original date, so matching by the tapped day would delete the series' regular occurrence on
    /// the day it was moved to (daily series) and leave the tapped one.
    static func deleteOccurrenceRemovesTheTappedDetachedOne(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let ref = try await h.repository.addEvent(
            NewEvent(title: "Standup", start: start, end: start.addingTimeInterval(1800),
                     recurrence: RecurrenceRule(frequency: .daily, count: 5)), calendarID: h.calendarID)
        let day = 86_400.0
        // The second occurrence moves onto the third one's day, an hour earlier (the same local
        // day as the third in every zone from UTC-10 to UTC+14 for `start`).
        let moved = start.addingTimeInterval(2 * day - 3600)
        let detached = try await h.detachOccurrence(ref, start.addingTimeInterval(day), moved)
        #expect(detached.identifier != ref.identifier)
        let window = start.addingTimeInterval(-3600)...start.addingTimeInterval(6 * day)
        let before = await h.eventStarts(ref, window)
        #expect(before == [start, moved, start.addingTimeInterval(2 * day), start.addingTimeInterval(3 * day),
                           start.addingTimeInterval(4 * day)])

        try await h.repository.deleteOccurrence(detached, on: moved)
        let after = await h.eventStarts(ref, window)
        #expect(after == [start, start.addingTimeInterval(2 * day), start.addingTimeInterval(3 * day),
                          start.addingTimeInterval(4 * day)])
    }

    /// A detached occurrence's id that no longer matches (already deleted, or reissued by a sync)
    /// is not found: it never falls back to the day match, which would delete the series' regular
    /// occurrence on that day.
    static func deleteOccurrenceWithAStaleDetachedIDIsNotFound(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let ref = try await h.repository.addEvent(
            NewEvent(title: "Standup", start: start, end: start.addingTimeInterval(1800),
                     recurrence: RecurrenceRule(frequency: .daily, count: 5)), calendarID: h.calendarID)
        let day = 86_400.0
        let moved = start.addingTimeInterval(2 * day - 3600)
        let detached = try await h.detachOccurrence(ref, start.addingTimeInterval(day), moved)
        try await h.repository.deleteOccurrence(detached, on: moved)
        let window = start.addingTimeInterval(-3600)...start.addingTimeInterval(6 * day)
        let before = await h.eventStarts(ref, window)

        await #expect(throws: ItemRepositoryError.notFound) {
            try await h.repository.deleteOccurrence(detached, on: moved)
        }
        #expect(await h.eventStarts(ref, window) == before)
        #expect(before.contains(start.addingTimeInterval(2 * day)))
    }

    static func completeAndUncompleteOneOff(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let ref = try await h.repository.addReminder(NewReminder(title: "Call", due: start), listID: h.listID)
        try await h.repository.complete(ref, on: start)
        #expect(try await h.repository.details(ref).reminder?.isCompleted == true)
        try await h.repository.uncomplete(ref)
        #expect(try await h.repository.details(ref).reminder?.isCompleted == false)
    }

    static func batchFailureRollsBack(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let before = await h.itemCount()
        await #expect(throws: ItemRepositoryError.notWritable) {
            _ = try await h.repository.addBatch(
                events: [(NewEvent(title: "A", start: start), h.calendarID),
                         (NewEvent(title: "B", start: start), h.readOnlyCalendarID)],
                reminders: [(NewReminder(title: "C", due: start), h.listID)])
        }
        #expect(await h.itemCount() == before)
        let refs = try await h.repository.addBatch(
            events: [(NewEvent(title: "A", start: start), h.calendarID)],
            reminders: [(NewReminder(title: "C", due: start), h.listID)])
        #expect(refs.count == 2)
        #expect(await h.itemCount() == before + 2)
    }

    /// One ref per item, in input order, events first (the bridge ledgers items by position).
    static func batchReturnsRefsInInputOrder(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let refs = try await h.repository.addBatch(
            events: [(NewEvent(title: "E1", start: start), h.calendarID),
                     (NewEvent(title: "E2", start: start), h.calendarID)],
            reminders: [(NewReminder(title: "R1", due: start), h.listID),
                        (NewReminder(title: "R2", due: start), h.listID)])
        #expect(refs.map(\.kind) == [.event, .event, .reminder, .reminder])
        var titles: [String] = []
        for ref in refs {
            let d = try await h.repository.details(ref)
            titles.append(d.event?.title ?? d.reminder?.title ?? "?")
        }
        #expect(titles == ["E1", "E2", "R1", "R2"])
    }

    /// A later item fails after earlier ones were already saved (uncommitted): nothing stays.
    static func batchFailureOfALaterItemRollsBack(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let before = await h.itemCount()
        await #expect(throws: ItemRepositoryError.self) {
            _ = try await h.repository.addBatch(
                events: [(NewEvent(title: "Saved first", start: start), h.calendarID)],
                reminders: [(NewReminder(title: "Fine", due: start), h.listID),
                            (NewReminder(title: "No due", recurrence: daily), h.listID)])
        }
        #expect(await h.itemCount() == before)
    }

    // MARK: Recurring completion (EventKit spike facts, section (a))

    private static let cal = Calendar.current

    private static func shifted(_ date: Date, days: Int) -> Date {
        cal.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// The open master plus every other reminder with the same title (the completed copies).
    private static func copies(of ref: AppleItemRef, in h: RepositoryHarness) async throws -> [Reminder] {
        let title = try #require(try await h.repository.details(ref).reminder).title
        return await h.reminders().filter { $0.title == title && $0.id != ref.identifier }
    }

    private static func expectAdvanced(_ h: RepositoryHarness, _ ref: AppleItemRef, from oldDue: Date, to newDue: Date,
                                       dueHasTime: Bool = true) async throws {
        let master = try #require(try await h.repository.details(ref))
        let r = try #require(master.reminder)
        #expect(r.id == ref.identifier)          // same identifier stays open
        #expect(r.isCompleted == false)
        #expect(r.dueDate == newDue)
        #expect(r.recurrence != nil)
        #expect(master.dueHasTime == dueHasTime)
        let copies = try await copies(of: ref, in: h)
        #expect(copies.count == 1)               // a SEPARATE completed copy
        let copy = try #require(copies.first)
        #expect(copy.id != ref.identifier)
        #expect(copy.isCompleted)
        #expect(copy.dueDate == oldDue)
        #expect(copy.recurrence == nil)
    }

    static func completingDailyAdvancesPastNow(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        // Due two days ago an hour before now: today's occurrence already passed, so next is due + 3 days.
        let due = shifted(h.now.addingTimeInterval(-3600), days: -2)
        let ref = try await h.repository.addReminder(
            NewReminder(title: "Daily", due: due, recurrence: RecurrenceRule(frequency: .daily)), listID: h.listID)
        try await h.repository.complete(ref, on: h.now)
        try await expectAdvanced(h, ref, from: due, to: shifted(due, days: 3))
    }

    static func completingWeeklyAdvancesAWeek(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let due = shifted(h.now.addingTimeInterval(-3600), days: -2)
        let ref = try await h.repository.addReminder(
            NewReminder(title: "Weekly", due: due, recurrence: RecurrenceRule(frequency: .weekly)), listID: h.listID)
        try await h.repository.complete(ref, on: h.now)
        try await expectAdvanced(h, ref, from: due, to: shifted(due, days: 7))
    }

    static func completingUsesLaterOfDueAndNow(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        // now is later than due, same day: next daily occurrence is tomorrow.
        let past = h.now.addingTimeInterval(-5 * 3600)
        let a = try await h.repository.addReminder(
            NewReminder(title: "Earlier today", due: past, recurrence: RecurrenceRule(frequency: .daily)),
            listID: h.listID)
        try await h.repository.complete(a, on: h.now)
        try await expectAdvanced(h, a, from: past, to: shifted(past, days: 1))
        // due in the future: the next one is after the old due date, not after now.
        let future = shifted(h.now, days: 6)
        let b = try await h.repository.addReminder(
            NewReminder(title: "Next week", due: future, recurrence: RecurrenceRule(frequency: .weekly)),
            listID: h.listID)
        try await h.repository.complete(b, on: future)
        try await expectAdvanced(h, b, from: future, to: shifted(future, days: 7))
    }

    static func completingDateOnlyTreatsTodayAsPassed(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let due = cal.startOfDay(for: shifted(h.now, days: -2))
        let ref = try await h.repository.addReminder(
            NewReminder(title: "Date only", due: due, dueHasTime: false,
                        recurrence: RecurrenceRule(frequency: .daily)), listID: h.listID)
        try await h.repository.complete(ref, on: h.now)
        // Today's midnight is behind now, so the next occurrence is tomorrow's date, still date-only.
        try await expectAdvanced(h, ref, from: due, to: cal.startOfDay(for: shifted(h.now, days: 1)),
                                 dueHasTime: false)
    }

    static func completingCountLimitedSeriesCountsDown(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let due = shifted(h.now.addingTimeInterval(-3600), days: -1)
        let ref = try await h.repository.addReminder(
            NewReminder(title: "Twice", due: due, recurrence: RecurrenceRule(frequency: .daily, count: 2)),
            listID: h.listID)
        try await h.repository.complete(ref, on: h.now)
        let first = try #require(try await h.repository.details(ref).reminder)
        #expect(first.isCompleted == false)
        #expect(first.recurrence?.count == 1)
        #expect(try await copies(of: ref, in: h).count == 1)
        // The caller completes the occurrence it shows: the series' current due date.
        try await h.repository.complete(ref, on: try #require(first.dueDate))
        let last = try #require(try await h.repository.details(ref).reminder)
        #expect(last.isCompleted)                // none left: the reminder itself completes
        #expect(try await copies(of: ref, in: h).count == 1)  // no extra copy
    }

    static func completingUntilExhaustedCompletesItself(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        // Built from the start of today with fixed hours, so the outcome is the same at any time of
        // day (a `now - 1h` due fell on yesterday in the first hour of the day). Due 09:00 two days
        // ago, repeating daily until yesterday (noon; EventKit stores the end of that day): every
        // occurrence up to UNTIL is already behind now, the next one (today 09:00) is after it.
        let today = cal.startOfDay(for: h.now)
        let due = try #require(cal.date(bySettingHour: 9, minute: 0, second: 0, of: shifted(today, days: -2)))
        let until = try #require(cal.date(bySettingHour: 12, minute: 0, second: 0, of: shifted(today, days: -1)))
        let rule = RecurrenceRule(frequency: .daily, until: until)
        let ref = try await h.repository.addReminder(NewReminder(title: "Until", due: due, recurrence: rule),
                                                     listID: h.listID)
        try await h.repository.complete(ref, on: h.now)
        let r = try #require(try await h.repository.details(ref).reminder)
        #expect(r.isCompleted)
        #expect(try await copies(of: ref, in: h).isEmpty)
    }

    /// The repetition guard (`complete` ignores a date before a series' current due day) is for
    /// repeating reminders only: a one-off completes whatever `date` it is given.
    static func completingAOneOffIgnoresTheDate(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let due = try #require(cal.date(bySettingHour: 9, minute: 0, second: 0, of: shifted(cal.startOfDay(for: h.now), days: 3)))
        for (title, date) in [("One-off earlier", shifted(due, days: -5)), ("One-off later", shifted(due, days: 4)),
                              ("One-off same", due)] {
            let ref = try await h.repository.addReminder(NewReminder(title: title, due: due), listID: h.listID)
            try await h.repository.complete(ref, on: date)
            let r = try #require(try await h.repository.details(ref).reminder)
            #expect(r.isCompleted, "\(title)")
            #expect(r.dueDate == due, "\(title)")
            #expect(try await copies(of: ref, in: h).isEmpty, "\(title)")
        }
    }

    /// A second completion of the same occurrence (double tap, the checkbox timer firing after
    /// Done) does nothing: the series has already moved past that day.
    static func completingTheSameOccurrenceTwiceCompletesOnce(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        let due = shifted(h.now.addingTimeInterval(-3600), days: -2)
        let ref = try await h.repository.addReminder(
            NewReminder(title: "Twice tapped", due: due, recurrence: RecurrenceRule(frequency: .daily)),
            listID: h.listID)
        try await h.repository.complete(ref, on: due)
        try await h.repository.complete(ref, on: due)
        try await expectAdvanced(h, ref, from: due, to: shifted(due, days: 3))
    }

    static func notWritableCalendarThrows(_ make: () async -> RepositoryHarness) async throws {
        let h = await make()
        await #expect(throws: ItemRepositoryError.notWritable) {
            _ = try await h.repository.addEvent(NewEvent(title: "X", start: start), calendarID: h.readOnlyCalendarID)
        }
        let writable = try await h.repository.writableCalendars()
        #expect(writable.contains { $0.id == h.calendarID })
        #expect(!writable.contains { $0.id == h.readOnlyCalendarID })
    }
}

@Suite("ItemRepository contract (fake)")
struct FakeItemRepositoryContractTests {
    static let calendars = [
        AppleCalendarInfo(id: "cal", title: "Home", accountName: "iCloud", colorHex: nil, isReminderList: false),
        AppleCalendarInfo(id: "ro", title: "Holidays", accountName: "Subscribed", colorHex: nil, isReminderList: false),
        AppleCalendarInfo(id: "list", title: "Reminders", accountName: "iCloud", colorHex: nil, isReminderList: true),
    ]

    static func make() -> RepositoryHarness {
        let fake = FakeItemRepository(calendars: calendars, readOnlyCalendarIDs: ["ro"],
                                      now: { ItemRepositoryContract.start })
        return RepositoryHarness(repository: fake, calendarID: "cal", listID: "list", readOnlyCalendarID: "ro",
                                 itemCount: { await fake.itemCount }, now: ItemRepositoryContract.start,
                                 reminders: { await fake.allReminders },
                                 detachOccurrence: { try await fake.detachOccurrence($0, originalDate: $1, to: $2) },
                                 eventStarts: { await fake.occurrenceStarts(of: $0, in: $1) })
    }

    @Test func addGetRoundTrip() async throws { try await ItemRepositoryContract.addGetRoundTrip(Self.make) }
    @Test func patchChangesOnlyPatchedFields() async throws {
        try await ItemRepositoryContract.patchChangesOnlyPatchedFields(Self.make)
    }
    @Test func clearRemovesRecurrence() async throws { try await ItemRepositoryContract.clearRemovesRecurrence(Self.make) }
    @Test func deleteWholeSeries() async throws { try await ItemRepositoryContract.deleteWholeSeries(Self.make) }
    @Test func deleteOccurrenceKeepsOthers() async throws {
        try await ItemRepositoryContract.deleteOccurrenceKeepsOthers(Self.make)
    }
    @Test func deleteOccurrenceRemovesTheTappedDetachedOne() async throws {
        try await ItemRepositoryContract.deleteOccurrenceRemovesTheTappedDetachedOne(Self.make)
    }
    @Test func deleteOccurrenceWithAStaleDetachedIDIsNotFound() async throws {
        try await ItemRepositoryContract.deleteOccurrenceWithAStaleDetachedIDIsNotFound(Self.make)
    }
    @Test func completeAndUncompleteOneOff() async throws {
        try await ItemRepositoryContract.completeAndUncompleteOneOff(Self.make)
    }
    @Test func batchFailureRollsBack() async throws { try await ItemRepositoryContract.batchFailureRollsBack(Self.make) }
    @Test func completingDailyAdvancesPastNow() async throws {
        try await ItemRepositoryContract.completingDailyAdvancesPastNow(Self.make)
    }
    @Test func completingWeeklyAdvancesAWeek() async throws {
        try await ItemRepositoryContract.completingWeeklyAdvancesAWeek(Self.make)
    }
    @Test func completingUsesLaterOfDueAndNow() async throws {
        try await ItemRepositoryContract.completingUsesLaterOfDueAndNow(Self.make)
    }
    @Test func completingDateOnlyTreatsTodayAsPassed() async throws {
        try await ItemRepositoryContract.completingDateOnlyTreatsTodayAsPassed(Self.make)
    }
    @Test func completingCountLimitedSeriesCountsDown() async throws {
        try await ItemRepositoryContract.completingCountLimitedSeriesCountsDown(Self.make)
    }
    @Test func completingUntilExhaustedCompletesItself() async throws {
        try await ItemRepositoryContract.completingUntilExhaustedCompletesItself(Self.make)
    }
    @Test func completingAOneOffIgnoresTheDate() async throws {
        try await ItemRepositoryContract.completingAOneOffIgnoresTheDate(Self.make)
    }
    @Test func batchReturnsRefsInInputOrder() async throws {
        try await ItemRepositoryContract.batchReturnsRefsInInputOrder(Self.make)
    }
    @Test func notWritableCalendarThrows() async throws {
        try await ItemRepositoryContract.notWritableCalendarThrows(Self.make)
    }
    @Test func batchFailureOfALaterItemRollsBack() async throws {
        try await ItemRepositoryContract.batchFailureOfALaterItemRollsBack(Self.make)
    }
    @Test func completingTheSameOccurrenceTwiceCompletesOnce() async throws {
        try await ItemRepositoryContract.completingTheSameOccurrenceTwiceCompletesOnce(Self.make)
    }
}

@Suite("FakeItemRepository (EventKit semantics)")
struct FakeItemRepositorySemanticsTests {
    private let start = ItemRepositoryContract.start
    private var h: RepositoryHarness { FakeItemRepositoryContractTests.make() }

    @Test func failNextThrowsOnceAndChangesNothing() async throws {
        let fake = FakeItemRepository(calendars: FakeItemRepositoryContractTests.calendars)
        await fake.failNext("disk full")
        await #expect(throws: ItemRepositoryError.saveFailed("disk full")) {
            _ = try await fake.addEvent(NewEvent(title: "X", start: start), calendarID: "cal")
        }
        #expect(await fake.itemCount == 0)
        _ = try await fake.addEvent(NewEvent(title: "X", start: start), calendarID: "cal")
        #expect(await fake.itemCount == 1)
    }

    @Test func detailsOfUnknownRefIsNotFound() async throws {
        await #expect(throws: ItemRepositoryError.notFound) {
            _ = try await h.repository.details(AppleItemRef(kind: .event, identifier: "nope"))
        }
    }

    @Test func recurringReminderWithoutDueIsUnrepresentable() async throws {
        let h = h
        await #expect(throws: ItemRepositoryError.self) {
            _ = try await h.repository.addReminder(
                NewReminder(title: "x", recurrence: RecurrenceRule(frequency: .daily)), listID: h.listID)
        }
    }
}

@Suite("AppleItemRef")
struct AppleItemRefTests {
    private let occ = Date(timeIntervalSince1970: 1_800_000_000)
    private let source = AppleSource(calendarID: "c", calendarTitle: "C", colorHex: nil, isReminder: false)

    @Test func parsesEventRowIDBuiltByMerge() {
        let event = Event(id: "apple-AB12-CD34:xyz", title: "t", start: occ)
        let item = AgendaItem(kind: .event(event), occurrence: occ, displayDate: occ, isOverdue: false,
                              appleSource: source)
        #expect(AppleItemRef.ref(for: item) == AppleItemRef(kind: .event, identifier: "AB12-CD34:xyz"))
    }

    @Test func parsesReminderRowIDAndPlanSuffix() {
        let reminder = Reminder(id: "apple-9F-8E", title: "t", dueDate: occ)
        let item = AgendaItem(kind: .reminder(reminder), occurrence: occ, displayDate: occ, isOverdue: false,
                              appleSource: source)
        #expect(AppleItemRef.ref(for: item) == AppleItemRef(kind: .reminder, identifier: "9F-8E"))
        #expect(AppleItemRef(agendaItemID: item.id + "-plan-abc", kind: .reminder)?.identifier == "9F-8E")
    }

    @Test func nilForStarkItems() {
        let event = Event(title: "t", start: occ)
        let item = AgendaItem(kind: .event(event), occurrence: occ, displayDate: occ, isOverdue: false)
        #expect(AppleItemRef.ref(for: item) == nil)
        #expect(AppleItemRef(agendaItemID: item.id, kind: .event) == nil)
        #expect(AppleItemRef(agendaItemID: "apple-", kind: .event) == nil)
        #expect(AppleItemRef(agendaItemID: "apple-ID-notanumber", kind: .event) == nil)
    }
}
