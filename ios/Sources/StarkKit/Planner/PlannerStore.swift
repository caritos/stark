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

    /// Replaces the event with the same `id` wherever it currently lives, then places the
    /// updated event where it now belongs (same routing as `addEvent`). Unknown id => no-op.
    /// Mutates memory first, then persists each affected file exactly once, so there is never
    /// a persisted state where the item is missing (as a delete + add would produce).
    public func updateEvent(_ event: Event) {
        var sources: Set<StoreLocation> = []
        if recurringEvents.contains(where: { $0.id == event.id }) { sources.insert(.recurring) }
        for month in loadedMonths where monthEvents[month]?.contains(where: { $0.id == event.id }) == true {
            sources.insert(.month(month))
        }
        guard !sources.isEmpty else { return }

        let destination: StoreLocation = event.recurrence != nil ? .recurring : .month(YearMonth(date: event.start))
        // Load the destination before touching anything: if it can't be read, abort so the
        // item stays where it was rather than being written over an unread file.
        if case .month(let month) = destination {
            loadMonth(month)
            guard loadedMonths.contains(month) else { return }
        }

        if sources == [destination] {
            // Same file: replace in place so the item keeps its position.
            switch destination {
            case .recurring:
                if let index = recurringEvents.firstIndex(where: { $0.id == event.id }) { recurringEvents[index] = event }
            case .month(let month):
                if let index = monthEvents[month]?.firstIndex(where: { $0.id == event.id }) { monthEvents[month]?[index] = event }
            }
        } else {
            for source in sources {
                switch source {
                case .recurring: recurringEvents.removeAll { $0.id == event.id }
                case .month(let month): monthEvents[month]?.removeAll { $0.id == event.id }
                }
            }
            switch destination {
            case .recurring: recurringEvents.append(event)
            case .month(let month): monthEvents[month, default: []].append(event)
            }
        }

        persist(sources.union([destination]))
        rebuild()
    }

    /// Reminder counterpart of `updateEvent(_:)`; routes by `recurrence` / `dueDate ?? Date()`
    /// exactly like `addReminder`.
    public func updateReminder(_ reminder: Reminder) {
        var sources: Set<StoreLocation> = []
        if recurringReminders.contains(where: { $0.id == reminder.id }) { sources.insert(.recurring) }
        for month in loadedMonths where monthReminders[month]?.contains(where: { $0.id == reminder.id }) == true {
            sources.insert(.month(month))
        }
        guard !sources.isEmpty else { return }

        let destination: StoreLocation = reminder.recurrence != nil
            ? .recurring
            : .month(YearMonth(date: reminder.dueDate ?? Date()))
        if case .month(let month) = destination {
            loadMonth(month)
            guard loadedMonths.contains(month) else { return }
        }

        if sources == [destination] {
            switch destination {
            case .recurring:
                if let index = recurringReminders.firstIndex(where: { $0.id == reminder.id }) { recurringReminders[index] = reminder }
            case .month(let month):
                if let index = monthReminders[month]?.firstIndex(where: { $0.id == reminder.id }) { monthReminders[month]?[index] = reminder }
            }
        } else {
            for source in sources {
                switch source {
                case .recurring: recurringReminders.removeAll { $0.id == reminder.id }
                case .month(let month): monthReminders[month]?.removeAll { $0.id == reminder.id }
                }
            }
            switch destination {
            case .recurring: recurringReminders.append(reminder)
            case .month(let month): monthReminders[month, default: []].append(reminder)
            }
        }

        persist(sources.union([destination]))
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

    /// Reopens a completed one-off reminder (Undo). The completed copy made by completing a
    /// recurring occurrence is just a one-off, so this covers it too; the master keeps its
    /// exception date on purpose. No-op for an unknown id, a recurring master, or a reminder
    /// that isn't completed.
    public func uncompleteReminder(id: String) {
        guard !recurringReminders.contains(where: { $0.id == id }) else { return }
        for month in loadedMonths {
            guard let idx = monthReminders[month]?.firstIndex(where: { $0.id == id }) else { continue }
            guard monthReminders[month]?[idx].isCompleted == true else { return }
            monthReminders[month]?[idx].isCompleted = false
            monthReminders[month]?[idx].completedDate = nil
            persistMonth(month)
            rebuild()
            return
        }
    }

    private func rebuild() {
        events = recurringEvents + monthEvents.values.flatMap { $0 }
        reminders = recurringReminders + monthReminders.values.flatMap { $0 }
    }

    private enum StoreLocation: Hashable {
        case recurring
        case month(YearMonth)
    }

    private func persist(_ locations: Set<StoreLocation>) {
        for location in locations {
            switch location {
            case .recurring: persistRecurring()
            case .month(let month): persistMonth(month)
            }
        }
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
