import Testing
import Foundation
@testable import StarkKit

/// Planner history for Apple reminders (spec Decision 1, spike (a)): Apple advances a repeating
/// reminder in place and leaves a completed copy (new identifier, old due date) per completion.
struct DayHistoryAppleTests {
    let cal = Calendar(identifier: .gregorian)

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    /// "Now" is Wednesday Nov 4 2026, 10:00; the day looked at is Monday Nov 2.
    var today: Date { at(2026, 11, 4, 10) }
    var day: Date { at(2026, 11, 2) }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)
    let other = AppleCalendarInfo(id: "L2", title: "Groceries", accountName: "iCloud", colorHex: nil, isReminderList: true)

    func apple(_ id: String, _ title: String, due: Date?, done: Bool = false,
               in calendar: AppleCalendarInfo? = nil, repeating: Bool = false) -> AppleReminder {
        AppleReminder(id: id, title: title, notes: nil, due: due, dueHasTime: true, isCompleted: done,
                      completedAt: done ? at(2026, 11, 2, 18) : nil, priority: nil, calendar: calendar ?? list,
                      isRecurring: repeating)
    }

    /// A 30-minute block on Nov 2 at 09:00 for `apple-<id>`'s Nov 2 09:00 occurrence.
    func block(_ id: String) -> PlanBlock {
        PlanBlock(id: "b-\(id)", reminderID: "apple-\(id)", occurrence: at(2026, 11, 2, 9),
                  start: at(2026, 11, 2, 9), minutes: 30)
    }

    func history(_ reminders: [AppleReminder], plans: [PlanBlock]) -> DayHistory {
        DayHistory.make(day: day, events: [], reminders: [], plans: [], today: today,
                        apple: AppleSnapshot(events: [], reminders: reminders), sidecarPlans: plans, calendar: cal)
    }

    @Test func blockTheSeriesMovedPastIsDoneNeverMissed() {
        // Weekly "Stretch": completed for Nov 2, the series now reads due Nov 9.
        let h = history([apple("r1", "Stretch", due: at(2026, 11, 9, 9), repeating: true)], plans: [block("r1")])
        #expect(h.done.map(\.title) == ["Stretch"])
        #expect(h.open.isEmpty)
        #expect(DayHistory.summaryLine(stats: h.stats, isToday: false) == "1 DONE")
    }

    @Test func matchingCompletedCopyIsDone() {
        // Positive evidence: Apple's completed copy for the Nov 2 occurrence (new identifier, same
        // title, list and due day), even though the master still reads due Nov 2.
        let h = history([apple("r1", "Stretch", due: at(2026, 11, 2, 9), repeating: true),
                         apple("copy1", "Stretch", due: at(2026, 11, 2, 9), done: true)],
                        plans: [block("r1")])
        #expect(h.done.map(\.title) == ["Stretch"])
        #expect(h.open.isEmpty)
    }

    @Test func copyInAnotherListOrOnAnotherDayIsNoEvidence() {
        let h = history([apple("r1", "Stretch", due: at(2026, 11, 2, 9), repeating: true),
                         apple("c1", "Stretch", due: at(2026, 11, 2, 9), done: true, in: other),
                         apple("c2", "Stretch", due: at(2026, 11, 1, 9), done: true)],
                        plans: [block("r1")])
        #expect(h.done.isEmpty)
        #expect(h.open.map(\.title) == ["Stretch"])
    }

    @Test func openPastOccurrenceIsMissed() {
        let h = history([apple("r1", "Stretch", due: at(2026, 11, 2, 9), repeating: true)], plans: [block("r1")])
        #expect(h.done.isEmpty)
        #expect(h.open.map(\.title) == ["Stretch"])
        #expect(DayHistory.summaryLine(stats: h.stats, isToday: false) == "1 MISSED")
    }

    @Test func completedOneOffIsDone() {
        let h = history([apple("r2", "Post letter", due: at(2026, 11, 2, 9), done: true)], plans: [block("r2")])
        #expect(h.done.map(\.title) == ["Post letter"])
        #expect(h.stats.doneMinutes == 30)
    }

    @Test func deletedAppleReminderIsIgnored() {
        let h = history([], plans: [block("gone")])
        #expect(!h.stats.hasPlan)
    }

    @Test func weekStatsCountAppleBlocks() {
        let stats = DayHistory.weekStats(containing: day, reminders: [], plans: [], today: today,
                                         apple: AppleSnapshot(events: [], reminders: [
                                             apple("r1", "Stretch", due: at(2026, 11, 9, 9), repeating: true),
                                             apple("r3", "Read", due: at(2026, 11, 2, 9)),
                                         ]),
                                         sidecarPlans: [block("r1"), block("r3")], calendar: cal)
        #expect(stats.done == 1)
        #expect(stats.open == 1)
        #expect(DayHistory.weekLine(stats) == "WEEK: 1 of 2 blocks done - 50%")
    }

    @Test func appleEventsShowOnThePastDay() {
        let event = AppleCalendarEvent(id: "e1", title: "Standup", notes: nil, location: nil, url: nil,
                                       start: at(2026, 11, 2, 9), end: at(2026, 11, 2, 9, 15), isAllDay: false,
                                       calendar: AppleCalendarInfo(id: "C1", title: "Work", accountName: "iCloud",
                                                                   colorHex: nil, isReminderList: false))
        let h = DayHistory.make(day: day, events: [], reminders: [], plans: [], today: today,
                                apple: AppleSnapshot(events: [event], reminders: []), calendar: cal)
        #expect(h.events.map(\.title) == ["Standup"])
    }
}
