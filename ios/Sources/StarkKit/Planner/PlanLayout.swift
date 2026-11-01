import Foundation

/// Placement rules for timeboxing plan blocks: 15 minute snapping, no overlap
/// between blocks, nothing crossing midnight. Pure functions; only `PlanBlock`s
/// take part (calendar events never block placement).
public enum PlanLayout {
    public static let defaultMinutes = 30
    public static let minMinutes = 15
    public static let snapMinutes = 15

    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    /// Rounds to the nearest quarter hour of the date's day (halfway rounds up).
    public static func snap(_ date: Date) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let step = TimeInterval(snapMinutes * 60)
        let offset = date.timeIntervalSince(dayStart)
        return dayStart.addingTimeInterval((offset / step).rounded() * step)
    }

    /// Returns `block` snapped to the quarter hour, clamped inside `day` (it may end
    /// exactly at midnight but never cross it) and moved to the nearest slot that
    /// overlaps none of `others`. Distance is measured between start times; when two
    /// free slots are equally near, the EARLIER one wins. Blocks that merely touch
    /// (one ends when the next starts) do not overlap. The caller must leave the block
    /// being moved out of `others`. Minutes are kept (at least `minMinutes`); returns
    /// nil when no free slot of that length exists in the day.
    public static func place(_ block: PlanBlock, among others: [PlanBlock], day: Date) -> PlanBlock? {
        let cal = calendar
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let minutes = max(minMinutes, block.minutes)
        let length = TimeInterval(minutes * 60)
        let step = TimeInterval(snapMinutes * 60)
        let lastStart = dayEnd.addingTimeInterval(-length)
        guard lastStart >= dayStart else { return nil }

        var desired = snap(block.start)
        desired = min(max(desired, dayStart), lastStart)

        var best: Date?
        var bestDistance = TimeInterval.infinity
        var candidate = dayStart
        while candidate <= lastStart {
            let end = candidate.addingTimeInterval(length)
            let free = !others.contains { $0.start < end && candidate < $0.end }
            if free {
                let distance = abs(candidate.timeIntervalSince(desired))
                // Ascending scan, so strict < keeps the earlier slot on a tie.
                if distance < bestDistance {
                    best = candidate
                    bestDistance = distance
                }
            }
            candidate = candidate.addingTimeInterval(step)
        }
        guard let start = best else { return nil }
        var placed = block
        placed.start = start
        placed.minutes = minutes
        return placed
    }

    /// Returns `block` with a new length: snapped to the quarter hour, at least
    /// `minMinutes`, and no longer than the room before the next block that starts
    /// at or after it, or midnight. The start never moves.
    public static func resized(_ block: PlanBlock, toMinutes: Int, among others: [PlanBlock], day: Date) -> PlanBlock {
        let cal = calendar
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        var limit = dayEnd
        for other in others where other.start >= block.start && other.start < limit {
            limit = other.start
        }
        let room = Int(limit.timeIntervalSince(block.start) / 60)
        let maxMinutes = max(minMinutes, room / snapMinutes * snapMinutes)
        let snapped = Int((Double(toMinutes) / Double(snapMinutes)).rounded()) * snapMinutes
        var result = block
        result.minutes = min(max(snapped, minMinutes), maxMinutes)
        return result
    }
}
