// ios/Sources/StarkKit/Planner/PlanAgenda.swift
import Foundation

/// Merges timeboxing plans into agenda rows built by `buildAgendaItems`.
///
/// A plan matches an OPEN reminder row (not completed; events never match) whose reminder id is
/// `plan.reminderID` and whose `occurrence` is on the same calendar day as `plan.occurrence`. Each
/// plan matches at most one row, and each row takes at most one plan (the first in `plans`).
/// Plans whose start day is before `today`'s day have lapsed and are ignored.
///
/// - If the row's `displayDate` is on the plan's day, the row is REPLACED by a planned copy
///   (`displayDate = plan.start`, `plan` set): one row per day, never two.
/// - Otherwise the original row is KEPT (a task planned for tomorrow still shows on today's row)
///   and a planned copy is ADDED on the plan's day, keeping `occurrence` and `isOverdue` so the
///   "due Sep 19" label survives.
///
/// The plan never changes the reminder itself. The result is re-sorted with the agenda's own
/// order (`sortAgendaItems`); planned rows sort among that day's incomplete rows at their planned
/// time. When no plan matches (including an empty `plans`), `items` is returned unchanged.
public func applyPlans(_ items: [AgendaItem], plans: [PlanBlock], today: Date,
                       calendar: Calendar = Calendar(identifier: .gregorian)) -> [AgendaItem] {
    let todayStart = calendar.startOfDay(for: today)
    var live = plans.filter { calendar.startOfDay(for: $0.start) >= todayStart }
    guard !live.isEmpty else { return items }

    var result: [AgendaItem] = []
    result.reserveCapacity(items.count + live.count)
    var changed = false
    for item in items {
        guard item.plan == nil, !item.isCompleted, case .reminder(let reminder) = item.kind,
              let index = live.firstIndex(where: {
                  $0.reminderID == reminder.id && calendar.isDate($0.occurrence, inSameDayAs: item.occurrence)
              })
        else {
            result.append(item)
            continue
        }
        let plan = live.remove(at: index)
        if !calendar.isDate(item.displayDate, inSameDayAs: plan.start) {
            result.append(item)
        }
        result.append(AgendaItem(kind: item.kind, occurrence: item.occurrence, displayDate: plan.start,
                                 isOverdue: item.isOverdue, plan: plan))
        changed = true
    }
    return changed ? sortAgendaItems(result, calendar: calendar) : items
}
