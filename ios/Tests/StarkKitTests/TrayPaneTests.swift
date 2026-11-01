import Testing
import Foundation
@testable import StarkKit

struct TrayPaneTests {
    @Test func labelsAndHintsUseThePlannedDayWord() {
        #expect(TrayPane.allCases == [.past, .today, .future])
        #expect(TrayPane.past.label(dayWord: "TODAY") == "PAST")
        #expect(TrayPane.today.label(dayWord: "TOMORROW") == "TOMORROW")
        #expect(TrayPane.future.label(dayWord: "TODAY") == "FUTURE")
        #expect(TrayPane.past.hint(dayWord: "TODAY") == "NEWEST FIRST - OLDER THAN TODAY")
        #expect(TrayPane.today.hint(dayWord: "TODAY") == "DUE TODAY - NOT YET PLACED")
        #expect(TrayPane.future.hint(dayWord: "TODAY") == "SOONEST FIRST - AFTER TODAY")
        #expect(TrayPane.today.hint(dayWord: "TOMORROW") == "DUE TOMORROW - NOT YET PLACED")
    }

    @Test func accessibilityLabelCountsTasks() {
        #expect(TrayPane.past.accessibilityLabel(dayWord: "TODAY", count: 87) == "Past, 87 tasks")
        #expect(TrayPane.today.accessibilityLabel(dayWord: "TOMORROW", count: 1) == "Tomorrow, 1 task")
        #expect(TrayPane.future.accessibilityLabel(dayWord: "TODAY", count: 0) == "Future, 0 tasks")
    }

    @Test func itemsComeFromTheModelPane() {
        let cal = Calendar(identifier: .gregorian)
        func at(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d))! }
        let model = DayPlanModel.make(day: at(11, 2), events: [], reminders: [
            Reminder(id: "p", title: "P", dueDate: at(10, 30)),
            Reminder(id: "t", title: "T", dueDate: at(11, 2)),
            Reminder(id: "f", title: "F", dueDate: at(11, 9)),
        ], plans: [], today: at(11, 2).addingTimeInterval(36_000))
        #expect(TrayPane.past.items(in: model).map(\.title) == ["P"])
        #expect(TrayPane.today.items(in: model).map(\.title) == ["T"])
        #expect(TrayPane.future.items(in: model).map(\.title) == ["F"])
    }
}
