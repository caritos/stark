// ios/Sources/StarkKit/Planner/PlannerStore.swift
import Foundation
import Combine

@MainActor
public final class PlannerStore: ObservableObject {
    @Published public private(set) var events: [Event] = []
    @Published public private(set) var reminders: [Reminder] = []
    @Published public var error: String?

    private let file: PlannerFile
    private var loadedMonths: Set<YearMonth> = []
    private var recurringEvents: [Event] = []
    private var recurringReminders: [Reminder] = []
    private var monthEvents: [YearMonth: [Event]] = [:]
    private var monthReminders: [YearMonth: [Reminder]] = [:]

    public init(file: PlannerFile) {
        self.file = file
    }

    public func start(around date: Date) {
        let recurring = file.loadRecurring()
        recurringEvents = recurring.events
        recurringReminders = recurring.reminders

        let center = YearMonth(date: date)
        for offset in -1...1 {
            loadMonth(YearMonth(year: center.year, month0: center.month0 + offset))
        }
        rebuild()
    }

    public func loadMonth(_ month: YearMonth) {
        guard !loadedMonths.contains(month) else { return }
        let result = file.loadMonth(month)
        monthEvents[month] = result.events
        monthReminders[month] = result.reminders
        loadedMonths.insert(month)
        rebuild()
    }

    public func addEvent(_ event: Event) {
        if event.recurrence != nil {
            recurringEvents.append(event)
            persistRecurring()
        } else {
            let month = YearMonth(date: event.start)
            loadMonth(month)
            monthEvents[month, default: []].append(event)
            persistMonth(month)
        }
        rebuild()
    }

    public func addReminder(_ reminder: Reminder) {
        if reminder.recurrence != nil {
            recurringReminders.append(reminder)
            persistRecurring()
        } else {
            let month = YearMonth(date: reminder.dueDate ?? Date())
            loadMonth(month)
            monthReminders[month, default: []].append(reminder)
            persistMonth(month)
        }
        rebuild()
    }

    public func deleteEvent(id: String) {
        recurringEvents.removeAll { $0.id == id }
        for month in loadedMonths { monthEvents[month]?.removeAll { $0.id == id } }
        persistRecurring()
        for month in loadedMonths { persistMonth(month) }
        rebuild()
    }

    public func deleteReminder(id: String) {
        recurringReminders.removeAll { $0.id == id }
        for month in loadedMonths { monthReminders[month]?.removeAll { $0.id == id } }
        persistRecurring()
        for month in loadedMonths { persistMonth(month) }
        rebuild()
    }

    public func completeReminder(id: String, on date: Date) {
        if let index = recurringReminders.firstIndex(where: { $0.id == id }) {
            recurringReminders[index].exceptionDates.append(date)
            var completedCopy = recurringReminders[index]
            completedCopy.id = UUID().uuidString
            completedCopy.recurrence = nil
            completedCopy.exceptionDates = []
            completedCopy.isCompleted = true
            completedCopy.completedDate = date
            completedCopy.dueDate = date

            let month = YearMonth(date: date)
            loadMonth(month)
            monthReminders[month, default: []].append(completedCopy)
            persistRecurring()
            persistMonth(month)
        } else {
            for month in loadedMonths {
                guard let idx = monthReminders[month]?.firstIndex(where: { $0.id == id }) else { continue }
                monthReminders[month]?[idx].isCompleted = true
                monthReminders[month]?[idx].completedDate = date
                persistMonth(month)
                break
            }
        }
        rebuild()
    }

    private func rebuild() {
        events = recurringEvents + monthEvents.values.flatMap { $0 }
        reminders = recurringReminders + monthReminders.values.flatMap { $0 }
    }

    private func persistRecurring() {
        do {
            try file.saveRecurring(events: recurringEvents, reminders: recurringReminders)
        } catch {
            self.error = "Couldn't save changes: \(error.localizedDescription)"
        }
    }

    private func persistMonth(_ month: YearMonth) {
        do {
            try file.saveMonth(month, events: monthEvents[month] ?? [], reminders: monthReminders[month] ?? [])
        } catch {
            self.error = "Couldn't save changes: \(error.localizedDescription)"
        }
    }
}
