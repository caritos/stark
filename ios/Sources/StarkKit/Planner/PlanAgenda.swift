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
/// Duplicates: if several plans exist for one occurrence, only the first in `plans` order is
/// used (the others are ignored); the store / `PlanDraft` must prevent duplicates.
///
/// The plan never changes the reminder itself. The result is re-sorted with the agenda's own
/// order (`sortAgendaItems`); planned rows sort among that day's incomplete rows at their planned
/// time. When no plan matches (including an empty `plans`), `items` is returned unchanged.
///
/// Tasks planned from outside the window: a live plan that matched no row in `items` is looked up
/// in `reminders`. An open ONE-OFF reminder (no recurrence, not completed) with that id, not listed
/// in `items` at all, whose due date is on the plan's occurrence day gets a synthesized planned row
/// (`occurrence` = due date, `displayDate = plan.start`, overdue when due before today's day).
/// This covers a one-off due beyond the agenda's window or the overdue lookback, which the tray
/// offers but `buildAgendaItems` never lists. Recurring reminders are never synthesized.
public func applyPlans(_ items: [AgendaItem], plans: [PlanBlock], today: Date,
                       reminders: [Reminder] = [],
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
    if !live.isEmpty && !reminders.isEmpty {
        // Each reminder is synthesized at most once, and never when `items` already lists it
        // (then a leftover plan is a duplicate, ignored as above).
        var listed = Set(items.compactMap { item -> String? in
            if case .reminder(let r) = item.kind { return r.id } else { return nil }
        })
        let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for plan in live {
            guard let r = byID[plan.reminderID], !r.isCompleted, r.recurrence == nil,
                  let due = r.dueDate, calendar.isDate(due, inSameDayAs: plan.occurrence),
                  listed.insert(r.id).inserted
            else { continue }
            result.append(AgendaItem(kind: .reminder(r), occurrence: due, displayDate: plan.start,
                                     isOverdue: calendar.startOfDay(for: due) < todayStart, plan: plan))
            changed = true
        }
    }
    return changed ? sortAgendaItems(result, calendar: calendar) : items
}
