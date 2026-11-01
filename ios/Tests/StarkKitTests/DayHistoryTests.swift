import Testing
import Foundation
@testable import StarkKit

struct DayHistoryTests {
    let cal = Calendar(identifier: .gregorian)

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    /// "Now" is Wednesday Nov 4 2026, 10:00.
    var today: Date { at(2026, 11, 4, 10) }

    func make(day: Date, events: [Event] = [], reminders: [Reminder], plans: [PlanBlock]) -> DayHistory {
        DayHistory.make(day: day, events: events, reminders: reminders, plans: plans, today: today, calendar: cal)
    }

    func plan(_ id: String, _ reminder: String, occ: Date, start: Date, minutes: Int = 30) -> PlanBlock {
        PlanBlock(id: id, reminderID: reminder, occurrence: occ, start: start, minutes: minutes)
    }

    @Test func doneAndOpenClassified() {
        let day = at(2026, 11, 2)
        let a = Reminder(id: "a", title: "Done one", dueDate: at(2026, 11, 2, 9), isCompleted: true, completedDate: at(2026, 11, 2, 9))
        let b = Reminder(id: "b", title: "Open one", dueDate: at(2026, 11, 2, 9))
        let h = make(day: day, reminders: [a, b], plans: [
            plan("p1", "a", occ: at(2026, 11, 2, 9), start: at(2026, 11, 2, 9)),
            plan("p2", "b", occ: at(2026, 11, 2, 9), start: at(2026, 11, 2, 10)),
        ])
        #expect(h.done.map(\.title) == ["Done one"])
        #expect(h.open.map(\.title) == ["Open one"])
        #expect(h.stats.done == 1)
        #expect(h.stats.open == 1)
    }

    @Test func deletedReminderIgnored() {
        let h = make(day: at(2026, 11, 2), reminders: [],
                     plans: [plan("p1", "gone", occ: at(2026, 11, 2), start: at(2026, 11, 2, 9))])
        #expect(h.done.isEmpty)
        #expect(h.open.isEmpty)
        #expect(!h.stats.hasPlan)
    }

    @Test func skippedEventLeftOut() {
        let day = at(2026, 11, 2)
        let skippedAt = at(2026, 11, 2, 9)
        let skipped = Event(id: "s", title: "Church", start: skippedAt, end: at(2026, 11, 2, 10),
                            outcomes: [EventOutcomeRecord(date: skippedAt, outcome: .skipped)])
        let kept = Event(id: "k", title: "Dentist", start: at(2026, 11, 2, 13), end: at(2026, 11, 2, 14))
        let allDay = Event(id: "ad", title: "Fair", start: at(2026, 11, 2), isAllDay: true)
        let h = make(day: day, events: [skipped, kept, allDay], reminders: [], plans: [])
        #expect(h.events.map(\.title) == ["Dentist"])
        #expect(h.allDayEvents.map(\.title) == ["Fair"])
    }

    @Test func recurringCompletedCopyMatchesBySeriesAndDay() {
        let day = at(2026, 11, 2)
        let master = Reminder(id: "daily", title: "Stretch", dueDate: at(2026, 11, 4, 8),
                              recurrence: RecurrenceRule(frequency: .daily))
        let copy = Reminder(id: "copy", title: "Stretch", dueDate: at(2026, 11, 2, 8), isCompleted: true,
                            completedDate: at(2026, 11, 2, 8), seriesID: "daily")
        let h = make(day: day, reminders: [master, copy], plans: [
            plan("p1", "daily", occ: at(2026, 11, 2, 8), start: at(2026, 11, 2, 8)),
            plan("p2", "daily", occ: at(2026, 11, 3, 8), start: at(2026, 11, 2, 9)),
        ])
        #expect(h.done.map(\.block.id) == ["p1"])
        #expect(h.open.map(\.block.id) == ["p2"])
    }

    @Test func minutesAndCompletion() {
        let a = Reminder(id: "a", title: "A", dueDate: at(2026, 11, 2), isCompleted: true, completedDate: at(2026, 11, 2))
        let b = Reminder(id: "b", title: "B", dueDate: at(2026, 11, 2))
        let c = Reminder(id: "c", title: "C", dueDate: at(2026, 11, 2))
        let h = make(day: at(2026, 11, 2), reminders: [a, b, c], plans: [
            plan("p1", "a", occ: at(2026, 11, 2), start: at(2026, 11, 2, 9), minutes: 60),
            plan("p2", "b", occ: at(2026, 11, 2), start: at(2026, 11, 2, 10), minutes: 30),
            plan("p3", "c", occ: at(2026, 11, 2), start: at(2026, 11, 2, 11), minutes: 30),
        ])
        #expect(h.stats.plannedMinutes == 120)
        #expect(h.stats.doneMinutes == 60)
        #expect(h.stats.completion == 1.0 / 3.0)
    }

    @Test func noPlanHasNoPlan() {
        let h = make(day: at(2026, 11, 2), reminders: [Reminder(id: "a", title: "A", dueDate: at(2026, 11, 2))], plans: [])
        #expect(!h.stats.hasPlan)
        #expect(h.stats.completion == nil)
        #expect(DayHistory.summaryLine(stats: h.stats, isToday: false) == nil)
    }

    @Test func futureDayEmpty() {
        let a = Reminder(id: "a", title: "A", dueDate: at(2026, 11, 5))
        let h = make(day: at(2026, 11, 5), events: [Event(id: "e", title: "E", start: at(2026, 11, 5, 9), end: at(2026, 11, 5, 10))],
                     reminders: [a], plans: [plan("p", "a", occ: at(2026, 11, 5), start: at(2026, 11, 5, 9))])
        #expect(h.events.isEmpty && h.allDayEvents.isEmpty && h.done.isEmpty && h.open.isEmpty)
        #expect(!h.stats.hasPlan)
    }

    @Test func weekStatsSumsSundayToSaturday() {
        // Week of Sun Nov 1 - Sat Nov 7; today is Wed Nov 4, so Thu plans are ignored,
        // and Sat Oct 31 belongs to the previous week.
        let done = Reminder(id: "d", title: "D", dueDate: at(2026, 11, 1), isCompleted: true, completedDate: at(2026, 11, 1))
        let open = Reminder(id: "o", title: "O", dueDate: at(2026, 11, 3))
        let future = Reminder(id: "f", title: "F", dueDate: at(2026, 11, 5))
        let prev = Reminder(id: "p", title: "P", dueDate: at(2026, 10, 31))
        let plans = [
            plan("1", "d", occ: at(2026, 11, 1), start: at(2026, 11, 1, 9), minutes: 60),
            plan("2", "o", occ: at(2026, 11, 3), start: at(2026, 11, 3, 9), minutes: 30),
            plan("3", "f", occ: at(2026, 11, 5), start: at(2026, 11, 5, 9), minutes: 30),
            plan("4", "p", occ: at(2026, 10, 31), start: at(2026, 10, 31, 9), minutes: 30),
        ]
        let s = DayHistory.weekStats(containing: at(2026, 11, 3), reminders: [done, open, future, prev], plans: plans, today: today, calendar: cal)
        #expect(s.done == 1)
        #expect(s.open == 1)
        #expect(s.plannedMinutes == 90)
        #expect(s.doneMinutes == 60)
    }

    @Test func summaryLineWording() {
        let s = DayHistory.Stats(done: 3, open: 2, plannedMinutes: 150, doneMinutes: 90)
        #expect(DayHistory.summaryLine(stats: s, isToday: false) == "3 DONE - 2 MISSED")
        #expect(DayHistory.summaryLine(stats: s, isToday: true) == "3 DONE - 2 OPEN")
        #expect(DayHistory.summaryLine(stats: DayHistory.Stats(done: 3, open: 0, plannedMinutes: 90, doneMinutes: 90), isToday: false) == "3 DONE")
        #expect(DayHistory.summaryLine(stats: DayHistory.Stats(done: 0, open: 2, plannedMinutes: 60, doneMinutes: 0), isToday: false) == "2 MISSED")
        #expect(DayHistory.weekLine(DayHistory.Stats(done: 11, open: 5, plannedMinutes: 480, doneMinutes: 330)) == "WEEK: 11 of 16 blocks done - 69%")
        #expect(DayHistory.weekLine(DayHistory.Stats(done: 0, open: 0, plannedMinutes: 0, doneMinutes: 0)) == nil)
    }

    @Test func minutesTextFormats() {
        #expect(DayHistory.minutesText(240) == "4h")
        #expect(DayHistory.minutesText(150) == "2h30")
        #expect(DayHistory.minutesText(45) == "45m")
        #expect(DayHistory.minutesText(0) == "0m")
        #expect(DayHistory.minutesText(65) == "1h05")
    }
}
