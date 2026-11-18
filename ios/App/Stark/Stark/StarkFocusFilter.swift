//
//  StarkFocusFilter.swift
//  Stark
//
//  The Focus filter (Settings > Focus > a Focus > Add Filter > Stark): a saved calendar set to
//  show while that Focus is on. `perform()` goes through UserDefaults only (`FocusFilterStore`);
//  it never touches the app's main-actor models. The rules are StarkKit's `FocusFilter`.
//

import AppIntents
import Foundation
import StarkKit

/// A saved calendar set, as the Focus filter's parameter lists it.
nonisolated struct CalendarSetEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Calendar Set")
    static let defaultQuery = CalendarSetQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated struct CalendarSetQuery: EntityQuery {
    private func all() -> [CalendarSetEntity] {
        FocusFilterStore().sets.sets.map { CalendarSetEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [UUID]) async throws -> [CalendarSetEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CalendarSetEntity] {
        all()
    }
}

nonisolated struct StarkFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Calendar Set"
    static let description: IntentDescription? = IntentDescription(
        "Show only the calendars of a saved calendar set while this Focus is on.")

    /// nil means "don't change calendars"; iOS also runs the filter without it when the Focus ends.
    @Parameter(title: "Calendar Set")
    var calendarSet: CalendarSetEntity?

    var displayRepresentation: DisplayRepresentation {
        if let calendarSet {
            return DisplayRepresentation(title: "\(calendarSet.name)", subtitle: "Calendar set")
        }
        return DisplayRepresentation(title: "Calendars unchanged")
    }

    func perform() async throws -> some IntentResult {
        let store = FocusFilterStore()
        if let calendarSet {
            let provider = EventKitProvider()
            // Never prompts: without access (or before any calendar exists) nothing changes.
            let allIDs = provider.accessState() == .granted ? Set(provider.calendars().map(\.id)) : []
            store.turnOn(setID: calendarSet.id, allIDs: allIDs)
        } else {
            store.turnOff()
        }
        return .result()
    }
}
