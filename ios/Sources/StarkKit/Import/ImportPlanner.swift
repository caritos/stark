// ios/Sources/StarkKit/Import/ImportPlanner.swift
import Foundation

/// Turns Stark's own local items into the phase 2 import: ordered `ImportStep`s plus the preview's
/// numbers. Pure: no I/O, no EventKit.
///
/// Rules (spec `2026-11-17-apple-import-phase2-design.md`):
/// - An id already in the import ledger (`alreadyImported`) is omitted.
/// - A repeat Apple cannot hold (`RecurrenceDescriptor(_:)` throws) makes the item unrepresentable.
/// - Events are imported whole (start, repeat, exception dates, outcomes), however old.
/// - One-off reminders keep their due date; a completed one is created completed at the time it
///   was ticked (`completedAt`, else `completedDate`).
/// - Completed copies of repeating reminders (`seriesID`) are history: counted, not imported.
/// - A repeating reminder starts at the occurrence the agenda shows today (`buildAgendaItems`:
///   the oldest unresolved miss inside the lookback, else the next one). A fixed `COUNT` keeps
///   only the occurrences from that one on; a series with none left is a finished series.
public enum ImportPlanner {
    public static func plan(events: [Event], reminders: [Reminder], plans: [PlanBlock], alreadyImported: Set<String>,
                            apple: [AgendaItem], today: Date, calendar: Calendar) -> ImportPlan {
        var result = ImportPlan()
        let plansByItem = Dictionary(grouping: plans, by: \.reminderID)

        var eventSteps: [ImportStep] = []
        for event in events where !alreadyImported.contains(event.id) {
            if let rule = event.recurrence, let reason = unrepresentableReason(rule) {
                result.unrepresentable.append((event.id, event.title, reason))
                continue
            }
            var new = ItemRouter.newEvent(event)
            if let end = new.end, end < new.start { new.end = nil }
            if let rule = event.recurrence, skipsShortMonths(rule, anchor: event.start, calendar: calendar) {
                result.shortMonthRepeats.append(event.title)
            }
            eventSteps.append(ImportStep(localID: event.id, kind: .event, event: new,
                                         exceptionDates: event.recurrence == nil ? [] : event.exceptionDates,
                                         outcomes: event.outcomes, title: event.title))
        }

        // History of each series, for `buildAgendaItems`' "a tick closes every earlier gap" rule.
        var copiesBySeries: [String: [Reminder]] = [:]
        var completedByTitle: [String: [Reminder]] = [:]
        for reminder in reminders where reminder.isCompleted {
            if let seriesID = reminder.seriesID { copiesBySeries[seriesID, default: []].append(reminder) }
            else { completedByTitle[reminder.title, default: []].append(reminder) }
        }

        var reminderSteps: [ImportStep] = []
        for reminder in reminders where !alreadyImported.contains(reminder.id) {
            if reminder.isCompleted && reminder.seriesID != nil {
                result.skippedHistoryCount += 1
                continue
            }
            let blocks = plansByItem[reminder.id] ?? []
            guard let rule = reminder.recurrence else {
                var new = ItemRouter.newReminder(reminder, url: nil)
                if reminder.isCompleted {
                    new.completedAt = reminder.completedAt ?? reminder.completedDate ?? reminder.dueDate ?? today
                }
                reminderSteps.append(ImportStep(localID: reminder.id, kind: .reminder, reminder: new, plans: blocks,
                                                title: reminder.title))
                continue
            }
            if let reason = unrepresentableReason(rule) {
                result.unrepresentable.append((reminder.id, reminder.title, reason))
                continue
            }
            guard let due = reminder.dueDate else {
                result.unrepresentable.append((reminder.id, reminder.title, "A repeating reminder needs a due date."))
                continue
            }
            if reminder.isCompleted {
                result.unrepresentable.append((reminder.id, reminder.title,
                                               "A completed repeating reminder can't be created in Apple."))
                continue
            }
            let history = (copiesBySeries[reminder.id] ?? []) + (completedByTitle[reminder.title] ?? [])
            guard let shown = shownOccurrence(of: reminder, history: history, today: today, calendar: calendar),
                  let newRule = remainingRule(rule, startingAt: shown, anchor: due, calendar: calendar) else {
                result.finishedSeries.append(reminder.title)
                continue
            }
            if skipsShortMonths(rule, anchor: due, calendar: calendar) {
                result.shortMonthRepeats.append(reminder.title)
            }
            var moved = reminder
            moved.dueDate = shown
            moved.recurrence = newRule
            moved.exceptionDates = []
            reminderSteps.append(ImportStep(localID: reminder.id, kind: .reminder,
                                            reminder: ItemRouter.newReminder(moved, url: nil), plans: blocks,
                                            title: reminder.title))
        }

        eventSteps.sort { lhs, rhs in
            let l = lhs.event?.start ?? .distantFuture, r = rhs.event?.start ?? .distantFuture
            return l != r ? l < r : lhs.localID < rhs.localID
        }
        reminderSteps.sort { lhs, rhs in
            let l = lhs.reminder?.due ?? .distantFuture, r = rhs.reminder?.due ?? .distantFuture
            return l != r ? l < r : lhs.localID < rhs.localID
        }
        result.steps = eventSteps + reminderSteps
        result.counts = counts(of: result.steps)
        result.probableDuplicates = probableDuplicateCount(result.steps, apple: apple)
        return result
    }

    // MARK: Rules

    /// Why Apple cannot hold `rule`, or nil when it can.
    static func unrepresentableReason(_ rule: RecurrenceRule) -> String? {
        do {
            _ = try RecurrenceDescriptor(rule)
            return nil
        } catch ItemRepositoryError.unrepresentable(let reason) {
            return reason
        } catch {
            return "\(error)"
        }
    }

    /// The occurrence the agenda shows today for a repeating reminder (overdue row first, else the
    /// next one), or nil when the series has nothing left. Searched in a year, then eight years
    /// (a yearly Feb 29 every other year can be that far away).
    static func shownOccurrence(of master: Reminder, history: [Reminder], today: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: today)
        for days in [400, 3000] {
            guard let upper = calendar.date(byAdding: .day, value: days, to: start) else { continue }
            let rows = buildAgendaItems(events: [], reminders: [master] + history, in: start...upper, today: today)
                .filter { item in
                    if case .reminder(let r) = item.kind { return r.id == master.id && !r.isCompleted }
                    return false
                }
            if let overdue = rows.first(where: \.isOverdue) { return overdue.occurrence }
            if let next = rows.map(\.occurrence).min() { return next }
        }
        return nil
    }

    /// `rule` for a series that now starts at `shown` instead of `anchor`: a fixed count keeps
    /// only the occurrences from `shown` on (every earlier match, done, skipped or missed, is used
    /// up, exactly as `OccurrenceExpander` counts them), and a day or month taken from the old
    /// anchor is pinned so a clamped occurrence (Nov 30 of a "31st" series) does not move the
    /// series. Nil when no occurrence is left.
    static func remainingRule(_ rule: RecurrenceRule, startingAt shown: Date, anchor: Date, calendar: Calendar) -> RecurrenceRule? {
        var result = rule
        if let count = rule.count {
            let used = shown > anchor
                ? OccurrenceExpander.occurrences(anchor: anchor, rule: rule, exceptionDates: [],
                                                 in: anchor...shown.addingTimeInterval(-1)).count
                : 0
            let remaining = count - used
            guard remaining >= 1 else { return nil }
            result.count = remaining
        }
        let hasDayRule = !(rule.byMonthDay ?? []).isEmpty || !(rule.byPositionalDay ?? []).isEmpty
        let anchorDay = calendar.component(.day, from: anchor)
        switch rule.frequency {
        case .monthly where !hasDayRule && calendar.component(.day, from: shown) != anchorDay:
            result.byMonthDay = [anchorDay]
        case .yearly where !hasDayRule && calendar.component(.day, from: shown) != anchorDay:
            result.byMonthDay = [anchorDay]
            if (rule.byMonth ?? []).isEmpty, let month = Month(rawValue: calendar.component(.month, from: anchor)) {
                result.byMonth = [month]
            }
        default:
            break
        }
        return result
    }

    /// A monthly repeat on day 29-31, or a yearly one on a day some of its months lack (Feb 29):
    /// Apple skips those months where Stark clamped. "Last day of the month" (positional) is not.
    static func skipsShortMonths(_ rule: RecurrenceRule, anchor: Date, calendar: Calendar) -> Bool {
        guard (rule.byPositionalDay ?? []).isEmpty else { return false }
        let monthDays = rule.byMonthDay.flatMap { $0.isEmpty ? nil : $0 } ?? [calendar.component(.day, from: anchor)]
        switch rule.frequency {
        case .daily, .weekly:
            return false
        case .monthly:
            return monthDays.contains { $0 >= 29 }
        case .yearly:
            let months = rule.byMonth.flatMap { $0.isEmpty ? nil : $0.map(\.rawValue) }
                ?? [calendar.component(.month, from: anchor)]
            return months.contains { month in monthDays.contains { $0 > shortestLength(ofMonth: month) } }
        }
    }

    /// The fewest days `month` (1...12) ever has.
    private static func shortestLength(ofMonth month: Int) -> Int {
        switch month {
        case 2: return 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    // MARK: Preview numbers

    private static func counts(of steps: [ImportStep]) -> ImportCounts {
        var counts = ImportCounts()
        for step in steps {
            if step.event?.recurrence != nil || step.reminder?.recurrence != nil {
                counts.recurringMasters += 1
            } else if step.kind == .event {
                counts.events += 1
            } else if step.reminder?.completedAt != nil {
                counts.completedReminders += 1
            } else {
                counts.openReminders += 1
            }
            counts.planBlocks += step.plans.count
            counts.outcomes += step.outcomes.count
        }
        return counts
    }

    /// Steps whose trimmed, case-insensitive title and start/due time (within one minute) match an
    /// Apple item already loaded. Informational only; an undated step never matches.
    static func probableDuplicateCount(_ steps: [ImportStep], apple: [AgendaItem]) -> Int {
        let appleByTitle = Dictionary(grouping: apple, by: { normalized($0.title) })
        return steps.filter { step in
            guard let date = step.event?.start ?? step.reminder?.due,
                  let candidates = appleByTitle[normalized(step.title)] else { return false }
            return candidates.contains { abs($0.occurrence.timeIntervalSince(date)) <= 60 }
        }.count
    }

    private static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
