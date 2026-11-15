// ios/Sources/StarkKit/Items/ItemRepository.swift
import Foundation

/// Points at one Apple Calendar event or Reminders reminder. `identifier` is EventKit's
/// `calendarItemIdentifier`; `externalID` is the cross-device id when the store has one.
public struct AppleItemRef: Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable { case event, reminder }

    public let kind: Kind
    public let identifier: String
    public let externalID: String?

    public init(kind: Kind, identifier: String, externalID: String? = nil) {
        self.kind = kind
        self.identifier = identifier
        self.externalID = externalID
    }

    /// Parses an `AgendaItem.id` of an Apple row: `apple-<identifier>-<occurrence timestamp>`
    /// (`AgendaItem.id`), optionally followed by `-plan-<plan id>`. The identifier itself may
    /// contain hyphens. Returns nil for anything else, in particular Stark's UUID ids. The id does
    /// not say what kind the row is, so the caller passes it.
    public init?(agendaItemID: String, kind: Kind) {
        var rest = Substring(agendaItemID)
        guard rest.hasPrefix("apple-") else { return nil }
        rest = rest.dropFirst("apple-".count)
        if let plan = rest.range(of: "-plan-", options: .backwards) { rest = rest[..<plan.lowerBound] }
        guard let dash = rest.lastIndex(of: "-"),
              Double(rest[rest.index(after: dash)...]) != nil else { return nil }
        let identifier = String(rest[..<dash])
        guard !identifier.isEmpty else { return nil }
        self.init(kind: kind, identifier: identifier)
    }

    /// The ref for an Apple overlay row, or nil for one of Stark's own rows.
    public static func ref(for item: AgendaItem) -> AppleItemRef? {
        guard item.appleSource != nil else { return nil }
        switch item.kind {
        case .event: return AppleItemRef(agendaItemID: item.id, kind: .event)
        case .reminder: return AppleItemRef(agendaItemID: item.id, kind: .reminder)
        }
    }
}

/// An event to create (an `Event` without its id and exception dates).
public struct NewEvent: Equatable, Sendable {
    public var title: String
    public var notes: String?
    public var start: Date
    public var end: Date?
    public var isAllDay: Bool
    public var location: String?
    public var url: String?
    public var recurrence: RecurrenceRule?

    public init(title: String, notes: String? = nil, start: Date, end: Date? = nil, isAllDay: Bool = false,
                location: String? = nil, url: String? = nil, recurrence: RecurrenceRule? = nil) {
        self.title = title
        self.notes = notes
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.url = url
        self.recurrence = recurrence
    }
}

/// A reminder to create. `dueHasTime == false` means a date-only due date. Recurring reminders
/// need a due date (EventKit refuses to save one without).
public struct NewReminder: Equatable, Sendable {
    public var title: String
    public var notes: String?
    public var due: Date?
    public var dueHasTime: Bool
    public var priority: Int?
    public var recurrence: RecurrenceRule?
    public var url: String?

    public init(title: String, notes: String? = nil, due: Date? = nil, dueHasTime: Bool = true,
                priority: Int? = nil, recurrence: RecurrenceRule? = nil, url: String? = nil) {
        self.title = title
        self.notes = notes
        self.due = due
        self.dueHasTime = dueHasTime
        self.priority = priority
        self.recurrence = recurrence
        self.url = url
    }
}

/// What to do with one optional field: leave it, set it, or remove it.
public enum Patch<T: Sendable>: Sendable {
    case keep
    case set(T)
    case clear

    /// Applies the patch to a stored optional.
    public func applied(to value: T?) -> T? {
        switch self {
        case .keep: return value
        case .set(let new): return new
        case .clear: return nil
        }
    }
}

extension Patch: Equatable where T: Equatable {}

/// Changes to an event. Only the fields that are not `keep` / nil change. Required fields
/// (title, start, all-day) take an optional value, nil meaning keep.
public struct EventPatch: Equatable, Sendable {
    public var title: String?
    public var notes: Patch<String>
    public var location: Patch<String>
    public var url: Patch<String>
    public var start: Date?
    public var end: Patch<Date>
    public var isAllDay: Bool?
    public var recurrence: Patch<RecurrenceRule>
    /// The caller has warned the user that changing the repeat rule of a series loses the
    /// occurrences edited one by one in Apple Calendar (spike b). Without it the EventKit
    /// repository refuses a rule change on a series that has such occurrences.
    public var confirmRuleChange: Bool

    public init(title: String? = nil, notes: Patch<String> = .keep, location: Patch<String> = .keep,
                url: Patch<String> = .keep, start: Date? = nil, end: Patch<Date> = .keep,
                isAllDay: Bool? = nil, recurrence: Patch<RecurrenceRule> = .keep,
                confirmRuleChange: Bool = false) {
        self.title = title
        self.notes = notes
        self.location = location
        self.url = url
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.confirmRuleChange = confirmRuleChange
    }
}

/// Changes to a reminder, with the same rules as `EventPatch`.
public struct ReminderPatch: Equatable, Sendable {
    public var title: String?
    public var notes: Patch<String>
    public var due: Patch<Date>
    public var dueHasTime: Bool?
    public var priority: Patch<Int>
    public var recurrence: Patch<RecurrenceRule>
    public var url: Patch<String>

    public init(title: String? = nil, notes: Patch<String> = .keep, due: Patch<Date> = .keep,
                dueHasTime: Bool? = nil, priority: Patch<Int> = .keep,
                recurrence: Patch<RecurrenceRule> = .keep, url: Patch<String> = .keep) {
        self.title = title
        self.notes = notes
        self.due = due
        self.dueHasTime = dueHasTime
        self.priority = priority
        self.recurrence = recurrence
        self.url = url
    }
}

/// The real stored item behind a ref (for an event, the series master), with its real recurrence
/// and exception dates, for the edit sheet to start from.
public struct ItemDetails: Equatable, Sendable {
    public var event: Event?
    public var reminder: Reminder?
    /// A reminder's due date has a time of day (`Reminder` itself marks date-only as midnight).
    public var dueHasTime: Bool
    /// A reminder's URL (`Reminder` has no URL field).
    public var reminderURL: String?
    public var calendarID: String
    public var isWritable: Bool
    /// The user is only an invitee of the event, so most edits would not stick.
    public var isInviteeOnly: Bool
    /// The item repeats in a way `RecurrenceRule` cannot express; saving a changed rule would lose it.
    public var hasUnrepresentableRepeat: Bool
    /// The cross-device identifier (`calendarItemExternalIdentifier`), when the store has one.
    public var externalID: String?

    public init(event: Event? = nil, reminder: Reminder? = nil, dueHasTime: Bool = true,
                reminderURL: String? = nil, calendarID: String, isWritable: Bool = true,
                isInviteeOnly: Bool = false, hasUnrepresentableRepeat: Bool = false,
                externalID: String? = nil) {
        self.externalID = externalID
        self.event = event
        self.reminder = reminder
        self.dueHasTime = dueHasTime
        self.reminderURL = reminderURL
        self.calendarID = calendarID
        self.isWritable = isWritable
        self.isInviteeOnly = isInviteeOnly
        self.hasUnrepresentableRepeat = hasUnrepresentableRepeat
    }
}

public enum ItemRepositoryError: Error, Equatable, Sendable {
    case notFound
    case notWritable
    case unrepresentable(String)
    case saveFailed(String)
}

/// Reads and writes Apple Calendar events and Reminders reminders. StarkKit defines it; the app
/// target implements it over EventKit; `FakeItemRepository` is the in-memory twin for tests.
public protocol ItemRepository: Sendable {
    func addEvent(_ event: NewEvent, calendarID: String) async throws -> AppleItemRef
    func addReminder(_ reminder: NewReminder, listID: String) async throws -> AppleItemRef
    func details(_ ref: AppleItemRef) async throws -> ItemDetails
    /// Series edits apply to the whole series.
    func update(_ ref: AppleItemRef, event patch: EventPatch) async throws
    func update(_ ref: AppleItemRef, reminder patch: ReminderPatch) async throws
    /// Deletes the item; for a series, all of it.
    func delete(_ ref: AppleItemRef) async throws
    /// Removes one occurrence of an event series (the day `date` falls on).
    func deleteOccurrence(_ ref: AppleItemRef, on date: Date) async throws
    /// Completes a reminder. A recurring one advances to its next occurrence (same ref) and leaves a
    /// separate completed copy; when no occurrence is left the reminder itself is completed.
    func complete(_ ref: AppleItemRef, on date: Date) async throws
    func uncomplete(_ ref: AppleItemRef) async throws
    func writableCalendars() async throws -> [AppleCalendarInfo]
    /// All or nothing: if any item cannot be saved none is.
    func addBatch(events: [(event: NewEvent, calendarID: String)],
                  reminders: [(reminder: NewReminder, listID: String)]) async throws -> [AppleItemRef]
}
