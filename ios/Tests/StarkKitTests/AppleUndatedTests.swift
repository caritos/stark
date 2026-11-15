import Foundation
import Testing
@testable import StarkKit

/// Undated Apple reminders (spec Decision 3): never in the agenda, listed for Search and the
/// planner's "No date" pane.
struct AppleUndatedTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: "#00FF00",
                                 isReminderList: true, isWritable: false)

    func reminder(_ id: String, _ title: String, due: Date? = nil, done: Bool = false) -> AppleReminder {
        AppleReminder(id: id, title: title, notes: nil, due: due, dueHasTime: false, isCompleted: done,
                      completedAt: done ? at(11, 10) : nil, priority: nil, calendar: list,
                      url: "https://example.com/\(id)")
    }

    @Test func undatedOpenRemindersBecomeRowsSortedLast() {
        let snapshot = AppleSnapshot(events: [], reminders: [
            reminder("u2", "Water plants"),
            reminder("d1", "Dated", due: at(11, 15)),
            reminder("u1", "Call bank"),
            reminder("u3", "Finished", done: true),
        ])
        let rows = undatedAppleReminders(snapshot)
        #expect(rows.map(\.title) == ["Call bank", "Water plants"])
        #expect(rows.allSatisfy { $0.displayDate == .distantFuture && $0.occurrence == .distantFuture })
        #expect(rows.allSatisfy { !$0.isOverdue && $0.plan == nil })
        guard case .reminder(let r) = rows[0].kind else { Issue.record("not a reminder"); return }
        #expect(r.id == "apple-u1")
        #expect(r.dueDate == nil && r.recurrence == nil && !r.isCompleted)
        #expect(rows[0].appleSource == AppleSource(calendarID: "L1", calendarTitle: "Inbox", colorHex: "#00FF00",
                                                    isReminder: true, url: "https://example.com/u1",
                                                    isWritable: false))
    }

    @Test func undatedRemindersNeverReachTheAgenda() {
        let snapshot = AppleSnapshot(events: [], reminders: [reminder("u1", "Call bank")])
        let merged = mergeAppleItems([], snapshot: snapshot, in: at(11, 1)...at(11, 30), today: at(11, 15, 10),
                                     calendar: cal)
        #expect(merged.isEmpty)
    }

    @Test func snapshotSplitsUndatedReminders() {
        let snapshot = AppleSnapshot(events: [], reminders: [reminder("u1", "A"), reminder("d1", "B", due: at(11, 2))])
        #expect(snapshot.undatedReminders.map(\.id) == ["u1"])
        #expect(AppleSnapshot.empty == AppleSnapshot(events: [], reminders: []))
    }
}
