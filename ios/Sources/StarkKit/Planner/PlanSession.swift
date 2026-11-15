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

    /// True when an editable day's blocks to save differ from `saved`'s (blocks compared by id,
    /// reminder, occurrence, start and length, order ignored); a day without changes on one side
    /// counts as "nothing to save" there. These are edits made while `saved` was being written,
    /// which a closing planner would lose.
    public func hasEdits(since saved: PlanSession, today: Date) -> Bool {
        struct Key: Hashable {
            let id: String, reminderID: String, occurrence: Date, start: Date, minutes: Int
            init(_ b: PlanBlock) {
                id = b.id; reminderID = b.reminderID; occurrence = b.occurrence; start = b.start; minutes = b.minutes
            }
        }
        func keys(_ draft: PlanDraft?) -> Set<Key>? {
            guard let draft, draft.hasChanges else { return nil }
            return Set(draft.blocksToSave.map(Key.init))
        }
        let days = Set(drafts.keys).union(saved.drafts.keys)
        return days.contains { day in
            PlannerDays.isEditable(day, today: today, calendar: calendar) && keys(drafts[day]) != keys(saved.drafts[day])
        }
    }

    /// `saveAll` for an async writer (`ItemRouter.replacePlans`): the same days in the same
    /// order, one write at a time; returns the days whose write failed.
    public func saveAll(today: Date, writing write: (Date, [PlanBlock]) async -> Bool) async -> [Date] {
        var failed: [Date] = []
        for day in changedDays where PlannerDays.isEditable(day, today: today, calendar: calendar) {
            if let draft = drafts[day], !(await write(day, draft.blocksToSave)) { failed.append(day) }
        }
        return failed
    }
}
