// ios/App/Stark/Stark/AgendaRow.swift
import Foundation
import StarkKit

enum AgendaItem: Identifiable {
    case event(Event, occurrence: Date)
    case reminder(Reminder, occurrence: Date)

    var id: String {
        switch self {
        case .event(let e, let occurrence): return "\(e.id)-\(occurrence.timeIntervalSince1970)"
        case .reminder(let r, let occurrence): return "\(r.id)-\(occurrence.timeIntervalSince1970)"
        }
    }

    var occurrence: Date {
        switch self {
        case .event(_, let occurrence), .reminder(_, let occurrence): return occurrence
        }
    }

    var title: String {
        switch self {
        case .event(let e, _): return e.title
        case .reminder(let r, _): return r.title
        }
    }
}

/// Expands every event/reminder into concrete dated occurrences within `range`,
/// then sorts by date. The single source of truth `AgendaView` and `MonthGridView`
/// both build on — never duplicate this expansion logic in a view.
func buildAgendaItems(events: [Event], reminders: [Reminder], in range: ClosedRange<Date>) -> [AgendaItem] {
    var items: [AgendaItem] = []
    for event in events {
        for occurrence in OccurrenceExpander.expand(event: event, in: range) {
            items.append(.event(event, occurrence: occurrence))
        }
    }
    for reminder in reminders {
        for occurrence in OccurrenceExpander.expand(reminder: reminder, in: range) {
            items.append(.reminder(reminder, occurrence: occurrence))
        }
    }
    return items.sorted { $0.occurrence < $1.occurrence }
}
