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
                   copy(due: "2026-10-11", done: "2026-10-12"),
                   copy(due: "2026-10-07", done: "2026-10-07")]
        let h = CompletionHistory.forReminder(master, among: all, today: today)
        #expect(h.entries.count == 3)
        #expect(h.doneLast30 == 3)
        #expect(h.lateLast90 == 1)
        #expect(h.entries[1].daysLate == 1)
        #expect(h.lastDone == d("2026-10-14"))
        #expect(h.longestGapDays == 5)
        #expect(h.averageGapDays == 3.5)
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
        #expect(h.longestGapDays == 1)          // entry days Oct 13 and Oct 14 -> gap 1
    }
}
