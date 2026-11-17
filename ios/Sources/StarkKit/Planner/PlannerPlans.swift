// ios/Sources/StarkKit/Planner/PlannerPlans.swift
import Foundation

/// What the planner passes to `DayPlanModel.make` / `PlanDraft`, from its one plan source: the
/// sidecar's blocks of Apple reminders (`PlanCache`, reminderID = model id `apple-<identifier>`).
/// Stark keeps no plans of its own since phase 3, so no other block can be drafted, edited or
/// silently dropped on save. Every block is passed once (`DayPlanModel.combinedPlans` dedupes,
/// but nothing here relies on it).
public enum PlannerPlans {
    /// `make`'s `plans:` and `sidecarPlans:`. `draftBlocks` (the viewed day's unsaved draft)
    /// replace every saved block starting on `day`; nil uses the saved ones.
    public static func forModel(day: Date, apple: [PlanBlock], draftBlocks: [PlanBlock]?,
                                calendar: Calendar = Calendar(identifier: .gregorian))
        -> (plans: [PlanBlock], sidecarPlans: [PlanBlock]) {
        guard let draftBlocks else { return ([], apple) }
        return (draftBlocks, apple.filter { !calendar.isDate($0.start, inSameDayAs: day) })
    }

    /// The day's saved blocks (`PlanDraft`'s `saved:`), so a save writes back a block the model
    /// leaves out (its list hidden, say) instead of dropping it.
    public static func saved(on day: Date, apple: [PlanBlock],
                             calendar: Calendar = Calendar(identifier: .gregorian)) -> [PlanBlock] {
        apple.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }
}
