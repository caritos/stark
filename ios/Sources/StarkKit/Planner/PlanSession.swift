import Foundation

/// The unsaved drafts of a planning session, one per day the user stepped to, so that stepping
/// between days keeps edits and a single "save all" writes every changed, still-editable day.
public struct PlanSession {
    private var drafts: [Date: PlanDraft] = [:]
    private let calendar: Calendar

    public init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    /// Keeps `draft` for `day` (keyed by start of day), replacing any earlier one.
    public mutating func stash(_ draft: PlanDraft, for day: Date) {
        drafts[calendar.startOfDay(for: day)] = draft
    }

    public func draft(for day: Date) -> PlanDraft? {
        drafts[calendar.startOfDay(for: day)]
    }

    /// Start-of-day keys whose draft has changes, ascending.
    public var changedDays: [Date] {
        drafts.filter { $0.value.hasChanges }.map(\.key).sorted()
    }

    public var hasChanges: Bool { drafts.values.contains { $0.hasChanges } }

    /// Removes drafts for days that are no longer editable (the date rolled past them).
    public mutating func dropLapsed(today: Date) {
        drafts = drafts.filter { PlannerDays.isEditable($0.key, today: today, calendar: calendar) }
    }

    /// Blocks on editable days other than `day`: each stashed draft's blocks, plus `saved`
    /// blocks on days that have no stashed draft.
    public func plannedElsewhere(of day: Date, saved: [PlanBlock], today: Date) -> [PlanBlock] {
        let own = calendar.startOfDay(for: day)
        var result: [PlanBlock] = []
        for (key, draft) in drafts where key != own && PlannerDays.isEditable(key, today: today, calendar: calendar) {
            result.append(contentsOf: draft.blocksToSave)
        }
        for block in saved {
            let key = calendar.startOfDay(for: block.start)
            if key != own, drafts[key] == nil, PlannerDays.isEditable(key, today: today, calendar: calendar) {
                result.append(block)
            }
        }
        return result
    }

    /// Writes every changed, editable day in ascending order; returns the days whose write failed.
    public func saveAll(today: Date, write: (Date, [PlanBlock]) -> Bool) -> [Date] {
        var failed: [Date] = []
        for day in changedDays where PlannerDays.isEditable(day, today: today, calendar: calendar) {
            if let draft = drafts[day], !write(day, draft.blocksToSave) { failed.append(day) }
        }
        return failed
    }
}
