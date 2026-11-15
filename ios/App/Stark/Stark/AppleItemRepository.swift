//
//  AppleItemRepository.swift
//  Stark
//
//  The EventKit `ItemRepository`: creates, edits, completes and deletes Apple Calendar events and
//  Reminders reminders. Besides `EventKitProvider` (reads) this is the only file that imports
//  EventKit. Every rule below follows the write spikes
//  (`docs/superpowers/specs/2026-11-15-eventkit-write-spikes.md`); the semantics are pinned by the
//  shared `ItemRepositoryContract` that `FakeItemRepository` also passes.
//

import EventKit
import Foundation
import StarkKit

/// `nonisolated` and `@concurrent` for the same reasons as `EventKitProvider`: EventKit work never
/// runs on the main actor. `@unchecked Sendable`: the only state is the provider (itself
/// `Sendable`, holding the one shared `EKEventStore`) and a lock. Every write runs synchronously
/// under `writeLock`, so a batch's uncommitted saves and its `reset()` rollback can never mix with
/// another write. Every failed save or remove also resets the store under the lock, so a refused
/// change never lingers in the shared store's memory. EventKit objects never leave this file.
///
/// Identifiers: an event ref carries `eventIdentifier` (what the overlay rows carry, see
/// `EventKitProvider.map`), a reminder ref `calendarItemIdentifier`. A detached occurrence's
/// `/RID=` suffix is stripped, so its ref resolves to the series master.
nonisolated final class AppleItemRepository: ItemRepository, @unchecked Sendable {
    private let provider: EventKitProvider
    private let writeLock = NSLock()

    init(provider: EventKitProvider) {
        self.provider = provider
    }

    private var store: EKEventStore { provider.store }

    // MARK: - Add

    @concurrent
    func addEvent(_ event: NewEvent, calendarID: String) async throws -> AppleItemRef {
        try locked {
            let ekEvent = try makeEvent(event, in: try target(calendarID, entity: .event))
            do {
                try store.save(ekEvent, span: .futureEvents, commit: true)
            } catch {
                ekEvent.rollback()
                store.reset()
                throw error
            }
            return Self.ref(for: ekEvent)
        }
    }

    @concurrent
    func addReminder(_ reminder: NewReminder, listID: String) async throws -> AppleItemRef {
        try locked {
            let ekReminder = try makeReminder(reminder, in: try target(listID, entity: .reminder))
            do {
                try store.save(ekReminder, commit: true)
            } catch {
                ekReminder.rollback()
                store.reset()
                throw error
            }
            return Self.ref(for: ekReminder)
        }
    }

    /// Validates every target first, then `save(commit: false)` for each item and ONE `commit()`;
    /// any failure resets the store, so nothing is half-written.
    @concurrent
    func addBatch(events: [(event: NewEvent, calendarID: String)],
                  reminders: [(reminder: NewReminder, listID: String)]) async throws -> [AppleItemRef] {
        try locked {
            let eventTargets = try events.map { try target($0.calendarID, entity: .event) }
            let listTargets = try reminders.map { try target($0.listID, entity: .reminder) }
            var saved: [EKCalendarItem] = []
            do {
                for (item, calendar) in zip(events, eventTargets) {
                    let ekEvent = try makeEvent(item.event, in: calendar)
                    try store.save(ekEvent, span: .futureEvents, commit: false)
                    saved.append(ekEvent)
                }
                for (item, list) in zip(reminders, listTargets) {
                    let ekReminder = try makeReminder(item.reminder, in: list)
                    try store.save(ekReminder, commit: false)
                    saved.append(ekReminder)
                }
                try store.commit()
            } catch {
                store.reset()
                throw error
            }
            return saved.map(Self.ref(for:))
        }
    }

    // MARK: - Read

    @concurrent
    func details(_ ref: AppleItemRef) async throws -> ItemDetails {
        try locked {
            switch ref.kind {
            case .event:
                let master = try event(ref)
                guard let calendar = master.calendar else { throw ItemRepositoryError.notFound }
                let (value, unrepresentable) = eventValue(master)
                return ItemDetails(event: value, calendarID: calendar.calendarIdentifier,
                                   isWritable: calendar.allowsContentModifications,
                                   isInviteeOnly: Self.isInviteeOnly(master),
                                   hasUnrepresentableRepeat: unrepresentable,
                                   externalID: master.calendarItemExternalIdentifier,
                                   hasAttendees: master.hasAttendees)
            case .reminder:
                let ekReminder = try reminder(ref)
                guard let list = ekReminder.calendar else { throw ItemRepositoryError.notFound }
                let (value, hasTime, unrepresentable) = Self.reminderValue(ekReminder)
                return ItemDetails(reminder: value, dueHasTime: hasTime,
                                   reminderURL: Self.nonEmpty(ekReminder.url?.absoluteString),
                                   calendarID: list.calendarIdentifier,
                                   isWritable: list.allowsContentModifications,
                                   hasUnrepresentableRepeat: unrepresentable,
                                   externalID: ekReminder.calendarItemExternalIdentifier)
            }
        }
    }

    @concurrent
    func writableCalendars() async throws -> [AppleCalendarInfo] {
        try locked {
            store.calendars(for: .event).filter(\.allowsContentModifications)
                .map { EventKitProvider.info($0, isReminderList: false) }
                + store.calendars(for: .reminder).filter(\.allowsContentModifications)
                .map { EventKitProvider.info($0, isReminderList: true) }
        }
    }

    // MARK: - Update

    /// Edits the series master (`event(withIdentifier:)`) and saves `.futureEvents`, never an
    /// occurrence from a predicate fetch (that would split the series, spike b). A repeat-rule
    /// change on a series with occurrences edited one by one in Apple Calendar loses them, so it is
    /// refused unless `patch.confirmRuleChange`.
    @concurrent
    func update(_ ref: AppleItemRef, event patch: EventPatch) async throws {
        try locked {
            let master = try event(ref)
            try checkWritable(master.calendar)
            do {
                try apply(patch, to: master)
                try store.save(master, span: .futureEvents, commit: true)
            } catch {
                master.rollback()
                store.reset()
                throw error
            }
        }
    }

    @concurrent
    func update(_ ref: AppleItemRef, reminder patch: ReminderPatch) async throws {
        try locked {
            let ekReminder = try reminder(ref)
            try checkWritable(ekReminder.calendar)
            do {
                try apply(patch, to: ekReminder)
                try store.save(ekReminder, commit: true)
            } catch {
                ekReminder.rollback()
                store.reset()
                throw error
            }
        }
    }

    // MARK: - Delete

    /// A series goes whole: `.futureEvents` from the master (`.thisEvent` on the master would
    /// remove only its first day, spike c).
    @concurrent
    func delete(_ ref: AppleItemRef) async throws {
        try locked {
            switch ref.kind {
            case .event:
                let master = try event(ref)
                try checkWritable(master.calendar)
                try remove(master, span: .futureEvents)
            case .reminder:
                let ekReminder = try reminder(ref)
                try checkWritable(ekReminder.calendar)
                do {
                    try store.remove(ekReminder, commit: true)
                } catch {
                    ekReminder.rollback()
                    store.reset()
                    throw error
                }
            }
        }
    }

    /// Removes the occurrence that falls on `date`'s day with `.thisEvent`. A non-repeating event
    /// is deleted (as `FakeItemRepository` does). A detached occurrence's own ref (`/RID=`) is
    /// matched by its `eventIdentifier` only (not found otherwise): it keeps its ORIGINAL
    /// `occurrenceDate`, so the day match would pick the series' regular occurrence on that day.
    @concurrent
    func deleteOccurrence(_ ref: AppleItemRef, on date: Date) async throws {
        try locked {
            let master = try event(ref)
            try checkWritable(master.calendar)
            guard master.hasRecurrenceRules, let calendar = master.calendar else {
                try remove(master, span: .thisEvent)
                return
            }
            let days = Calendar.autoupdatingCurrent
            let dayStart = days.startOfDay(for: date)
            let dayEnd = days.date(byAdding: .day, value: 1, to: dayStart) ?? date
            let seriesID = Self.seriesID(master.eventIdentifier ?? ref.identifier)
            let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [calendar])
            let candidates = store.events(matching: predicate)
            if ref.identifier.contains("/RID=") {
                // Exact match only: a stale or reissued detached id must never fall back to the
                // day match, which would delete the series' regular occurrence on that day.
                guard let occurrence = candidates.first(where: { $0.eventIdentifier == ref.identifier }) else {
                    throw ItemRepositoryError.notFound
                }
                try remove(occurrence, span: .thisEvent)
                return
            }
            guard let occurrence = candidates.first(where: { candidate in
                Self.seriesID(candidate.eventIdentifier ?? "") == seriesID
                    && days.isDate(candidate.occurrenceDate ?? candidate.startDate, inSameDayAs: date)
            }) else { throw ItemRepositoryError.notFound }
            try remove(occurrence, span: .thisEvent)
        }
    }

    // MARK: - Complete

    /// `isCompleted = true` and save, nothing else (spike a): for a repeating reminder EventKit
    /// itself moves the same reminder to its next due date and writes a separate completed copy;
    /// when no occurrence is left (COUNT/UNTIL) the reminder itself reads completed afterwards. The
    /// repository must not move the due date too (that would skip one more occurrence). EventKit
    /// always completes the reminder's current occurrence, so `date` only guards against a second
    /// completion: when a repeating reminder's current due date is on a later day than `date`,
    /// that occurrence is already done (a double tap, the checkbox timer firing after Done) and
    /// nothing is saved. Completing a completed reminder does nothing.
    @concurrent
    func complete(_ ref: AppleItemRef, on date: Date) async throws {
        try locked {
            let ekReminder = try reminder(ref)
            try checkWritable(ekReminder.calendar)
            guard !ekReminder.isCompleted else { return }
            if ekReminder.hasRecurrenceRules, let components = ekReminder.dueDateComponents,
               let due = appleReminderDue(components).date {
                let days = Calendar.autoupdatingCurrent
                if days.startOfDay(for: due) > days.startOfDay(for: date) { return }
            }
            ekReminder.isCompleted = true
            do {
                try store.save(ekReminder, commit: true)
            } catch {
                ekReminder.rollback()
                store.reset()
                throw error
            }
        }
    }

    /// Un-completes the reminder. For a repeating series' completed copy this only reopens the copy
    /// (a one-off); the series is not rewound (spike a).
    @concurrent
    func uncomplete(_ ref: AppleItemRef) async throws {
        try locked {
            let ekReminder = try reminder(ref)
            try checkWritable(ekReminder.calendar)
            guard ekReminder.isCompleted else { return }
            ekReminder.isCompleted = false
            do {
                try store.save(ekReminder, commit: true)
            } catch {
                ekReminder.rollback()
                store.reset()
                throw error
            }
        }
    }

    // MARK: - Lookup and checks

    /// Removes with commit; on failure rolls the event back and resets the store (as every failed
    /// write does), so no half-applied change stays in the shared store's memory.
    private func remove(_ event: EKEvent, span: EKSpan) throws {
        do {
            try store.remove(event, span: span, commit: true)
        } catch {
            event.rollback()
            store.reset()
            throw error
        }
    }

    /// Runs `body` under the write lock and maps every error to `ItemRepositoryError`.
    private func locked<T>(_ body: () throws -> T) throws -> T {
        do {
            return try writeLock.withLock(body)
        } catch {
            throw Self.mapError(error)
        }
    }

    static func mapError(_ error: Error) -> ItemRepositoryError {
        if let error = error as? ItemRepositoryError { return error }
        let ns = error as NSError
        if ns.domain == EKErrorDomain, let code = EKError.Code(rawValue: ns.code) {
            switch code {
            case .calendarReadOnly, .calendarIsImmutable:
                return .notWritable
            default:
                break
            }
        }
        return .saveFailed(ns.localizedDescription)
    }

    private func target(_ id: String, entity: EKEntityType) throws -> EKCalendar {
        guard let calendar = store.calendar(withIdentifier: id),
              calendar.allowedEntityTypes.contains(entity == .event ? .event : .reminder) else {
            throw ItemRepositoryError.notFound
        }
        try checkWritable(calendar)
        return calendar
    }

    private func checkWritable(_ calendar: EKCalendar?) throws {
        guard let calendar else { throw ItemRepositoryError.notFound }
        guard calendar.allowsContentModifications else { throw ItemRepositoryError.notWritable }
    }

    /// The series master (or the single event).
    private func event(_ ref: AppleItemRef) throws -> EKEvent {
        guard ref.kind == .event else { throw ItemRepositoryError.notFound }
        let id = Self.seriesID(ref.identifier)
        if let found = store.event(withIdentifier: id) { return found }
        if let found = store.calendarItem(withIdentifier: id) as? EKEvent { return found }
        throw ItemRepositoryError.notFound
    }

    private func reminder(_ ref: AppleItemRef) throws -> EKReminder {
        guard ref.kind == .reminder,
              let found = store.calendarItem(withIdentifier: ref.identifier) as? EKReminder else {
            throw ItemRepositoryError.notFound
        }
        return found
    }

    /// A detached occurrence's id is the master's plus `/RID=<seconds>` (spike b).
    static func seriesID(_ identifier: String) -> String {
        guard let suffix = identifier.range(of: "/RID=") else { return identifier }
        return String(identifier[..<suffix.lowerBound])
    }

    private static func ref(for item: EKCalendarItem) -> AppleItemRef {
        if let event = item as? EKEvent {
            return AppleItemRef(kind: .event, identifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                                externalID: event.calendarItemExternalIdentifier)
        }
        return AppleItemRef(kind: .reminder, identifier: item.calendarItemIdentifier,
                            externalID: item.calendarItemExternalIdentifier)
    }

    /// The user is only invited: someone else organises it. When EventKit names no organizer, an
    /// attendee entry for the user that is not the chair also counts. Anything EventKit cannot say
    /// is NOT invitee-only (unverified on a device; Task 10 checklist).
    static func isInviteeOnly(_ event: EKEvent) -> Bool {
        if let organizer = event.organizer { return !organizer.isCurrentUser }
        if let me = event.attendees?.first(where: \.isCurrentUser) { return me.participantRole != .chair }
        return false
    }

    // MARK: - Building items

    private func makeEvent(_ new: NewEvent, in calendar: EKCalendar) throws -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = new.title
        event.notes = new.notes
        event.location = new.location
        event.url = try Self.url(new.url)
        event.isAllDay = new.isAllDay
        event.startDate = new.start
        // No end: a point event (timed) or a single day (all-day; EventKit stretches it to the day).
        event.endDate = new.end ?? new.start
        if let rule = new.recurrence {
            event.recurrenceRules = [Self.ekRule(try RecurrenceDescriptor(rule), isAllDay: new.isAllDay)]
        }
        return event
    }

    private func makeReminder(_ new: NewReminder, in list: EKCalendar) throws -> EKReminder {
        if new.recurrence != nil, new.due == nil {
            throw ItemRepositoryError.unrepresentable("A repeating reminder must have a due date.")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = new.title
        reminder.notes = new.notes
        reminder.priority = appleReminderPriority(new.priority)
        reminder.url = try Self.url(new.url)
        reminder.dueDateComponents = new.due.map { Self.dueComponents($0, hasTime: new.dueHasTime) }
        if let rule = new.recurrence {
            reminder.recurrenceRules = [Self.ekRule(try RecurrenceDescriptor(rule), isAllDay: false)]
        }
        return reminder
    }

    private func apply(_ patch: EventPatch, to event: EKEvent) throws {
        if let title = patch.title { event.title = title }
        Self.apply(patch.notes) { event.notes = $0 }
        Self.apply(patch.location) { event.location = $0 }
        switch patch.url {
        case .keep: break
        case .set(let text): event.url = try Self.url(text)
        case .clear: event.url = nil
        }

        let oldStart = event.startDate ?? Date()
        let oldEnd = event.endDate ?? oldStart
        if let allDay = patch.isAllDay { event.isAllDay = allDay }
        let newStart = patch.start ?? oldStart
        event.startDate = newStart
        switch patch.end {
        case .keep:
            // Keeps the length when only the start moves, so the end never lands before it.
            if patch.start != nil { event.endDate = newStart.addingTimeInterval(oldEnd.timeIntervalSince(oldStart)) }
        case .set(let end):
            event.endDate = end
        case .clear:
            // A timed event without an end is a point; an all-day one is a single day.
            event.endDate = newStart
        }

        switch patch.recurrence {
        case .keep:
            break
        case .set(let rule):
            let descriptor = try RecurrenceDescriptor(rule)
            let current = event.recurrenceRules ?? []
            if current.count == 1, Self.descriptor(current[0], isAllDay: event.isAllDay) == descriptor { break }
            try guardRuleChange(of: event, confirmed: patch.confirmRuleChange)
            event.recurrenceRules = [Self.ekRule(descriptor, isAllDay: event.isAllDay)]
        case .clear:
            guard event.hasRecurrenceRules else { break }
            try guardRuleChange(of: event, confirmed: patch.confirmRuleChange)
            event.recurrenceRules = nil
        }
    }

    /// Changing the rule of a series drops its detached occurrences (spike b), so it needs the
    /// caller's confirmation when there are any in the searched window.
    private func guardRuleChange(of master: EKEvent, confirmed: Bool) throws {
        guard !confirmed, master.hasRecurrenceRules else { return }
        if occurrences(of: master).contains(where: \.isDetached) {
            throw ItemRepositoryError.ruleChangeLosesEditedOccurrences
        }
    }

    private func apply(_ patch: ReminderPatch, to reminder: EKReminder) throws {
        if let title = patch.title { reminder.title = title }
        Self.apply(patch.notes) { reminder.notes = $0 }
        switch patch.url {
        case .keep: break
        case .set(let text): reminder.url = try Self.url(text)
        case .clear: reminder.url = nil
        }
        switch patch.priority {
        case .keep: break
        case .set(let priority): reminder.priority = appleReminderPriority(priority)
        case .clear: reminder.priority = 0
        }

        if patch.due != .keep || patch.dueHasTime != nil {
            let current = reminder.dueDateComponents.map { appleReminderDue($0) }
            let due = patch.due.applied(to: current?.date)
            let hasTime = patch.dueHasTime ?? current?.hasTime ?? true
            if let due {
                let components = Self.dueComponents(due, hasTime: hasTime)
                reminder.dueDateComponents = components
                // EventKit keeps the start equal to the due date (spike a); keep it so.
                if reminder.startDateComponents != nil { reminder.startDateComponents = components }
            } else {
                reminder.dueDateComponents = nil
                reminder.startDateComponents = nil
            }
            // EventKit leaves absolute-date alerts where they were; keep them with the due date.
            Self.shiftAlarms(of: reminder, from: current?.date, oldHasTime: current?.hasTime ?? true,
                             to: reminder.dueDateComponents.map { appleReminderDue($0) }?.date, newHasTime: hasTime)
        }

        switch patch.recurrence {
        case .keep: break
        case .set(let rule): reminder.recurrenceRules = [Self.ekRule(try RecurrenceDescriptor(rule), isAllDay: false)]
        case .clear: reminder.recurrenceRules = nil
        }
        if reminder.hasRecurrenceRules, reminder.dueDateComponents == nil {
            throw ItemRepositoryError.unrepresentable("A repeating reminder must have a due date.")
        }
    }

    /// Moves the reminder's absolute-date alerts with its due date (`ReminderAlarmShift`: by whole
    /// days, keeping their time of day, whenever a date-only due is involved); offset alerts follow
    /// the due date by themselves. Absolute alerts are replaced by NEW alarms (an
    /// absolute alert on iOS carries only its date): changing or removing the reminder's own alarm
    /// objects, or copies of them, did not always persist on the simulator (a removed alert came
    /// back at its original date).
    private static func shiftAlarms(of reminder: EKReminder, from oldDue: Date?, oldHasTime: Bool,
                                    to newDue: Date?, newHasTime: Bool) {
        let alarms = reminder.alarms ?? []
        let absolute = alarms.compactMap(\.absoluteDate)
        guard oldDue != newDue || oldHasTime != newHasTime, !absolute.isEmpty else { return }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .autoupdatingCurrent
        var shifted = ReminderAlarmShift.shifted(absolute, oldDue: oldDue, oldHasTime: oldHasTime,
                                                 newDue: newDue, newHasTime: newHasTime,
                                                 calendar: gregorian).makeIterator()
        var result: [EKAlarm] = []
        for alarm in alarms {
            guard alarm.absoluteDate != nil else {
                result.append(alarm)
                continue
            }
            if let date = shifted.next() ?? nil { result.append(EKAlarm(absoluteDate: date)) }
        }
        reminder.alarms = result
    }

    private static func apply(_ patch: Patch<String>, _ set: (String?) -> Void) {
        switch patch {
        case .keep: break
        case .set(let value): set(value)
        case .clear: set(nil)
        }
    }

    /// A non-empty link that is not a URL is refused rather than silently dropped.
    private static func url(_ text: String?) throws -> URL? {
        guard let text, !text.isEmpty else { return nil }
        guard let url = URL(string: text) else {
            throw ItemRepositoryError.unrepresentable("The link \"\(text)\" isn't a valid web address.")
        }
        return url
    }

    /// Gregorian field values in the phone's zone, as `appleReminderDue` reads them back; a
    /// date-only due date has no hour.
    static func dueComponents(_ date: Date, hasTime: Bool) -> DateComponents {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .autoupdatingCurrent
        return hasTime
            ? gregorian.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            : gregorian.dateComponents([.year, .month, .day], from: date)
    }

    // MARK: - Reading items back

    private func eventValue(_ event: EKEvent) -> (Event, unrepresentable: Bool) {
        let calendar = Calendar.autoupdatingCurrent
        let start = event.startDate ?? Date()
        var end = appleEventEnd(start: start, end: event.endDate, isAllDay: event.isAllDay, calendar: calendar)
        if let last = end {
            // A single all-day day and a timed point both read as "no end", as Stark stores them.
            if event.isAllDay ? calendar.isDate(last, inSameDayAs: start) : last == start { end = nil }
        }
        let (rule, unrepresentable) = Self.starkRule(event.recurrenceRules, isAllDay: event.isAllDay)
        // No exception dates: EventKit does not expose them and nothing that writes needs them
        // (computing them took two three-year fetches under the write lock on every `details`).
        let value = Event(id: Self.seriesID(event.eventIdentifier ?? event.calendarItemIdentifier),
                          title: event.title ?? "", notes: Self.nonEmpty(event.notes), start: start, end: end,
                          isAllDay: event.isAllDay, location: Self.nonEmpty(event.location), recurrence: rule,
                          url: Self.nonEmpty(event.url?.absoluteString))
        return (value, unrepresentable)
    }

    private static func reminderValue(_ reminder: EKReminder) -> (Reminder, hasTime: Bool, unrepresentable: Bool) {
        let due = reminder.dueDateComponents.map { appleReminderDue($0) }
        let (rule, unrepresentable) = starkRule(reminder.recurrenceRules, isAllDay: false)
        let value = Reminder(id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                             notes: nonEmpty(reminder.notes), dueDate: due?.date,
                             isCompleted: reminder.isCompleted,
                             completedDate: reminder.isCompleted ? due?.date : nil,
                             priority: icalPriority(fromApple: reminder.priority), recurrence: rule,
                             completedAt: reminder.completionDate)
        return (value, due?.hasTime ?? true, unrepresentable)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// The window searched for a series' detached occurrences (`guardRuleChange`): from a year
    /// back (or the series start) for three years, inside EventKit's four-year predicate limit.
    private func occurrenceWindow(of master: EKEvent) -> ClosedRange<Date> {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let start = master.startDate ?? now
        let lower = max(start, calendar.date(byAdding: .year, value: -1, to: now) ?? now)
        let upper = calendar.date(byAdding: .year, value: 3, to: lower) ?? lower
        return lower...upper
    }

    /// The series' occurrences in `occurrenceWindow`, detached ones included.
    private func occurrences(of master: EKEvent) -> [EKEvent] {
        guard let calendar = master.calendar else { return [] }
        let window = occurrenceWindow(of: master)
        let seriesID = Self.seriesID(master.eventIdentifier ?? "")
        let predicate = store.predicateForEvents(withStart: window.lowerBound, end: window.upperBound,
                                                 calendars: [calendar])
        return store.events(matching: predicate).filter { Self.seriesID($0.eventIdentifier ?? "") == seriesID }
    }

    // MARK: - Recurrence mapping (1:1 with RecurrenceDescriptor)

    static func ekRule(_ descriptor: RecurrenceDescriptor, isAllDay: Bool) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency = switch descriptor.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        let days = descriptor.daysOfTheWeek.compactMap { day -> EKRecurrenceDayOfWeek? in
            guard let weekday = EKWeekday(rawValue: day.weekday.rawValue + 1) else { return nil }
            if let number = day.weekNumber { return EKRecurrenceDayOfWeek(weekday, weekNumber: number) }
            return EKRecurrenceDayOfWeek(weekday)
        }
        let end: EKRecurrenceEnd? = switch descriptor.end {
        case .never: nil
        case .count(let count): EKRecurrenceEnd(occurrenceCount: count)
        case .until(let day): EKRecurrenceEnd(end: untilWriteDate(day, isAllDay: isAllDay))
        }
        func numbers(_ values: [Int]) -> [NSNumber]? { values.isEmpty ? nil : values.map { NSNumber(value: $0) } }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: descriptor.interval,
                                daysOfTheWeek: days.isEmpty ? nil : days,
                                daysOfTheMonth: numbers(descriptor.daysOfTheMonth),
                                monthsOfTheYear: numbers(descriptor.monthsOfTheYear),
                                weeksOfTheYear: nil, daysOfTheYear: nil,
                                setPositions: numbers(descriptor.setPositions), end: end)
    }

    /// Nil for shapes the descriptor has no field for (weeks or days of the year).
    static func descriptor(_ rule: EKRecurrenceRule, isAllDay: Bool) -> RecurrenceDescriptor? {
        guard (rule.weeksOfTheYear ?? []).isEmpty, (rule.daysOfTheYear ?? []).isEmpty else { return nil }
        let frequency: RecurrenceDescriptor.Frequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: return nil
        }
        var days: [RecurrenceDescriptor.DayOfWeek] = []
        for day in rule.daysOfTheWeek ?? [] {
            guard let weekday = Weekday(rawValue: day.dayOfTheWeek.rawValue - 1) else { return nil }
            days.append(RecurrenceDescriptor.DayOfWeek(weekday, weekNumber: day.weekNumber == 0 ? nil : day.weekNumber))
        }
        var end = RecurrenceDescriptor.End.never
        if let ruleEnd = rule.recurrenceEnd {
            if ruleEnd.occurrenceCount > 0 {
                end = .count(ruleEnd.occurrenceCount)
            } else if let date = ruleEnd.endDate {
                end = .until(untilReadDay(date, isAllDay: isAllDay))
            }
        }
        return RecurrenceDescriptor(frequency: frequency, interval: rule.interval, daysOfTheWeek: days,
                                    daysOfTheMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
                                    monthsOfTheYear: (rule.monthsOfTheYear ?? []).map(\.intValue),
                                    setPositions: (rule.setPositions ?? []).map(\.intValue), end: end)
    }

    /// Stark's rule, or nil with `unrepresentable` when EventKit has more than one rule or a shape
    /// Stark cannot hold.
    static func starkRule(_ rules: [EKRecurrenceRule]?, isAllDay: Bool) -> (RecurrenceRule?, unrepresentable: Bool) {
        guard let rules, !rules.isEmpty else { return (nil, false) }
        guard rules.count == 1, let descriptor = descriptor(rules[0], isAllDay: isAllDay),
              let rule = try? descriptor.asStarkRule() else { return (nil, true) }
        return (rule, false)
    }

    /// The inclusive last day. Timed items and reminders: 23:59:59 local on it (a start-of-day end
    /// would lose a timed item's last occurrence, spike d). All-day events: local NOON of the day,
    /// whose UTC date is that same day in every zone within +-11:59, because EventKit rewrites an
    /// all-day end to 23:59:59Z of a date and the read side takes the UTC day. (On the simulator,
    /// 23:59:59 local was also rewritten to the same date in New York, Tokyo and Honolulu; noon is
    /// the choice that does not depend on which date EventKit takes.)
    static func untilWriteDate(_ day: Date, isAllDay: Bool) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: isAllDay ? 12 : 23, minute: isAllDay ? 0 : 59,
                             second: isAllDay ? 0 : 59, of: start) ?? day
    }

    /// The until's calendar day, as local start of day: local for timed items, UTC for all-day
    /// events (EventKit rewrites their end to 23:59:59Z of the day, spike d).
    static func untilReadDay(_ date: Date, isAllDay: Bool) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .autoupdatingCurrent
        guard isAllDay else { return gregorian.startOfDay(for: date) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return gregorian.date(from: parts) ?? gregorian.startOfDay(for: date)
    }
}
