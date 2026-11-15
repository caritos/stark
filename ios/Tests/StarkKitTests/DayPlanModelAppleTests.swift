import Testing
import Foundation
@testable import StarkKit

/// The planner reads Apple reminders and events (spec Decisions 1-3): open ones in the tray,
/// undated ones in the "No date" pane, blocks from the sidecar.
struct DayPlanModelAppleTests {
    let cal = Calendar(identifier: .gregorian)

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    /// "Now" is Monday Nov 2 2026, 10:00; the planned day is today.
    var today: Date { at(2026, 11, 2, 10) }
    let list = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil, isReminderList: true)

    func apple(_ id: String, _ title: String, due: Date? = nil, hasTime: Bool = false, done: Bool = false) -> AppleReminder {
        AppleReminder(id: id, title: title, notes: nil, due: due, dueHasTime: hasTime, isCompleted: done,
                      completedAt: done ? at(2026, 11, 2, 8) : nil, priority: nil, calendar: list)
    }

    func make(reminders: [Reminder] = [], apple: [AppleReminder], sidecar: [PlanBlock] = [],
              elsewhere: [PlanBlock] = [], day: Date? = nil) -> DayPlanModel {
        DayPlanModel.make(day: day ?? at(2026, 11, 2), events: [], reminders: reminders, plans: [], today: today,
                          plannedElsewhere: elsewhere, apple: AppleSnapshot(events: [], reminders: apple),
                          sidecarPlans: sidecar)
    }

    func ids(_ items: [AgendaItem]) -> [String] {
        items.compactMap { if case .reminder(let r) = $0.kind { return r.id } else { return nil } }
    }

    @Test func trayListsOpenAppleRemindersBesideLocalOnes() {
        let local = Reminder(id: "local", title: "Local task", dueDate: at(2026, 11, 2))
        let model = make(reminders: [local], apple: [
            apple("r1", "Buy stamps", due: at(2026, 11, 2)),
            apple("r2", "Old bill", due: at(2026, 10, 28)),
            apple("r3", "Renew card", due: at(2026, 11, 20)),
            apple("r4", "Done already", due: at(2026, 11, 2), done: true),
        ])
        #expect(ids(model.trayToday) == ["apple-r1", "local"])
        #expect(ids(model.trayPast) == ["apple-r2"])
        #expect(model.trayPast.first?.isOverdue == true)
        #expect(ids(model.trayFuture) == ["apple-r3"])
        #expect(model.trayToday.first?.appleSource?.calendarID == "L1")
        #expect(model.trayNoDate.isEmpty)
    }

    @Test func appleReminderFarOutsideTheLoadRangeIsStillInTheTray() {
        let model = make(apple: [apple("far", "Passport", due: at(2027, 6, 1))])
        #expect(ids(model.trayFuture) == ["apple-far"])
        #expect(model.trayFuture.first?.appleSource != nil)
    }

    @Test func timedAppleReminderDueThatDayIsOnTheTimeline() {
        let model = make(apple: [apple("t", "Call Ana", due: at(2026, 11, 2, 15), hasTime: true)])
        #expect(ids(model.timed) == ["apple-t"])
        #expect(model.tray.isEmpty)
    }

    @Test func undatedAppleRemindersFillTheNoDatePaneOnly() {
        let model = make(apple: [apple("u2", "Water plants"), apple("u1", "Call bank"),
                                 apple("u3", "Finished", done: true)])
        #expect(model.trayNoDate.map(\.title) == ["Call bank", "Water plants"])
        #expect(model.tray.isEmpty)
        #expect(TrayPane.noDate.items(in: model).map(\.title) == ["Call bank", "Water plants"])
        #expect(TrayPane.panes(for: model) == [.past, .today, .future, .noDate])
    }

    @Test func noDatePaneIsHiddenWithoutUndatedReminders() {
        let local = Reminder(id: "local", title: "Local", dueDate: at(2026, 11, 2))
        let model = make(reminders: [local], apple: [apple("r1", "Dated", due: at(2026, 11, 2))])
        #expect(model.trayNoDate.isEmpty)
        #expect(TrayPane.panes(for: model) == [.past, .today, .future])
        // The always-shown panes are unchanged.
        #expect(TrayPane.allCases == [.past, .today, .future])
    }

    @Test func noDatePaneTexts() {
        #expect(TrayPane.noDate.label(dayWord: "TODAY") == "NO DATE")
        #expect(TrayPane.noDate.hint(dayWord: "TODAY") == "A TO Z - NO DUE DATE")
        #expect(TrayPane.noDate.accessibilityLabel(dayWord: "TODAY", count: 2) == "No date, 2 tasks")
    }

    @Test func sidecarBlockPlacesAnAppleReminder() {
        let block = PlanBlock(id: "b1", reminderID: "apple-r1", occurrence: at(2026, 11, 2),
                              start: at(2026, 11, 2, 14), minutes: 30)
        let model = make(apple: [apple("r1", "Buy stamps", due: at(2026, 11, 2))], sidecar: [block])
        #expect(model.blocks == [block])
        #expect(model.tray.isEmpty)
        #expect(model.doneBlocks.isEmpty)
    }

    @Test func sidecarBlockPlacesAnUndatedReminder() {
        let block = PlanBlock(id: "b1", reminderID: "apple-u1", occurrence: .distantFuture,
                              start: at(2026, 11, 2, 15), minutes: 45)
        let model = make(apple: [apple("u1", "Call bank"), apple("u2", "Water plants")], sidecar: [block])
        #expect(model.blocks == [block])
        #expect(model.trayNoDate.map(\.title) == ["Water plants"])
    }

    @Test func undatedReminderPlannedOnAnotherDayLeavesTheNoDatePane() {
        let block = PlanBlock(id: "b1", reminderID: "apple-u1", occurrence: .distantFuture,
                              start: at(2026, 11, 4, 9), minutes: 30)
        let model = make(apple: [apple("u1", "Call bank")], elsewhere: [block])
        #expect(model.trayNoDate.isEmpty)
    }

    @Test func blockForAnOccurrenceTheSeriesMovedPastIsDone() {
        // A daily Apple reminder completed this morning now reads due tomorrow.
        let block = PlanBlock(id: "b1", reminderID: "apple-r1", occurrence: at(2026, 11, 2),
                              start: at(2026, 11, 2, 7), minutes: 20)
        let model = make(apple: [apple("r1", "Stretch", due: at(2026, 11, 3))], sidecar: [block])
        #expect(model.blocks.isEmpty)
        #expect(model.doneBlocks == [DayPlanModel.DoneBlock(block: block, title: "Stretch")])
    }

    @Test func blockForACompletedAppleOneOffIsDone() {
        let block = PlanBlock(id: "b1", reminderID: "apple-r1", occurrence: at(2026, 11, 2),
                              start: at(2026, 11, 2, 7), minutes: 20)
        let model = make(apple: [apple("r1", "Post letter", due: at(2026, 11, 2), done: true)], sidecar: [block])
        #expect(model.doneBlocks.map(\.title) == ["Post letter"])
    }

    @Test func emptySnapshotKeepsTheLocalModel() {
        let local = Reminder(id: "local", title: "Local", dueDate: at(2026, 11, 2))
        let plain = DayPlanModel.make(day: at(2026, 11, 2), events: [], reminders: [local], plans: [], today: today)
        let withEmpty = make(reminders: [local], apple: [])
        #expect(plain.tray == withEmpty.tray)
        #expect(withEmpty.trayNoDate.isEmpty)
    }
}
