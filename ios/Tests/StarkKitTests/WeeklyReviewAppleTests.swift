import Testing
import Foundation
@testable import StarkKit

/// Weekly Review with Apple reminders (spec Decision 1, spike (a)): completions counted by their
/// completion date, Apple's completed copies of a repeating reminder count as ordinary
/// completions, nothing is derived from a series having moved on.
struct WeeklyReviewAppleTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }
    /// Week of Sunday Nov 1 2026; "now" is Wednesday Nov 4, 10:00.
    var weekStart: Date { at(11, 1) }
    var today: Date { at(11, 4, 10) }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)

    func apple(_ id: String, _ title: String, due: Date?, completedAt: Date? = nil) -> AppleReminder {
        AppleReminder(id: id, title: title, notes: nil, due: due, dueHasTime: false, isCompleted: completedAt != nil,
                      completedAt: completedAt, priority: nil, calendar: list)
    }

    func review(_ reminders: [AppleReminder], local: [Reminder] = []) -> WeeklyReview {
        WeeklyReview.summary(events: [], reminders: local, weekStarting: weekStart, today: today,
                             apple: AppleSnapshot(events: [], reminders: reminders))
    }

    @Test func countsAppleCompletionsByCompletionDate() {
        let r = review([
            apple("one", "Post letter", due: at(11, 3), completedAt: at(11, 3, 18)),
            // Apple's completed copy of the repeating "Stretch" for Nov 2.
            apple("copy1", "Stretch", due: at(11, 2), completedAt: at(11, 2, 7)),
            // Due the week before, ticked this week: counts this week.
            apple("late", "File taxes", due: at(10, 28), completedAt: at(11, 5, 9)),
            // Due this week but ticked the week before: not this week.
            apple("early", "Early bird", due: at(11, 2), completedAt: at(10, 30, 9)),
        ])
        #expect(r.completed.map(\.title) == ["Stretch", "Post letter", "File taxes"])
        #expect(r.completed.allSatisfy { $0.appleSource != nil })
        #expect(r.completed.map(\.occurrence) == [at(11, 2, 7), at(11, 3, 18), at(11, 5, 9)])
    }

    @Test func doesNotInventCompletionsForARepeatingSeries() {
        // The series moved on to Nov 9, but no completed copy is in the snapshot.
        let r = review([apple("r1", "Stretch", due: at(11, 9))])
        #expect(r.completed.isEmpty)
        #expect(r.open.isEmpty)
        #expect(r.countsLabel == "0 done · 0 open")
    }

    @Test func openAppleRemindersDueInTheWeekAreOpen() {
        let r = review([
            apple("rent", "Pay rent", due: at(11, 6)),
            apple("missed", "Call Ana", due: at(11, 2)),
            apple("next", "Next week", due: at(11, 10)),
            apple("undated", "Someday", due: nil),
        ])
        #expect(r.open.map(\.title) == ["Call Ana", "Pay rent"])
        #expect(r.open.allSatisfy { !$0.isCompleted && $0.appleSource != nil })
    }

    @Test func appleAndLocalTogether() {
        let local = Reminder(id: "l", title: "Local done", dueDate: at(11, 4), isCompleted: true, completedDate: at(11, 4))
        let r = review([apple("one", "Post letter", due: at(11, 3), completedAt: at(11, 3, 18)),
                        apple("rent", "Pay rent", due: at(11, 6))], local: [local])
        #expect(r.countsLabel == "2 done · 1 open")
    }
}
