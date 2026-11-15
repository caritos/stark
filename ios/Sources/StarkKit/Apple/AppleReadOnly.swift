// ios/Sources/StarkKit/Apple/AppleReadOnly.swift
import Foundation

extension AgendaItem {
    /// The one gate for Apple Calendar / Reminders rows Stark cannot change: an Apple row whose
    /// calendar or list is not writable (`AppleSource.isWritable`, from the snapshot). Such a row
    /// must never reach a router write, a Stark edit, plan, convert, skip or complete path.
    /// Writable Apple rows are edited through `ItemRouter` (Task 9); events where the owner is only
    /// an invitee are found when the sheet loads the stored details (`AppleEditorState`).
    public var isReadOnly: Bool { appleSource.map { !$0.isWritable } ?? false }

    /// The row as the edit sheet shows it: the STORED item (`ItemRouter.details`, with its real
    /// repeat rule) in place of the overlay's stand-in, keeping the tapped occurrence, its day, the
    /// plan and the source. `outcome` is the event's attended/skipped mark for the tapped day
    /// (kept in Stark's sidecar for Apple events).
    public func withStoredItem(_ details: ItemDetails, outcome: EventOutcome? = nil) -> AgendaItem {
        let newKind: Kind
        if var event = details.event {
            if let outcome { event.outcomes = [EventOutcomeRecord(date: occurrence, outcome: outcome)] }
            newKind = .event(event)
        } else if let reminder = details.reminder {
            newKind = .reminder(reminder)
        } else {
            return self
        }
        return AgendaItem(kind: newKind, occurrence: occurrence, displayDate: displayDate, isOverdue: isOverdue,
                          plan: plan, appleSource: appleSource)
    }
}

/// What tapping an agenda or Search row opens. Stark's own items open the edit sheet (`edit`);
/// Apple items in a writable calendar or list open the Apple editor (`editableApple`), which loads
/// the stored item first; anything else is the read-only detail. `editable` stays the local-only
/// way into the old edit path.
public enum AgendaItemDetail: Identifiable, Equatable {
    case edit(AgendaItem)
    case editableApple(AgendaItem, AppleItemRef)
    case readOnly(AgendaItem)

    public init(_ item: AgendaItem) {
        if item.appleSource == nil {
            self = .edit(item)
        } else if !item.isReadOnly, let ref = AppleItemRef.ref(for: item) {
            self = .editableApple(item, ref)
        } else {
            self = .readOnly(item)
        }
    }

    public var id: String {
        switch self {
        case .edit(let item), .readOnly(let item), .editableApple(let item, _): return item.id
        }
    }

    /// The item for Stark's own edit sheet, or nil for any Apple item.
    public var editable: AgendaItem? {
        guard case .edit(let item) = self else { return nil }
        return item
    }
}

/// The Apple editor once the stored details are in: edit them, or show the read-only detail
/// (the calendar can't be written, or the owner is only an invitee of the event, spec call 5).
public enum AppleEditorState: Equatable {
    case edit(ItemDetails)
    case readOnly

    public init(details: ItemDetails) {
        self = details.isWritable && !details.isInviteeOnly ? .edit(details) : .readOnly
    }
}

/// Unticking the completed copy of a repeating Apple reminder changes nothing: EventKit can't move
/// the series back (write spike a), and reopening the copy would leave two open items. The views
/// show this text INSTEAD of calling `uncomplete`; nil means "a normal uncomplete".
///
/// EventKit links a copy to its series only by title and list, so the item counts as a copy when
/// the snapshot holds an OPEN, REPEATING reminder in the same list with the same title, a
/// different identifier and a due date after the copy's (the series has moved past it). A
/// completed one-off that happens to share a repeating reminder's title and list and is older than
/// its due date is indistinguishable and gets the notice too (see the task-9a report).
public enum UncompleteNotice {
    public static let message =
        "This is a finished occurrence of a repeating reminder. The reminder already moved to its next date, so nothing was changed."

    public static func text(for item: AgendaItem, snapshot: AppleSnapshot) -> String? {
        guard let source = item.appleSource, case .reminder(let reminder) = item.kind, reminder.isCompleted,
              let ref = AppleItemRef.ref(for: item) else {
            return nil
        }
        let copyDue = reminder.dueDate ?? .distantPast
        let isCopy = snapshot.reminders.contains {
            $0.isRecurring && !$0.isCompleted && $0.id != ref.identifier && $0.title == reminder.title
                && $0.calendar.id == source.calendarID && ($0.due.map { $0 > copyDue } ?? false)
        }
        return isCopy ? message : nil
    }
}

/// Where the Add screen creates its item (always Apple): needs full access, then a writable
/// calendar (events) or list (reminders). The default destination is preselected when offered.
public enum AddDestination {
    public enum State: Equatable, Sendable {
        case needsAccess
        case noneWritable
        case ready(selected: String?)
    }

    public static func state(hasAccess: Bool, choices: [AppleCalendarInfo], defaultID: String?) -> State {
        guard hasAccess else { return .needsAccess }
        guard !choices.isEmpty else { return .noneWritable }
        return .ready(selected: choices.contains { $0.id == defaultID } ? defaultID : nil)
    }

    /// Plain-words reason Save is off, or nil when the screen can add.
    public static func message(_ state: State, isEvent: Bool) -> String? {
        switch state {
        case .needsAccess:
            return "Stark adds new items to Apple Calendar and Reminders. Allow full access in Settings to add one."
        case .noneWritable:
            return isEvent
                ? "There is no calendar Stark can add events to. Add one in Apple Calendar, or check Settings."
                : "There is no reminder list Stark can add to. Add one in Apple Reminders, or check Settings."
        case .ready:
            return nil
        }
    }
}

/// The Apple fetch range the Search sheet registers while open (spec decision 10): events within
/// two years either side of today. Reminders are fetched whole by the overlay (every open one).
public enum SearchWindow {
    public static let years = 2

    public static func range(around today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> ClosedRange<Date> {
        let start = calendar.startOfDay(for: today)
        let lower = calendar.date(byAdding: .year, value: -years, to: start) ?? start
        let upperDay = calendar.date(byAdding: .year, value: years, to: start) ?? start
        let upper = calendar.date(byAdding: .day, value: 1, to: upperDay)?.addingTimeInterval(-1) ?? upperDay
        return lower...upper
    }
}

/// The URL that opens a read-only Apple item in Calendar or Reminders, or nil for a Stark item.
///
/// - Event: `calshow:<seconds since 2001-01-01>` of the tapped occurrence (Calendar opens on
///   that day).
/// - Reminder: `x-apple-reminderkit://REMCDReminder/<calendarItemIdentifier>`, the identifier
///   being the item id without its `apple-` prefix.
///
/// Neither scheme is documented by Apple; both are to be confirmed on a device (plan Task 9) and
/// the link removed if they do not open the app.
public func appleOpenURL(for item: AgendaItem) -> URL? {
    guard let source = item.appleSource else { return nil }
    switch item.kind {
    case .event:
        guard !source.isReminder else { return nil }
        return URL(string: "calshow:\(Int(item.occurrence.timeIntervalSinceReferenceDate))")
    case .reminder(let reminder):
        let prefix = "apple-"
        guard reminder.id.hasPrefix(prefix) else { return nil }
        let identifier = String(reminder.id.dropFirst(prefix.count))
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard !identifier.isEmpty,
              let encoded = identifier.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "x-apple-reminderkit://REMCDReminder/\(encoded)")
    }
}

/// The URL stored on a read-only Apple item (an event's from `Event.url`, a reminder's from
/// `AppleSource.url`), or nil when absent or empty, or for a Stark item.
public func appleItemURL(_ item: AgendaItem) -> String? {
    guard let source = item.appleSource else { return nil }
    let url: String?
    switch item.kind {
    case .event(let event): url = event.url
    case .reminder: url = source.url
    }
    guard let url, !url.isEmpty else { return nil }
    return url
}

extension AppleSource {
    /// The calendar's colour as `0xRRGGBB`, parsed from `colorHex` ("#RRGGBB"); nil when absent
    /// or malformed.
    public var colorRGB: UInt32? { AppleColor.rgb(colorHex) }
}
