import Testing
import Foundation
@testable import StarkKit

/// The agenda row's repeat glyph: Apple reminders carry no `recurrence` on the synthetic
/// `Reminder`, so `showsRepeatGlyph` also reads the series flag copied onto `AppleSource`.
struct AgendaRepeatGlyphTests {
    let cal = Calendar(identifier: .gregorian)
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)
    var today: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 10))! }

    func rows(recurring: Bool) -> [AgendaItem] {
        let due = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        let reminder = AppleReminder(id: "r1", title: "Stretch", notes: nil, due: due, dueHasTime: true,
                                     isCompleted: false, completedAt: nil, priority: nil, calendar: list,
                                     isRecurring: recurring)
        return mergeAppleItems([], snapshot: AppleSnapshot(events: [], reminders: [reminder]),
                               in: AgendaWindow.range(around: today, calendar: cal), today: today, calendar: cal)
    }

    @Test func repeatingAppleReminderShowsTheGlyph() {
        #expect(rows(recurring: true).first?.showsRepeatGlyph == true)
    }

    @Test func oneOffAppleReminderDoesNot() {
        #expect(rows(recurring: false).first?.showsRepeatGlyph == false)
    }

    @Test func localRecurringItemStillDoes() {
        let reminder = Reminder(id: "l1", title: "Local", dueDate: today, recurrence: RecurrenceRule(frequency: .daily))
        let item = AgendaItem(kind: .reminder(reminder), occurrence: today, displayDate: today, isOverdue: false)
        #expect(item.showsRepeatGlyph)
    }
}
