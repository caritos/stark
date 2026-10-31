// ios/Tests/StarkKitTests/DayExportTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("DayExport")
struct DayExportTests {
    private let cal = Calendar(identifier: .gregorian)

    private func dt(_ iso: String, hour: Int = 12, minute: Int = 0) -> Date {
        let c = DateMath.components(iso)
        return cal.date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: hour, minute: minute))!
    }

    @Test("plain text: ISO day heading, then events with times, open and done reminders")
    func text() {
        let day = dt("2026-10-31", hour: 0)
        let event = Event(id: "e", title: "Dentist", start: dt("2026-10-31", hour: 14, minute: 30))
        let allDay = Event(id: "a", title: "Halloween", start: day, isAllDay: true)
        let open = Reminder(id: "o", title: "Call Nina", dueDate: dt("2026-10-31", hour: 9))
        let done = Reminder(id: "d", title: "Pay rent", dueDate: dt("2026-10-31", hour: 9), isCompleted: true, completedDate: day)
        let late = Reminder(id: "l", title: "Taxes", dueDate: dt("2026-09-01", hour: 9))
        let items = [
            AgendaItem(kind: .reminder(late), occurrence: dt("2026-09-01", hour: 9), displayDate: day, isOverdue: true),
            AgendaItem(kind: .event(allDay), occurrence: day, displayDate: day, isOverdue: false),
            AgendaItem(kind: .event(event), occurrence: event.start, displayDate: day, isOverdue: false),
            AgendaItem(kind: .reminder(open), occurrence: dt("2026-10-31", hour: 9), displayDate: day, isOverdue: false),
            AgendaItem(kind: .reminder(done), occurrence: dt("2026-10-31", hour: 9), displayDate: day, isOverdue: false),
        ]
        #expect(DayExport.text(day: day, items: items, calendar: cal) == """
        2026-10-31
        - [ ] Taxes (due 2026-09-01)
        - Halloween
        - 14:30 Dentist
        - [ ] Call Nina
        - [x] Pay rent
        """)
    }

    @Test("an empty day says so")
    func empty() {
        #expect(DayExport.text(day: dt("2026-10-31", hour: 0), items: [], calendar: cal) == "2026-10-31\n- (none)")
    }
}
