// ios/Sources/StarkKit/Planner/AgendaDays.swift
import Foundation

/// One calendar day of the agenda: its start-of-day and the items shown under it.
public struct AgendaDay: Equatable {
    public let day: Date
    public let items: [AgendaItem]

    public init(day: Date, items: [AgendaItem]) {
        self.day = day
        self.items = items
    }
}

/// Groups agenda items by calendar day over `range`, producing **one entry for every day** from
/// `startOfDay(range.lowerBound)` through `startOfDay(range.upperBound)` inclusive (ascending),
/// whether or not the day has items. A day-per-entry list is what lets the month grid scroll the
/// agenda to any tapped day, not just days that happen to have items.
///
/// Items are placed by the start of their `displayDate`'s day and keep their incoming order
/// within a day (`buildAgendaItems` has already sorted them). Items whose day isn't in the range
/// are dropped — notably an overdue-pinned reminder (its `displayDate` is the real today) when
/// the range has been re-centred away from today.
///
/// Days are stepped with the calendar, not by adding 86 400 seconds, so a DST day of 23 or 25
/// hours still yields exactly one entry.
public func groupAgendaByDay(
    _ items: [AgendaItem],
    in range: ClosedRange<Date>,
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> [AgendaDay] {
    var days: [Date] = []
    var day = calendar.startOfDay(for: range.lowerBound)
    let last = calendar.startOfDay(for: range.upperBound)
    while day <= last {
        days.append(day)
        // Re-normalise with startOfDay: in a zone where midnight doesn't exist on a DST day,
        // adding a day lands on 01:00, which must still be keyed as that day's start.
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        let nextStart = calendar.startOfDay(for: next)
        guard nextStart > day else { break }
        day = nextStart
    }

    var grouped: [Date: [AgendaItem]] = [:]
    for item in items {
        grouped[calendar.startOfDay(for: item.displayDate), default: []].append(item)
    }
    return days.map { AgendaDay(day: $0, items: grouped[$0] ?? []) }
}
