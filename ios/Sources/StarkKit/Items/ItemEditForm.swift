// ios/Sources/StarkKit/Items/ItemEditForm.swift
import Foundation

/// The edit sheet's fields and the one rule that turns them back into an `Event` / `Reminder`
/// (moved out of `EditItemView` unchanged, so Stark's own items save exactly as before).
///
/// Apple items need one more step (spec call 5): the form normalises what it writes back (notes
/// and location trimmed, an all-day end that is not after the start day dropped, the repeat end
/// re-applied), so diffing the edited item against the STORED item would report fields the owner
/// never touched. `ItemDetails.formBaseline()` runs the stored item through an untouched form; the
/// router diffs against that, so an untouched field is never written.
public struct ItemEditForm: Equatable, Sendable {
    public var title: String
    public var date: Date
    /// Events only. An event with no end starts with Ends equal to Starts, which stores as no end.
    public var endDate: Date
    public var allDay: Bool
    /// The item's rule without its end (`withoutEnd`); the end is `repeatEnd`, applied on save,
    /// because the repeat presets replace the whole rule and their checkmark compares whole rules.
    public var recurrence: RecurrenceRule?
    public var repeatEnd: RepeatEnd
    public var notes: String
    public var location: String
    public var url: String
    public var priority: ReminderPriority
    /// The date and all-day flag the form started with, used to tell "left alone" from "edited".
    public let initialDate: Date
    public let initialAllDay: Bool
    /// The form edits a reminder that had no due date (`showsNoDate`, `addDueDate`).
    public let startedUndated: Bool

    /// The form for an event (`title` is the row's title, which is the event's).
    public init(event: Event) {
        // Switching from all-day to timed drops the end (see `Event.scheduled`), so an all-day
        // event's own end is not offered as the timed one.
        self.init(title: event.title, date: event.start, endDate: EventSchedule.formEnd(for: event),
                  allDay: event.isAllDay, recurrence: event.recurrence, notes: event.notes ?? "",
                  location: event.location ?? "", url: event.url ?? "", priority: .none)
    }

    /// The form for a reminder. For a recurring reminder `dueDate` is the series' anchor, not the
    /// tapped occurrence: editing changes every occurrence. An undated one starts on `occurrence`.
    public init(reminder: Reminder, occurrence: Date) {
        let start = reminder.dueDate ?? occurrence
        self.init(title: reminder.title, date: start, endDate: start, allDay: FormFields.isAllDay(reminder),
                  recurrence: reminder.recurrence, notes: reminder.notes ?? "", location: "", url: "",
                  priority: ReminderPriority(icalValue: reminder.priority), startedUndated: reminder.dueDate == nil)
    }

    /// The form for an agenda row.
    public init(item: AgendaItem) {
        switch item.kind {
        case .event(let event): self.init(event: event)
        case .reminder(let reminder): self.init(reminder: reminder, occurrence: item.occurrence)
        }
        title = item.title
    }

    private init(title: String, date: Date, endDate: Date, allDay: Bool, recurrence: RecurrenceRule?,
                 notes: String, location: String, url: String, priority: ReminderPriority,
                 startedUndated: Bool = false) {
        self.title = title
        self.date = date
        self.endDate = endDate
        self.allDay = allDay
        self.recurrence = recurrence?.withoutEnd
        self.repeatEnd = RepeatEnd(rule: recurrence)
        self.notes = notes
        self.location = location
        self.url = url
        self.priority = priority
        self.initialDate = date
        self.initialAllDay = allDay
        self.startedUndated = startedUndated
    }

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The event with the form's fields applied.
    public func edited(_ event: Event) -> Event {
        // `scheduled` stores the picked start/end (an all-day end is its last day) and drops an
        // end that is not after the start.
        var updated = event.scheduled(start: date, end: endDate, allDay: allDay)
        updated.title = trimmedTitle
        updated.recurrence = repeatEnd.applied(to: recurrence)
        updated.notes = FormFields.trimmedOrNil(notes)
        updated.location = FormFields.trimmedOrNil(location)
        updated.url = FormFields.trimmedOrNil(url)
        return updated
    }

    /// The reminder with the form's fields applied.
    public func edited(_ reminder: Reminder) -> Reminder {
        var updated = reminder
        updated.title = trimmedTitle
        // A reminder with no due date stays that way unless the user picked one.
        if reminder.dueDate != nil || date != initialDate || allDay != initialAllDay {
            updated.dueDate = FormFields.normalizedStart(date, allDay: allDay)
        }
        updated.recurrence = repeatEnd.applied(to: recurrence)
        updated.notes = FormFields.trimmedOrNil(notes)
        updated.priority = ReminderPriority.updated(original: reminder.priority, chosen: priority)
        return updated
    }
}

extension ItemDetails {
    /// The stored item as an untouched edit form would write it back (see `ItemEditForm`). Pass
    /// this as the router's `original` so only fields the owner changed end up in the patch. A
    /// repeat Stark cannot represent is not in `event`/`reminder` at all (nil), and the sheet never
    /// offers to change it, so it is never part of a patch either.
    public func formBaseline() -> ItemDetails {
        var copy = self
        if let event { copy.event = ItemEditForm(event: event).edited(event) }
        if let reminder {
            let occurrence = reminder.dueDate ?? Date(timeIntervalSinceReferenceDate: 0)
            copy.reminder = ItemEditForm(reminder: reminder, occurrence: occurrence).edited(reminder)
        }
        return copy
    }
}
