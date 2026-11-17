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
///
/// Apple reminders: a planned copy of an Apple row (`appleSource` set, id `apple-<identifier>`)
/// keeps its `appleSource`. `apple` (default empty) adds the snapshot's open DATED reminders to
/// the synthesis lookup above, as one-offs (an Apple reminder carries no recurrence: it is
/// Apple's single open occurrence); a synthesized row carries its `AppleSource`. An open undated
/// Apple reminder appears only when PLANNED (a plan with the `.distantFuture` occurrence the
/// planner's "No date" rows carry, matched by id): one planned row on `plan.start`, not overdue,
/// occurrence `.distantFuture`. Unplanned ones stay out of the agenda (spec Decision 3).
public func applyPlans(_ items: [AgendaItem], plans: [PlanBlock], today: Date,
                       reminders: [Reminder] = [], apple: AppleSnapshot = .empty,
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
        let planned = AgendaItem(kind: item.kind, occurrence: item.occurrence, displayDate: plan.start,
                                 isOverdue: item.isOverdue, plan: plan, appleSource: item.appleSource)
        result.append(planned)
        changed = true
    }
    // Open dated Apple reminders as synthetic one-offs, with their source.
    var appleSources: [String: AppleSource] = [:]
    var lookup = reminders
    for a in apple.reminders where !a.isCompleted && a.due != nil {
        let (r, source) = appleReminderValue(a, calendar: calendar)
        lookup.append(r)
        appleSources[r.id] = source
    }
    if !live.isEmpty && !lookup.isEmpty {
        // Each reminder is synthesized at most once, and never when `items` already lists it
        // (then a leftover plan is a duplicate, ignored as above).
        var listed = Set(items.compactMap { item -> String? in
            if case .reminder(let r) = item.kind { return r.id } else { return nil }
        })
        let byID = Dictionary(lookup.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for plan in live {
            guard let r = byID[plan.reminderID], !r.isCompleted, r.recurrence == nil,
                  let due = r.dueDate, calendar.isDate(due, inSameDayAs: plan.occurrence),
                  listed.insert(r.id).inserted
            else { continue }
            result.append(AgendaItem(kind: .reminder(r), occurrence: due, displayDate: plan.start,
                                     isOverdue: calendar.startOfDay(for: due) < todayStart, plan: plan,
                                     appleSource: appleSources[r.id]))
            changed = true
        }
    }
    // A PLANNED undated Apple reminder shows on its planned day like any planned task (unplanned
    // ones stay out of the agenda, spec Decision 3). The planner plans the "No date" row, whose
    // occurrence is the `.distantFuture` sentinel, so only such plans match; by id, open only.
    let undatedPlans = live.filter { $0.occurrence == .distantFuture }
    if !undatedPlans.isEmpty {
        var listed = Set(result.compactMap { item -> String? in
            if case .reminder(let r) = item.kind { return r.id } else { return nil }
        })
        let undated = Dictionary(
            apple.reminders.filter { !$0.isCompleted && $0.due == nil }
                .map { a -> (String, (Reminder, AppleSource)) in
                    let value = appleReminderValue(a, calendar: calendar)
                    return (value.0.id, value)
                },
            uniquingKeysWith: { first, _ in first })
        for plan in undatedPlans {
            guard let (r, source) = undated[plan.reminderID], listed.insert(r.id).inserted else { continue }
            result.append(AgendaItem(kind: .reminder(r), occurrence: .distantFuture, displayDate: plan.start,
                                     isOverdue: false, plan: plan, appleSource: source))
            changed = true
        }
    }
    return changed ? sortAgendaItems(result, calendar: calendar) : items
}

/// The agenda's rows with Apple items and plans, in the one correct order: Apple rows are merged
/// into `local` FIRST (`mergeAppleItems` over `range`), THEN plans are applied (`applyPlans`, with
/// `snapshot` for Apple reminders outside the window). Applying plans first would let an Apple
/// reminder planned on its own day be listed twice (the planned copy plus the merged row).
///
/// - `local`: `buildAgendaItems` over `range`, no plans applied yet (the app passes `[]` since
///   phase 3: Stark keeps no items of its own; engine tests still use it).
/// - `plans`: every plan block (the app's are the sidecar's, reminderID = model id), each once.
/// - `reminders`: local reminders, for synthesizing a planned one-off outside the window (none in
///   the app since phase 3).
/// - With an empty snapshot the result is exactly `applyPlans(local, ...)`.
///
/// AgendaView and the density functions call this instead of composing the two themselves.
public func agendaWithApple(local: [AgendaItem], snapshot: AppleSnapshot, plans: [PlanBlock],
                            range: ClosedRange<Date>, today: Date, reminders: [Reminder] = [],
                            calendar: Calendar = Calendar(identifier: .gregorian)) -> [AgendaItem] {
    let merged = snapshot == .empty
        ? local
        : mergeAppleItems(local, snapshot: snapshot, in: range, today: today, calendar: calendar)
    return applyPlans(merged, plans: plans, today: today, reminders: reminders, apple: snapshot, calendar: calendar)
}
