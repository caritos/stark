import Foundation

public struct CompletionEntry: Equatable {
    /// The occurrence's due date.
    public let due: Date
    /// When it was marked done; nil for old records.
    public let done: Date?
    /// Whole days done-day minus due-day, min 0; 0 when `done` is nil.
    public let daysLate: Int

    public init(due: Date, done: Date?, daysLate: Int) {
        self.due = due
        self.done = done
        self.daysLate = daysLate
    }
}

public struct CompletionHistory: Equatable {
    public let entries: [CompletionEntry]
    public let doneLast30: Int
    public let doneLast90: Int
    public let lateLast90: Int
    public let lastDone: Date?
    public let averageGapDays: Double?
    public let longestGapDays: Int?

    public static func forReminder(_ reminder: Reminder, among reminders: [Reminder], today: Date,
                                   calendar: Calendar = Calendar(identifier: .gregorian)) -> CompletionHistory {
        let masterID = reminder.seriesID ?? (reminder.recurrence != nil ? reminder.id : nil)
        let raw = reminders.filter { r in
            guard r.isCompleted else { return false }
            if let masterID, r.seriesID == masterID { return true }
            return r.seriesID == nil && r.title == reminder.title
        }.compactMap { r -> (due: Date, done: Date?)? in
            guard let due = r.dueDate ?? r.completedDate else { return nil }
            return (due: due, done: r.completedAt)
        }
        return build(raw, today: today, calendar: calendar)
    }

    public static func forEvent(_ event: Event, today: Date,
                                calendar: Calendar = Calendar(identifier: .gregorian)) -> CompletionHistory {
        let raw = event.outcomes.filter { $0.outcome == .attended }
            .map { (due: $0.date, done: $0.recordedAt) }
        return build(raw, today: today, calendar: calendar)
    }

    private static func build(_ raw: [(due: Date, done: Date?)], today: Date, calendar: Calendar) -> CompletionHistory {
        let entries = raw.map { r -> CompletionEntry in
            let late = r.done.map {
                max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: r.due),
                                               to: calendar.startOfDay(for: $0)).day ?? 0)
            } ?? 0
            return CompletionEntry(due: r.due, done: r.done, daysLate: late)
        }.sorted { ($0.done ?? $0.due) > ($1.done ?? $1.due) }
        let todayStart = calendar.startOfDay(for: today)
        func within(_ days: Int, _ e: CompletionEntry) -> Bool {
            let day = calendar.startOfDay(for: e.done ?? e.due)
            guard let from = calendar.date(byAdding: .day, value: -days, to: todayStart) else { return false }
            return day >= from && day <= todayStart
        }
        let uniqueDays = Array(Set(entries.map { calendar.startOfDay(for: $0.done ?? $0.due) })).sorted()
        let gaps = zip(uniqueDays, uniqueDays.dropFirst()).map {
            calendar.dateComponents([.day], from: $0, to: $1).day ?? 0
        }
        return CompletionHistory(
            entries: entries,
            doneLast30: entries.filter { within(30, $0) }.count,
            doneLast90: entries.filter { within(90, $0) }.count,
            lateLast90: entries.filter { within(90, $0) && $0.daysLate > 0 }.count,
            lastDone: entries.first.map { $0.done ?? $0.due },
            averageGapDays: gaps.isEmpty ? nil : Double(gaps.reduce(0, +)) / Double(gaps.count),
            longestGapDays: gaps.max()
        )
    }

    // MARK: Plain-text summary (kept out of the view so it is testable)

    /// Stat lines followed by up to `maxEntries` entry lines, newest first.
    public func summaryLines(maxEntries: Int = 10) -> [String] {
        var lines = ["Last 30 days: \(doneLast30)"]
        lines.append(lateLast90 > 0 ? "Last 90 days: \(doneLast90) (\(lateLast90) late)"
                                    : "Last 90 days: \(doneLast90)")
        if let lastDone { lines.append("Last done: \(Self.monthDay(lastDone))") }
        if let averageGapDays { lines.append("Average gap: \(String(format: "%.1f", averageGapDays)) days") }
        if let longestGapDays { lines.append("Longest gap: \(longestGapDays) days") }
        lines.append(contentsOf: entries.prefix(maxEntries).map(\.line))
        return lines
    }

    fileprivate static func monthDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

extension CompletionEntry {
    /// "Due Sep 14", or "Due Sep 14 · done Sep 16 (2 days late)".
    public var line: String {
        var text = "Due \(CompletionHistory.monthDay(due))"
        if let done {
            text += " · done \(CompletionHistory.monthDay(done))"
            if daysLate > 0 { text += " (\(daysLate) \(daysLate == 1 ? "day" : "days") late)" }
        }
        return text
    }
}
