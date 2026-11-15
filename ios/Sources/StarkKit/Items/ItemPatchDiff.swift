// ios/Sources/StarkKit/Items/ItemPatchDiff.swift
import Foundation

extension Patch where T: Equatable {
    /// `keep` when nothing changed, else `set` or `clear`.
    static func diff(_ old: T?, _ new: T?) -> Patch<T> {
        guard old != new else { return .keep }
        return new.map(Patch.set) ?? .clear
    }
}

extension EventPatch {
    /// Only the fields that differ between `original` (the real item the edit sheet started from)
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
}

extension ReminderPatch {
    /// Only the fields that differ between `original` and `edited`. `Reminder` carries neither the
    /// date-only flag nor a URL, so the caller passes those changes (nil / `keep` = unchanged).
    public init(from original: Reminder, to edited: Reminder, dueHasTime: Bool? = nil, url: Patch<String> = .keep) {
        self.init(
            title: original.title == edited.title ? nil : edited.title,
            notes: .diff(original.notes, edited.notes),
            due: .diff(original.dueDate, edited.dueDate),
            dueHasTime: dueHasTime,
            priority: .diff(original.priority, edited.priority),
            recurrence: .diff(original.recurrence, edited.recurrence),
            url: url)
    }
}
