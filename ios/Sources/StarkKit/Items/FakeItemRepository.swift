// ios/Sources/StarkKit/Items/FakeItemRepository.swift
import Foundation

/// In-memory `ItemRepository` with the semantics the EventKit one must have (see
/// `docs/superpowers/specs/2026-11-15-eventkit-write-spikes.md`): completing a recurring reminder
/// advances the same reminder to its next occurrence and leaves a separate completed copy; a
/// COUNT-limited series decrements and, when none is left, the reminder itself is completed.
public actor FakeItemRepository: ItemRepository {
    private struct StoredEvent {
        var event: Event
        var calendarID: String
    }
    private struct StoredReminder {
        var reminder: Reminder
        var dueHasTime: Bool
        var url: String?
        var calendarID: String
    }

    private let calendars: [AppleCalendarInfo]
    private let readOnlyIDs: Set<String>
    private let assignsExternalIDs: Bool
    private let now: @Sendable () -> Date
    private var events: [String: StoredEvent] = [:]
    private var reminders: [String: StoredReminder] = [:]
    private var counter = 0
    private var nextFailure: String?
    /// Series with occurrences "edited one by one in Calendar" (`markEditedOccurrences`).
    private var editedSeries: Set<String> = []
    /// Items whose details report a repeat Stark can't represent (`markUnrepresentableRepeat`).
    private var unrepresentable: Set<String> = []

    /// `assignsExternalIDs` gives every new item an external id (`ext-<identifier>`), as iCloud does.
    public init(calendars: [AppleCalendarInfo], readOnlyCalendarIDs: Set<String> = [],
                assignsExternalIDs: Bool = false, now: @escaping @Sendable () -> Date = { Date() }) {
        self.calendars = calendars
        self.readOnlyIDs = readOnlyCalendarIDs
        self.assignsExternalIDs = assignsExternalIDs
        self.now = now
    }

    /// Marks an event series as having occurrences edited one by one in Apple Calendar: a repeat
    /// change without `confirmRuleChange` is then refused, as the EventKit repository does.
    public func markEditedOccurrences(_ identifier: String) { editedSeries.insert(identifier) }

    /// Makes `details` report `hasUnrepresentableRepeat` for the item (an Apple rule Stark can't hold).
    public func markUnrepresentableRepeat(_ identifier: String) { unrepresentable.insert(identifier) }

    /// Makes the next mutating call throw `saveFailed(message)` and change nothing.
    public func failNext(_ message: String = "injected failure") { nextFailure = message }

    /// Number of stored items (events plus reminders, including completed copies), for tests.
    public var itemCount: Int { events.count + reminders.count }

    /// Every stored reminder, including completed copies, for tests.
    public var allReminders: [Reminder] { reminders.values.map(\.reminder) }

    // MARK: ItemRepository

    public func addEvent(_ event: NewEvent, calendarID: String) throws -> AppleItemRef {
        try beginWrite()
        try checkTarget(calendarID, reminderList: false)
        return insert(event, calendarID: calendarID)
    }

    public func addReminder(_ reminder: NewReminder, listID: String) throws -> AppleItemRef {
        try beginWrite()
        try checkTarget(listID, reminderList: true)
        try checkReminder(reminder)
        return insert(reminder, listID: listID)
    }

    public func addBatch(events newEvents: [(event: NewEvent, calendarID: String)],
                         reminders newReminders: [(reminder: NewReminder, listID: String)]) throws -> [AppleItemRef] {
        try beginWrite()
        for item in newEvents { try checkTarget(item.calendarID, reminderList: false) }
        for item in newReminders {
            try checkTarget(item.listID, reminderList: true)
            try checkReminder(item.reminder)
        }
        return newEvents.map { insert($0.event, calendarID: $0.calendarID) }
            + newReminders.map { insert($0.reminder, listID: $0.listID) }
    }

    public func details(_ ref: AppleItemRef) throws -> ItemDetails {
        switch ref.kind {
        case .event:
            guard let stored = events[ref.identifier] else { throw ItemRepositoryError.notFound }
            return ItemDetails(event: stored.event, calendarID: stored.calendarID,
                               isWritable: !readOnlyIDs.contains(stored.calendarID),
                               hasUnrepresentableRepeat: unrepresentable.contains(ref.identifier),
                               externalID: externalID(for: ref.identifier))
        case .reminder:
            guard let stored = reminders[ref.identifier] else { throw ItemRepositoryError.notFound }
            return ItemDetails(reminder: stored.reminder, dueHasTime: stored.dueHasTime,
                               reminderURL: stored.url, calendarID: stored.calendarID,
                               isWritable: !readOnlyIDs.contains(stored.calendarID),
                               hasUnrepresentableRepeat: unrepresentable.contains(ref.identifier),
                               externalID: externalID(for: ref.identifier))
        }
    }

    public func update(_ ref: AppleItemRef, event patch: EventPatch) throws {
        try beginWrite()
        guard ref.kind == .event, var stored = events[ref.identifier] else { throw ItemRepositoryError.notFound }
        try checkWritable(stored.calendarID)
        if patch.recurrence != .keep, !patch.confirmRuleChange, editedSeries.contains(ref.identifier),
           patch.recurrence.applied(to: stored.event.recurrence) != stored.event.recurrence {
            throw ItemRepositoryError.ruleChangeLosesEditedOccurrences
        }
        var e = stored.event
        if let title = patch.title { e.title = title }
        e.notes = patch.notes.applied(to: e.notes)
        e.location = patch.location.applied(to: e.location)
        e.url = patch.url.applied(to: e.url)
        if let start = patch.start { e.start = start }
        e.end = patch.end.applied(to: e.end)
        if let allDay = patch.isAllDay { e.isAllDay = allDay }
        e.recurrence = patch.recurrence.applied(to: e.recurrence)
        stored.event = e
        events[ref.identifier] = stored
    }

    public func update(_ ref: AppleItemRef, reminder patch: ReminderPatch) throws {
        try beginWrite()
        guard ref.kind == .reminder, var stored = reminders[ref.identifier] else { throw ItemRepositoryError.notFound }
        try checkWritable(stored.calendarID)
        var r = stored.reminder
        if let title = patch.title { r.title = title }
        r.notes = patch.notes.applied(to: r.notes)
        r.dueDate = patch.due.applied(to: r.dueDate)
        if let hasTime = patch.dueHasTime { stored.dueHasTime = hasTime }
        r.dueDate = Self.dueDate(r.dueDate, hasTime: stored.dueHasTime)
        r.priority = patch.priority.applied(to: r.priority)
        r.recurrence = patch.recurrence.applied(to: r.recurrence)
        stored.url = patch.url.applied(to: stored.url)
        if r.recurrence != nil, r.dueDate == nil {
            throw ItemRepositoryError.unrepresentable("A repeating reminder must have a due date.")
        }
        stored.reminder = r
        reminders[ref.identifier] = stored
    }

    public func delete(_ ref: AppleItemRef) throws {
        try beginWrite()
        switch ref.kind {
        case .event:
            guard let stored = events[ref.identifier] else { throw ItemRepositoryError.notFound }
            try checkWritable(stored.calendarID)
            events[ref.identifier] = nil
        case .reminder:
            guard let stored = reminders[ref.identifier] else { throw ItemRepositoryError.notFound }
            try checkWritable(stored.calendarID)
            reminders[ref.identifier] = nil
        }
    }

    public func deleteOccurrence(_ ref: AppleItemRef, on date: Date) throws {
        try beginWrite()
        guard ref.kind == .event, var stored = events[ref.identifier] else { throw ItemRepositoryError.notFound }
        try checkWritable(stored.calendarID)
        guard stored.event.recurrence != nil else {
            events[ref.identifier] = nil
            return
        }
        stored.event.exceptionDates.append(date)
        events[ref.identifier] = stored
    }

    public func complete(_ ref: AppleItemRef, on date: Date) throws {
        try beginWrite()
        guard ref.kind == .reminder, var stored = reminders[ref.identifier] else { throw ItemRepositoryError.notFound }
        try checkWritable(stored.calendarID)
        var r = stored.reminder
        guard !r.isCompleted else { return }
        // Already moved past `date`'s day: that occurrence is done (a double tap), do nothing.
        if r.recurrence != nil, let due = r.dueDate,
           Calendar.current.startOfDay(for: due) > Calendar.current.startOfDay(for: date) { return }
        let stamp = now()
        guard let rule = r.recurrence, let due = r.dueDate else {
            r.isCompleted = true
            r.completedAt = stamp
            r.completedDate = r.dueDate
            stored.reminder = r
            reminders[ref.identifier] = stored
            return
        }
        // A series with nothing left after this one completes itself, with no copy.
        var nextRule = rule
        if let count = rule.count { nextRule.count = count - 1 }
        let next = rule.count == 1 ? nil : nextOccurrence(after: max(due, stamp), anchor: due, rule: rule,
                                                          exceptions: r.exceptionDates)
        guard let next else {
            r.isCompleted = true
            r.completedAt = stamp
            r.completedDate = due
            stored.reminder = r
            reminders[ref.identifier] = stored
            return
        }
        let copy = Reminder(id: newID(), title: r.title, notes: r.notes, dueDate: due, isCompleted: true,
                            completedDate: due, priority: r.priority, completedAt: stamp)
        reminders[copy.id] = StoredReminder(reminder: copy, dueHasTime: stored.dueHasTime, url: stored.url,
                                            calendarID: stored.calendarID)
        r.dueDate = next
        r.recurrence = nextRule
        stored.reminder = r
        reminders[ref.identifier] = stored
    }

    public func uncomplete(_ ref: AppleItemRef) throws {
        try beginWrite()
        guard ref.kind == .reminder, var stored = reminders[ref.identifier] else { throw ItemRepositoryError.notFound }
        try checkWritable(stored.calendarID)
        stored.reminder.isCompleted = false
        stored.reminder.completedAt = nil
        stored.reminder.completedDate = nil
        reminders[ref.identifier] = stored
    }

    public func writableCalendars() -> [AppleCalendarInfo] {
        calendars.filter { !readOnlyIDs.contains($0.id) }
    }

    // MARK: Helpers

    private func beginWrite() throws {
        if let message = nextFailure {
            nextFailure = nil
            throw ItemRepositoryError.saveFailed(message)
        }
    }

    private func checkWritable(_ calendarID: String) throws {
        if readOnlyIDs.contains(calendarID) { throw ItemRepositoryError.notWritable }
    }

    /// The calendar or list must exist (as the right kind) and be writable.
    private func checkTarget(_ id: String, reminderList: Bool) throws {
        guard calendars.contains(where: { $0.id == id && $0.isReminderList == reminderList }) else {
            throw ItemRepositoryError.notFound
        }
        try checkWritable(id)
    }

    private func checkReminder(_ reminder: NewReminder) throws {
        if reminder.recurrence != nil, reminder.due == nil {
            throw ItemRepositoryError.unrepresentable("A repeating reminder must have a due date.")
        }
    }

    private func externalID(for identifier: String) -> String? {
        assignsExternalIDs ? "ext-\(identifier)" : nil
    }

    private func newID() -> String {
        counter += 1
        return "fake-\(counter)"
    }

    private func insert(_ new: NewEvent, calendarID: String) -> AppleItemRef {
        let id = newID()
        events[id] = StoredEvent(
            event: Event(id: id, title: new.title, notes: new.notes, start: new.start, end: new.end,
                         isAllDay: new.isAllDay, location: new.location, recurrence: new.recurrence, url: new.url),
            calendarID: calendarID)
        return AppleItemRef(kind: .event, identifier: id, externalID: externalID(for: id))
    }

    private func insert(_ new: NewReminder, listID: String) -> AppleItemRef {
        let id = newID()
        reminders[id] = StoredReminder(
            reminder: Reminder(id: id, title: new.title, notes: new.notes,
                               dueDate: Self.dueDate(new.due, hasTime: new.dueHasTime),
                               priority: new.priority, recurrence: new.recurrence),
            dueHasTime: new.dueHasTime, url: new.url, calendarID: listID)
        return AppleItemRef(kind: .reminder, identifier: id, externalID: externalID(for: id))
    }

    /// A date-only due date keeps only its day (local midnight), as EventKit's day components do.
    private static func dueDate(_ date: Date?, hasTime: Bool) -> Date? {
        guard let date, !hasTime else { return date }
        return Calendar.current.startOfDay(for: date)
    }

    /// The first occurrence of the series strictly after `moment` (EventKit's rule: after both the
    /// old due date and now). The rule's own COUNT is ignored here, the caller tracks it.
    private func nextOccurrence(after moment: Date, anchor: Date, rule: RecurrenceRule, exceptions: [Date]) -> Date? {
        var open = rule
        open.count = nil
        let from = moment.addingTimeInterval(1)
        let to = Calendar(identifier: .gregorian).date(byAdding: .year, value: 10, to: from) ?? from
        return OccurrenceExpander.occurrences(anchor: anchor, rule: open, exceptionDates: exceptions,
                                              in: from...to).first
    }
}
