// ios/Sources/StarkKit/Planner/PlannerPlans.swift
import Foundation

/// What the planner passes to `DayPlanModel.make` / `PlanDraft` / `PlanSession`, from its two
/// plan sources: `local` (Stark's own blocks, `PlannerStore.plans`) and `apple` (Apple reminders'
/// blocks from the sidecar, `PlanCache`, reminderID = model id `apple-<identifier>`). Every block
/// is passed once (`DayPlanModel.combinedPlans` dedupes, but nothing here relies on it). With no
/// Apple blocks every result is exactly what the planner passed before Task 9b.
public enum PlannerPlans {
    /// `make`'s `plans:` and `sidecarPlans:`. `draftBlocks` (the viewed day's unsaved draft, local
    /// and Apple blocks together) replace every saved block starting on `day`; nil uses the saved ones.
    public static func forModel(day: Date, local: [PlanBlock], apple: [PlanBlock], draftBlocks: [PlanBlock]?,
                                calendar: Calendar = Calendar(identifier: .gregorian))
        -> (plans: [PlanBlock], sidecarPlans: [PlanBlock]) {
        guard let draftBlocks else { return (local, apple) }
        func elsewhere(_ block: PlanBlock) -> Bool { !calendar.isDate(block.start, inSameDayAs: day) }
        return (local.filter(elsewhere) + draftBlocks, apple.filter(elsewhere))
    }

    /// The day's saved blocks from both sources (`PlanDraft`'s `saved:`), so a save writes back an
    /// Apple block the model leaves out (its list hidden, say) instead of dropping it.
    public static func saved(on day: Date, local: [PlanBlock], apple: [PlanBlock],
                             calendar: Calendar = Calendar(identifier: .gregorian)) -> [PlanBlock] {
        (local + apple).filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    /// Every saved block (`PlanSession.plannedElsewhere`'s `saved:`, densities).
    public static func all(local: [PlanBlock], apple: [PlanBlock]) -> [PlanBlock] {
        local + apple
    }
}
