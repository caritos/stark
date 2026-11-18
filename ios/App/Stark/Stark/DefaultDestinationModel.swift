//
//  DefaultDestinationModel.swift
//  Stark
//
//  Where new Apple items go: the default calendar for events and the default list for reminders,
//  chosen in Settings. Ids only in UserDefaults. The choice logic is StarkKit's
//  `DefaultDestination` (tested there); this holds the state and reads EventKit off the main actor.
//

import Foundation
import Observation
import StarkKit

@MainActor @Observable
final class DefaultDestinationModel: DefaultDestinations {
    private enum Key {
        static let calendar = StoredKeys.defaultCalendar
        static let list = StoredKeys.defaultList
    }

    /// The effective destinations (nil when nothing writable exists or access is not granted yet).
    private(set) var calendarID: String?
    private(set) var listID: String?
    /// The pickers' choices: writable calendars and writable lists only.
    private(set) var calendarChoices: [AppleCalendarInfo] = []
    private(set) var listChoices: [AppleCalendarInfo] = []
    /// Shown in Settings and on the main screen when there is nowhere to add to.
    private(set) var error: String?

    @ObservationIgnored private let provider: EventKitProvider
    @ObservationIgnored private let repository: any ItemRepository
    @ObservationIgnored private let defaults: UserDefaults
    /// Makes a calendar or list visible in the overlay (the default ones are never hidden, so an
    /// item added in Stark never vanishes from view). `AppleOverlayModel.setShown(_:true)`.
    @ObservationIgnored private let keepShown: (String) -> Void

    init(provider: EventKitProvider, repository: any ItemRepository, defaults: UserDefaults = .standard,
         keepShown: @escaping (String) -> Void) {
        self.provider = provider
        self.repository = repository
        self.defaults = defaults
        self.keepShown = keepShown
    }

    /// Re-reads the writable calendars and EventKit's defaults and resolves both destinations.
    /// Does nothing (and touches no `EKEventStore`) until access is granted.
    func refresh() async {
        guard provider.accessState() == .granted else { return }
        let provider = self.provider
        let calendars: [AppleCalendarInfo]
        do {
            calendars = try await repository.writableCalendars()
        } catch {
            self.error = "Stark couldn't read your calendars and lists. Try again in a moment."
            return
        }
        // Synchronous EventKit read: run it on the concurrent pool.
        let system = await Task.detached { provider.systemDefaultIDs() }.value
        calendarChoices = DefaultDestination.choices(calendars, reminderLists: false)
        listChoices = DefaultDestination.choices(calendars, reminderLists: true)
        calendarID = resolve(Key.calendar, system: system.calendarID, in: calendars, reminderLists: false)
        listID = resolve(Key.list, system: system.listID, in: calendars, reminderLists: true)
        error = DefaultDestination.problem(calendarID: calendarID, listID: listID)
        // Also covers a default hidden before the toggles were locked on.
        for id in [calendarID, listID].compactMap({ $0 }) { keepShown(id) }
    }

    func chooseCalendar(_ id: String) {
        defaults.set(id, forKey: Key.calendar)
        keepShown(id)
        calendarID = id
        error = DefaultDestination.problem(calendarID: calendarID, listID: listID)
    }

    func chooseList(_ id: String) {
        defaults.set(id, forKey: Key.list)
        keepShown(id)
        listID = id
        error = DefaultDestination.problem(calendarID: calendarID, listID: listID)
    }

    private func resolve(_ key: String, system: String?, in calendars: [AppleCalendarInfo],
                         reminderLists: Bool) -> String? {
        let resolution = DefaultDestination.resolve(stored: defaults.string(forKey: key), systemDefault: system,
                                                    in: calendars, reminderLists: reminderLists)
        if resolution.persist, let id = resolution.id { defaults.set(id, forKey: key) }
        return resolution.id
    }
}
