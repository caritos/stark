import Testing
import Foundation
@testable import StarkKit

/// Tag autocomplete and Search over Apple items (spec Decision 10: the caller passes events
/// within two years either side of today and all reminders, undated included).
struct AppleTagsSearchTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    var today: Date { at(2026, 11, 15, 10) }
    let work = AppleCalendarInfo(id: "C1", title: "Work", accountName: "iCloud", colorHex: nil, isReminderList: false)
    let inbox = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)

    func event(_ id: String, _ title: String, notes: String? = nil, start: Date) -> AppleCalendarEvent {
        AppleCalendarEvent(id: id, title: title, notes: notes, location: nil, url: nil, start: start,
                           end: start.addingTimeInterval(3600), isAllDay: false, calendar: work)
    }
    func reminder(_ id: String, _ title: String, notes: String? = nil, due: Date? = nil) -> AppleReminder {
        AppleReminder(id: id, title: title, notes: notes, due: due, dueHasTime: false, isCompleted: false,
                      completedAt: nil, priority: nil, calendar: inbox)
    }

    // MARK: Tags

    @Test func suggestionsIncludeTagsUsedOnlyInAppleTitlesAndNotes() {
        let local = Reminder(id: "l", title: "Draft +garden plan")
        let apple = AppleSnapshot(events: [event("e1", "Sync +gamma", notes: "with ~sophia", start: at(2026, 11, 16, 9))],
                                  reminders: [reminder("r1", "Order +gardenbeds", notes: "see +garage list")])
        let prefix = TagAutocomplete.Prefix(sigil: "+", partial: "+ga")
        #expect(TagAutocomplete.suggestions(for: prefix, events: [], reminders: [local], apple: apple)
                == ["+gamma", "+garage", "+garden", "+gardenbeds"])
        #expect(TagAutocomplete.suggestions(for: .init(sigil: "~", partial: "~s"), events: [], reminders: [], apple: apple)
                == ["~sophia"])
    }

    @Test func emptySnapshotKeepsLocalSuggestions() {
        let local = Reminder(id: "l", title: "Draft +garden plan")
        let prefix = TagAutocomplete.Prefix(sigil: "+", partial: "+g")
        #expect(TagAutocomplete.suggestions(for: prefix, events: [], reminders: [local], apple: .empty)
                == TagAutocomplete.suggestions(for: prefix, events: [], reminders: [local]))
    }

    // MARK: Search

    @Test func searchFindsAnUndatedAppleReminder() {
        let apple = AppleSnapshot(events: [], reminders: [reminder("u1", "Call the bank")])
        let found = SearchResults.find(events: [], reminders: [], apple: apple, query: "bank", today: today)
        #expect(found.map(\.title) == ["Call the bank"])
        #expect(found.first?.appleSource?.isReminder == true)
        guard case .reminder(let r)? = found.first?.kind else { Issue.record("not a reminder"); return }
        #expect(r.id == "apple-u1" && r.dueDate == nil)
    }

    @Test func searchFindsAnAppleEventEighteenMonthsAhead() {
        let start = at(2028, 5, 15, 9)
        let apple = AppleSnapshot(events: [event("e1", "Conference keynote", start: start)], reminders: [])
        let found = SearchResults.find(events: [], reminders: [], apple: apple, query: "keynote", today: today)
        #expect(found.map(\.title) == ["Conference keynote"])
        #expect(found.first?.occurrence == start)
    }

    @Test func searchAppleRowsCarryTheFullSource() {
        let list = AppleCalendarInfo(id: "L9", title: "Shared", accountName: "iCloud", colorHex: "#123456",
                                     isReminderList: true, isWritable: false)
        let r = AppleReminder(id: "r9", title: "Tickets", notes: nil, due: nil, dueHasTime: false, isCompleted: false,
                              completedAt: nil, priority: nil, calendar: list, url: "https://example.com/t")
        let found = SearchResults.find(events: [], reminders: [], apple: AppleSnapshot(events: [], reminders: [r]),
                                       query: "tick", today: today)
        #expect(found.first?.appleSource == AppleSource(calendarID: "L9", calendarTitle: "Shared", colorHex: "#123456",
                                                         isReminder: true, url: "https://example.com/t",
                                                         isWritable: false))
    }
}
