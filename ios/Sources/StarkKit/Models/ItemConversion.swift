// ios/Sources/StarkKit/Models/ItemConversion.swift
import Foundation

/// Converting an event into a task (`Reminder`) and back, from the Edit screen (issue #116).
/// The converted item keeps the original id, so it replaces the original in storage.
public enum ItemConversion {
    /// The reminder an event becomes. Carries title, notes, start (as the due date/time; an
    /// all-day event is due at the start of its day, the model's "no time" marker), recurrence
    /// (until/count included) and exception dates. Location and URL are appended to the notes as
    /// "Location: …" / "URL: …" lines. The end and the attended/skipped marks are dropped (see
    /// `droppedMarks(converting:)`, which the UI confirms first).
    public static func reminder(from event: Event) -> Reminder {
        Reminder(
            id: event.id,
            title: event.title,
            notes: notes(event.notes, location: event.location, url: event.url),
            dueDate: FormFields.normalizedStart(event.start, allDay: event.isAllDay),
            recurrence: event.recurrence,
            exceptionDates: event.exceptionDates
        )
    }

    /// The event an open reminder becomes. Carries title, notes, due date (as the start),
    /// recurrence and exception dates; priority is dropped (events never carry one). A reminder
    /// with no time (due at the start of its day) becomes an all-day event, otherwise a timed
    /// event with no end. An undated reminder becomes all-day on `undatedStart`'s day.
    public static func event(from reminder: Reminder, undatedStart: Date) -> Event {
        let start = reminder.dueDate ?? FormFields.normalizedStart(undatedStart, allDay: true)
        return Event(
            id: reminder.id,
            title: reminder.title,
            notes: reminder.notes,
            start: start,
            isAllDay: FormFields.isAllDay(start),
            recurrence: reminder.recurrence,
            exceptionDates: reminder.exceptionDates
        )
    }

    /// The event the Edit form describes when it converts a reminder: `edited` is the reminder
    /// with the form's fields already applied, `originalDueDate` its due date when the form
    /// opened. The form's Starts/Ends/All day apply (an end not after the start is stored as
    /// none), except that a reminder opened undated always lands all-day on the form's date: its
    /// All day toggle starts off only because an undated reminder has no time to show.
    public static func event(fromEdited edited: Reminder, originalDueDate: Date?,
                             start: Date, end: Date, allDay: Bool) -> Event {
        let isAllDay = allDay || originalDueDate == nil
        return event(from: edited, undatedStart: start).scheduled(start: start, end: end, allDay: isAllDay)
    }

    /// How many attended/skipped marks converting this event to a reminder would lose.
    public static func droppedMarks(converting event: Event) -> Int {
        event.outcomes.count
    }

    /// Only open reminders can become events; a completed one (including a recurring series'
    /// completed copy) is history.
    public static func isConvertible(_ reminder: Reminder) -> Bool {
        !reminder.isCompleted
    }

    /// `notes` followed by a "Location: …" and a "URL: …" line (blank values skipped), separated
    /// from non-empty notes by a blank line. Nil when nothing is left.
    public static func notes(_ notes: String?, location: String?, url: String?) -> String? {
        let base = notes.flatMap(FormFields.trimmedOrNil)
        var extra: [String] = []
        if let location = location.flatMap(FormFields.trimmedOrNil) { extra.append("Location: \(location)") }
        if let url = url.flatMap(FormFields.trimmedOrNil) { extra.append("URL: \(url)") }
        guard !extra.isEmpty else { return base }
        let details = extra.joined(separator: "\n")
        return base.map { "\($0)\n\n\(details)" } ?? details
    }
}
