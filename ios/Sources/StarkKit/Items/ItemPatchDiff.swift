// ios/Sources/StarkKit/Items/ItemPatchDiff.swift
import Foundation

extension Patch where T: Equatable {
    /// `keep` when nothing changed, else `set` or `clear`.
    static func diff(_ old: T?, _ new: T?) -> Patch<T> {
        guard old != new else { return .keep }
        return new.map(Patch.set) ?? .clear
    }
}

extension FormFields {
    /// Whether a reminder's due date has a time of day, by Stark's rule: local midnight marks a
    /// date-only due date. Shared by add and update so the two always agree.
    public static func dueHasTime(_ reminder: Reminder) -> Bool {
        !isAllDay(reminder)
    }
}

extension EventPatch {
    /// Only the fields that differ between `original` (the item the edit sheet started from)
    /// and `edited`. Ids, exception dates and outcomes are never part of a patch.
    public init(from original: Event, to edited: Event) {
        self.init(
            title: original.title == edited.title ? nil : edited.title,
            notes: .diff(original.notes, edited.notes),
            location: .diff(original.location, edited.location),
            url: .diff(original.url, edited.url),
            start: original.start == edited.start ? nil : edited.start,
            end: .diff(original.end, edited.end),
            isAllDay: original.isAllDay == edited.isAllDay ? nil : edited.isAllDay,
            recurrence: .diff(original.recurrence, edited.recurrence))
    }

    /// Against the stored details; empty when they hold no event.
    public init(from original: ItemDetails, to edited: Event) {
        if let event = original.event { self.init(from: event, to: edited) } else { self.init() }
    }
}

extension ReminderPatch {
    /// Only the fields that differ between the stored details and the edited reminder plus its
    /// edited `url` (`Reminder` has no URL field). The date-only flag is derived from the edited
    /// due date (`FormFields.dueHasTime`) and sent only when the due date changed and the derived
    /// flag differs from the stored one, so an untouched timed reminder at midnight stays timed.
    public init(from original: ItemDetails, to edited: Reminder, url: String?) {
        let old = original.reminder
        let due: Patch<Date> = .diff(old?.dueDate, edited.dueDate)
        var dueHasTime: Bool?
        if case .set = due {
            let derived = FormFields.dueHasTime(edited)
            if derived != original.dueHasTime { dueHasTime = derived }
        }
        self.init(
            title: old?.title == edited.title ? nil : edited.title,
            notes: .diff(old?.notes, edited.notes),
            due: due,
            dueHasTime: dueHasTime,
            priority: .diff(old?.priority, edited.priority),
            recurrence: .diff(old?.recurrence, edited.recurrence),
            url: .diff(original.reminderURL, url))
    }
}
