import Foundation

/// The editable plan for one day: a copy of the saved blocks that the planner UI changes
/// (place, move, resize, remove) before saving `blocksToSave` with `PlannerStore.replacePlans`.
/// Only `PlanBlock`s change; a reminder's due date and recurrence are never touched.
public struct PlanDraft {
    /// The blocks the planner shows and edits (the model's blocks: open, loaded tasks).
    public private(set) var blocks: [PlanBlock]
    /// Saved blocks on this day that the model leaves out (a completed task's entry, kept as the
    /// record, or one for a task whose month is not loaded). Never shown, never edited, never
    /// considered for overlap, and always written back on save so a save never deletes them.
    public let retained: [PlanBlock]
    private let initial: [PlanBlock]
    private let day: Date
    private let calendar = Calendar(identifier: .gregorian)

    /// - Parameter saved: the day's stored blocks (`PlannerStore.plans(on:)`); those starting on
    ///   `model.day` and not among `model.blocks` (by id) are retained.
    public init(model: DayPlanModel, saved: [PlanBlock] = []) {
        self.blocks = model.blocks
        self.initial = model.blocks
        self.day = model.day
        let shown = Set(model.blocks.map(\.id))
        let calendar = Calendar(identifier: .gregorian)
        self.retained = saved.filter { !shown.contains($0.id) && calendar.isDate($0.start, inSameDayAs: model.day) }
    }

    /// Everything to persist for the day: the edited blocks plus the retained ones.
    public var blocksToSave: [PlanBlock] { blocks + retained }

    /// True when the blocks differ from those the draft started with (order ignored).
    public var hasChanges: Bool {
        Set(blocks.map(Key.init)) != Set(initial.map(Key.init))
    }

    private struct Key: Hashable {
        let id: String, reminderID: String, occurrence: Date, start: Date, minutes: Int
        init(_ b: PlanBlock) {
            id = b.id; reminderID = b.reminderID; occurrence = b.occurrence; start = b.start; minutes = b.minutes
        }
    }

    /// Plans a reminder row at `start` (snapped, shifted to the nearest free slot). A row that
    /// already has a block on this day is moved instead. Events are refused; so is a full day.
    @discardableResult
    public mutating func place(_ item: AgendaItem, at start: Date) -> Bool {
        guard case .reminder(let reminder) = item.kind else { return false }
        if let existing = blocks.first(where: {
            $0.reminderID == reminder.id && calendar.isDate($0.occurrence, inSameDayAs: item.occurrence)
        }) {
            return move(id: existing.id, to: start)
        }
        let block = PlanBlock(reminderID: reminder.id, occurrence: item.occurrence,
                              start: start, minutes: PlanLayout.defaultMinutes)
        guard let placed = PlanLayout.place(block, among: blocks, day: day) else { return false }
        blocks.append(placed)
        return true
    }

    @discardableResult
    public mutating func move(id: String, to start: Date) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return false }
        var moving = blocks[index]
        moving.start = start
        let others = blocks.filter { $0.id != id }
        guard let placed = PlanLayout.place(moving, among: others, day: day) else { return false }
        blocks[index] = placed
        return true
    }

    public mutating func resize(id: String, toMinutes: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let others = blocks.filter { $0.id != id }
        blocks[index] = PlanLayout.resized(blocks[index], toMinutes: toMinutes, among: others, day: day)
    }

    public mutating func remove(id: String) {
        blocks.removeAll { $0.id == id }
    }
}
