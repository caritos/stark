// ios/Sources/StarkKit/Planner/DayHistory.swift
import Foundation

/// A read-only look back at one day's plan: its events, the planned blocks whose task got done,
/// and those whose task did not (missed on a past day, still open today), with numbers.
/// Building it never changes a reminder or a plan.
public struct DayHistory {
    public let day: Date
    /// Single-day timed events on `day` (Skip-marked ones left out, as in the planner).
    public let events: [AgendaItem]
    /// All-day and multi-day events on `day`.
    public let allDayEvents: [AgendaItem]
    public let done: [DayPlanModel.DoneBlock]
    public let open: [OpenBlock]
    public let stats: Stats

    /// A plan block whose task is not completed, with the task's title.
    public struct OpenBlock: Equatable, Identifiable, Sendable {
        public let block: PlanBlock
        public let title: String
        public var id: String { block.id }
        public init(block: PlanBlock, title: String) {
            self.block = block
            self.title = title
        }
    }

    public struct Stats: Equatable, Sendable {
        public var done: Int
        public var open: Int
        public var plannedMinutes: Int
        public var doneMinutes: Int
        public init(done: Int = 0, open: Int = 0, plannedMinutes: Int = 0, doneMinutes: Int = 0) {
            self.done = done
            self.open = open
            self.plannedMinutes = plannedMinutes
            self.doneMinutes = doneMinutes
        }
        /// done / (done + open); nil when nothing was planned.
        public var completion: Double? {
            done + open > 0 ? Double(done) / Double(done + open) : nil
        }
        public var hasPlan: Bool { done + open > 0 }

        static func + (lhs: Stats, rhs: Stats) -> Stats {
            Stats(done: lhs.done + rhs.done, open: lhs.open + rhs.open,
                  plannedMinutes: lhs.plannedMinutes + rhs.plannedMinutes,
                  doneMinutes: lhs.doneMinutes + rhs.doneMinutes)
        }
    }

    /// - A plan is done when its task is completed (`DayPlanModel`'s matching), open when its
    ///   reminder still exists and is not completed, and ignored when the reminder is gone.
    /// - A `day` after `today` is empty.
    public static func make(
        day: Date, events: [Event], reminders: [Reminder], plans: [PlanBlock], today: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> DayHistory {
        let dayStart = calendar.startOfDay(for: day)
        guard dayStart <= calendar.startOfDay(for: today) else {
            return DayHistory(day: day, events: [], allDayEvents: [], done: [], open: [], stats: Stats())
        }
        // Events: the planner's own filtering (skipped left out, banner split, midnight workaround).
        let planner = DayPlanModel.make(day: day, events: events, reminders: [], plans: [], today: today, calendar: calendar)
        let (done, open) = classify(plans.filter { calendar.isDate($0.start, inSameDayAs: dayStart) },
                                    reminders: reminders, calendar: calendar)
        return DayHistory(day: day, events: planner.events, allDayEvents: planner.allDayEvents,
                          done: done, open: open, stats: stats(done: done, open: open))
    }

    /// Totals for the Sunday-Saturday week containing `day` (Weekly Review's week); days after
    /// `today` are ignored.
    public static func weekStats(
        containing day: Date, reminders: [Reminder], plans: [PlanBlock], today: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Stats {
        let dayStart = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: dayStart) // 1 = Sunday
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: dayStart)!
        let week = WeeklyReview.range(forWeekStarting: sunday, calendar: calendar)
        let cutoff = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: today)!)
        let inWeek = plans.filter { week.contains($0.start) && $0.start < cutoff }
        let (done, open) = classify(inWeek, reminders: reminders, calendar: calendar)
        return stats(done: done, open: open)
    }

    private static func classify(
        _ plans: [PlanBlock], reminders: [Reminder], calendar: Calendar
    ) -> (done: [DayPlanModel.DoneBlock], open: [OpenBlock]) {
        var done: [DayPlanModel.DoneBlock] = []
        var open: [OpenBlock] = []
        for plan in plans.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
            if let block = DayPlanModel.doneBlock(for: plan, reminders: reminders, calendar: calendar) {
                done.append(block)
            } else if let r = reminders.first(where: { $0.id == plan.reminderID && !$0.isCompleted }) {
                open.append(OpenBlock(block: plan, title: r.title))
            }
        }
        return (done, open)
    }

    private static func stats(done: [DayPlanModel.DoneBlock], open: [OpenBlock]) -> Stats {
        let doneMinutes = done.reduce(0) { $0 + $1.block.minutes }
        let openMinutes = open.reduce(0) { $0 + $1.block.minutes }
        return Stats(done: done.count, open: open.count,
                     plannedMinutes: doneMinutes + openMinutes, doneMinutes: doneMinutes)
    }

    // MARK: - Text

    /// "3 DONE - 2 MISSED" ("OPEN" on today; a 0 part is left out); nil when nothing was planned.
    public static func summaryLine(stats: Stats, isToday: Bool) -> String? {
        guard stats.hasPlan else { return nil }
        var parts: [String] = []
        if stats.done > 0 { parts.append("\(stats.done) DONE") }
        if stats.open > 0 { parts.append("\(stats.open) \(isToday ? "OPEN" : "MISSED")") }
        return parts.joined(separator: " - ")
    }

    /// "4h", "2h30", "45m".
    public static func minutesText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h" + (m < 10 ? "0\(m)" : "\(m)")
    }

    /// "WEEK: 11 of 16 blocks done - 69%"; nil when the week has no plan.
    public static func weekLine(_ stats: Stats) -> String? {
        guard let completion = stats.completion else { return nil }
        return "WEEK: \(stats.done) of \(stats.done + stats.open) blocks done - \(Int((completion * 100).rounded()))%"
    }
}
