// ios/Sources/StarkKit/Apple/AppleFetchWindow.swift
import Foundation

/// The date range the Apple overlay must fetch. The agenda, the month grid and the year view each
/// show their own range but share one snapshot, so a reload for one screen must not narrow the
/// data another screen on display needs: the fetch covers the hull of every screen's range. A
/// screen that goes away releases its range (`set(_, nil)`) so the hull can shrink again.
public struct AppleFetchWindow: Equatable, Sendable {
    public enum Screen: Hashable, Sendable {
        case agenda
        case monthGrid
        case year
        /// The Search sheet while it is open (`SearchWindow`, two years either side of today).
        case search
        /// The planner while it is open: the viewed day's `PlannerDays.loadRange`, so Apple
        /// reminders and completed copies exist for that day and its week line.
        case planner
        /// Weekly Review while it is open: the reviewed week (the overlay adds the reminder
        /// lookback), so completions exist for weeks older than the agenda's window.
        case weeklyReview
    }

    private var ranges: [Screen: ClosedRange<Date>] = [:]

    public init() {}

    public mutating func set(_ screen: Screen, _ range: ClosedRange<Date>?) {
        ranges[screen] = range
    }

    /// The smallest range covering every screen's range; nil when no screen needs data.
    public var covering: ClosedRange<Date>? {
        guard let lower = ranges.values.map(\.lowerBound).min(),
              let upper = ranges.values.map(\.upperBound).max() else { return nil }
        return lower...upper
    }
}
