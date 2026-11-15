// ios/Tests/StarkKitTests/AppleWriteFixRoundTests.swift
import Testing
import Foundation
@testable import StarkKit

/// Task 9a review fixes: convert refused for repeats Stark can't represent, refs from the model
/// id, URL kept on convert, uncomplete of a series' completed copy is a notice only, Search
/// collapses Apple event series.
@Suite("AppleWriteFixRound")
struct AppleWriteFixRoundTests {
    private let when = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let list = AppleCalendarInfo(id: "l1", title: "Home", accountName: "iCloud", colorHex: nil, isReminderList: true)
    private let cal = AppleCalendarInfo(id: "c1", title: "Work", accountName: "iCloud", colorHex: nil, isReminderList: false)

    // MARK: 1. Convert refused for an unrepresentable repeat

    @Test("an item whose repeat Stark can't represent can't be converted; completed reminders can't either")
    func canConvert() {
        let event = Event(id: "apple-E", title: "Gym", start: when)
        #expect(ItemDetails(event: event, calendarID: "c1").canConvert)
        #expect(!ItemDetails(event: event, calendarID: "c1", hasUnrepresentableRepeat: true).canConvert)
        let open = Reminder(id: "apple-R", title: "Milk")
        #expect(ItemDetails(reminder: open, calendarID: "l1").canConvert)
        #expect(!ItemDetails(reminder: open, calendarID: "l1", hasUnrepresentableRepeat: true).canConvert)
        let done = Reminder(id: "apple-R", title: "Milk", isCompleted: true)
        #expect(!ItemDetails(reminder: done, calendarID: "l1").canConvert)
        #expect(ItemDetails.unconvertibleReason.isEmpty == false)
    }

    // MARK: 2. Refs from the model id

    @Test("an undated Apple reminder row (.distantPast) with a dashed identifier routes by its model id")
    func refFromModelID() {
        let source = AppleSource(calendarID: "l1", calendarTitle: "Home", colorHex: nil, isReminder: true)
        let undated = AgendaItem(kind: .reminder(Reminder(id: "apple-AB-12-CD", title: "Someday")),
                                 occurrence: .distantPast, displayDate: .distantPast, isOverdue: false,
                                 appleSource: source)
        #expect(AppleItemRef.ref(for: undated) == AppleItemRef(kind: .reminder, identifier: "AB-12-CD"))
        let eventSource = AppleSource(calendarID: "c1", calendarTitle: "Work", colorHex: nil, isReminder: false)
        let detached = AgendaItem(kind: .event(Event(id: "apple-SRC:EXT-1/RID=816530400", title: "Standup", start: when)),
                                  occurrence: when, displayDate: when, isOverdue: false, appleSource: eventSource)
        #expect(AppleItemRef.ref(for: detached) == AppleItemRef(kind: .event, identifier: "SRC:EXT-1/RID=816530400"))
        // The row-id parser still works for its callers.
        #expect(AppleItemRef(agendaItemID: "apple-AB-12-\(800_000_000.0)", kind: .reminder)?.identifier == "AB-12")
        // A Stark row has no ref.
        let stark = AgendaItem(kind: .reminder(Reminder(id: "r1", title: "x")), occurrence: when, displayDate: when,
                               isOverdue: false)
        #expect(AppleItemRef.ref(for: stark) == nil)
    }

    // MARK: 3. URL kept on convert

    @Test("converting an Apple reminder keeps its URL on the event unless one was typed")
    func reminderURLToEvent() {
        #expect(ItemConversion.eventURL(typed: "  ", storedReminderURL: "https://a.example") == "https://a.example")
        #expect(ItemConversion.eventURL(typed: " https://b.example ", storedReminderURL: "https://a.example")
            == "https://b.example")
        #expect(ItemConversion.eventURL(typed: "", storedReminderURL: nil) == nil)
    }

    @Test("converting an Apple event keeps its URL as the reminder's URL, not in the notes; location still goes to notes")
    func eventURLToReminder() {
        let event = Event(id: "apple-E", title: "Review", notes: "agenda", start: when, location: "Room 2",
                          url: "https://c.example")
        let (reminder, url) = ItemConversion.appleReminder(from: event)
        #expect(url == "https://c.example")
        #expect(reminder.notes == "agenda\n\nLocation: Room 2")
        #expect(reminder.title == "Review")
    }

    // MARK: 4. Uncomplete of a series' completed copy is a notice only

    private func appleRow(_ id: String, title: String = "Water plants", due: Date, completed: Bool,
                          listID: String = "l1") -> AgendaItem {
        AgendaItem(kind: .reminder(Reminder(id: "apple-\(id)", title: title, dueDate: due, isCompleted: completed)),
                   occurrence: due, displayDate: due, isOverdue: false,
                   appleSource: AppleSource(calendarID: listID, calendarTitle: "Home", colorHex: nil, isReminder: true))
    }

    private func series(_ id: String = "M1", title: String = "Water plants", due: Date, recurring: Bool = true,
                        completed: Bool = false) -> AppleReminder {
        AppleReminder(id: id, title: title, notes: nil, due: due, dueHasTime: false, isCompleted: completed,
                      completedAt: nil, priority: nil, calendar: list, isRecurring: recurring)
    }

    @Test("a completed copy of a repeating Apple reminder (other id, earlier due, same title and list) is a no-op with a notice")
    func copyIsNoticeOnly() {
        let copy = appleRow("C1", due: when, completed: true)
        let snapshot = AppleSnapshot(events: [], reminders: [series(due: when.addingTimeInterval(86_400))])
        let text = UncompleteNotice.text(for: copy, snapshot: snapshot)
        #expect(text?.contains("nothing was changed") == true)
    }

    @Test("no notice (so a normal uncomplete) for a one-off, another list, the series itself, a later due, a Stark item")
    func noNoticeCases() {
        let later = when.addingTimeInterval(86_400)
        let copy = appleRow("C1", due: when, completed: true)
        // Same title in the list but the other reminder doesn't repeat.
        #expect(UncompleteNotice.text(for: copy, snapshot: AppleSnapshot(events: [], reminders: [series(due: later, recurring: false)])) == nil)
        // Another list.
        #expect(UncompleteNotice.text(for: appleRow("C1", due: when, completed: true, listID: "other"),
                                      snapshot: AppleSnapshot(events: [], reminders: [series(due: later)])) == nil)
        // The matched series is the item itself (a series that ended completes itself).
        #expect(UncompleteNotice.text(for: appleRow("M1", due: when, completed: true),
                                      snapshot: AppleSnapshot(events: [], reminders: [series(due: later)])) == nil)
        // The completed one is not older than the series' current due date: not a copy of it.
        #expect(UncompleteNotice.text(for: appleRow("C1", due: later, completed: true),
                                      snapshot: AppleSnapshot(events: [], reminders: [series(due: when)])) == nil)
        // An open item, and a Stark item.
        #expect(UncompleteNotice.text(for: appleRow("C1", due: when, completed: false),
                                      snapshot: AppleSnapshot(events: [], reminders: [series(due: later)])) == nil)
        let stark = AgendaItem(kind: .reminder(Reminder(id: "r1", title: "Water plants", dueDate: when, isCompleted: true)),
                               occurrence: when, displayDate: when, isOverdue: false)
        #expect(UncompleteNotice.text(for: stark, snapshot: AppleSnapshot(events: [], reminders: [series(due: later)])) == nil)
    }

    // MARK: 5. Search collapses Apple event series

    private func occurrence(_ id: String, title: String = "Standup", dayOffset: Int) -> AppleCalendarEvent {
        let start = when.addingTimeInterval(Double(dayOffset) * 86_400)
        return AppleCalendarEvent(id: id, title: title, notes: nil, location: nil, url: nil, start: start,
                                  end: start.addingTimeInterval(3600), isAllDay: false, calendar: cal)
    }

    @Test("a daily Apple series is one Search row: the nearest occurrence at or after today")
    func dailySeriesOneRow() {
        let events = (-5...5).map { occurrence("S:E1", dayOffset: $0) }
        let results = SearchResults.find(events: [], reminders: [], apple: AppleSnapshot(events: events, reminders: []),
                                         query: "stand", today: when.addingTimeInterval(1800))
        #expect(results.count == 1)
        #expect(results.first?.occurrence == when.addingTimeInterval(86_400))
    }

    @Test("a series entirely in the past shows its latest occurrence; a detached occurrence belongs to its series")
    func pastSeriesLatest() {
        var events = (-10 ... -3).map { occurrence("S:E2", dayOffset: $0) }
        events.append(occurrence("S:E2/RID=816000000", dayOffset: -2))
        let results = SearchResults.find(events: [], reminders: [], apple: AppleSnapshot(events: events, reminders: []),
                                         query: "stand", today: when)
        #expect(results.count == 1)
        #expect(results.first?.occurrence == when.addingTimeInterval(-2 * 86_400))
    }

    @Test("two series with the same title stay two rows; local results are unchanged")
    func twoSeriesTwoRows() {
        let events = [occurrence("S:A", dayOffset: 1), occurrence("S:A", dayOffset: 2),
                      occurrence("S:B", dayOffset: 1), occurrence("S:B", dayOffset: 3)]
        let local = Event(id: "e1", title: "Standup notes", start: when)
        let results = SearchResults.find(events: [local], reminders: [], apple: AppleSnapshot(events: events, reminders: []),
                                         query: "stand", today: when)
        #expect(results.count == 3)
        #expect(results.filter { $0.appleSource == nil }.map(\.id) == [AgendaItem(kind: .event(local), occurrence: when,
                                                                                    displayDate: when, isOverdue: false).id])
    }
}
