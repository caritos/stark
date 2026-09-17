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

    /// Loads every month covered by `[windowStart, windowEnd]` — this must always be the
    /// same window `AgendaView` displays (see `AgendaWindow`). Loading a hardcoded
    /// center-month ± 1 while the agenda displays a wider window let items beyond the
    /// loaded months silently vanish on relaunch (they stayed visible only as long as the
    /// in-memory state that added them was still alive).
    public func start(windowStart: Date, windowEnd: Date) {
        // Recover any writes that failed and were queued during a previous session before
        // reading, so a recovered file's real content is what gets loaded.
        file.retryPendingWrites()

        do {
            let recurring = try file.loadRecurring()
            recurringEvents = recurring.events
            recurringReminders = recurring.reminders
        } catch {
            // A genuine read failure must never be treated as "no recurring items" —
            // leave whatever recurring state already existed untouched and surface the error.
            self.error = "Couldn't read recurring items: \(error.localizedDescription)"
        }

        var month = YearMonth(date: windowStart)
        let endMonth = YearMonth(date: windowEnd)
        while month <= endMonth {
            loadMonth(month)
            month = YearMonth(year: month.year, month0: month.month0 + 1)
        }
        rebuild()
    }

    /// Retries any writes that previously failed and were queued to disk. Safe to call
    /// repeatedly (e.g. on scene-foreground) — in-memory state is always already correct
    /// (mutations update it regardless of whether the persist succeeded), so this only
    /// needs to reconcile what's on disk, never reload or rebuild.
    public func retryPendingWrites() {
        file.retryPendingWrites()
    }

    public func loadMonth(_ month: YearMonth) {
        guard !loadedMonths.contains(month) else { return }
        do {
            let result = try file.loadMonth(month)
            monthEvents[month] = result.events
            monthReminders[month] = result.reminders
            loadedMonths.insert(month)
        } catch {
            // Do NOT mark as loaded and do NOT set an empty result — a real read failure
            // must stay retryable and must never be silently treated as "this month is empty".
            self.error = "Couldn't read \(month.fileName): \(error.localizedDescription)"
        }
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
        let recurringCountBefore = recurringEvents.count
        recurringEvents.removeAll { $0.id == id }
        if recurringEvents.count != recurringCountBefore {
            persistRecurring()
        }
        for month in loadedMonths {
            guard let events = monthEvents[month], events.contains(where: { $0.id == id }) else { continue }
            monthEvents[month]?.removeAll { $0.id == id }
            persistMonth(month)
        }
        rebuild()
    }

    public func deleteReminder(id: String) {
        let recurringCountBefore = recurringReminders.count
        recurringReminders.removeAll { $0.id == id }
        if recurringReminders.count != recurringCountBefore {
            persistRecurring()
        }
        for month in loadedMonths {
            guard let reminders = monthReminders[month], reminders.contains(where: { $0.id == id }) else { continue }
            monthReminders[month]?.removeAll { $0.id == id }
            persistMonth(month)
        }
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
