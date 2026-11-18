//
//  FocusFilterStore.swift
//  Stark
//
//  The Focus filter's persistence: reads and writes the same UserDefaults keys the app's models
//  use (the excluded calendar ids, the saved sets, the default calendar and list) plus the
//  filter's own memory (`focusFilter.v1`). Nonisolated and UI-free so the intent's `perform()`
//  never touches a main-actor model; the running app re-reads the selection when it becomes
//  active or when `didChange` is posted. The rules are StarkKit's `FocusFilter` (tested there).
//

import Foundation
import StarkKit
import WidgetKit

/// The UserDefaults keys shared by the app's models and the Focus filter (nonisolated, so the
/// intent can read them off the main actor).
nonisolated enum StoredKeys {
    static let excludedCalendars = "appleOverlay.excludedCalendarIDs"
    static let calendarSets = "calendarSets.v1"
    static let defaultCalendar = "appleWrite.defaultCalendarID"
    static let defaultList = "appleWrite.defaultListID"
    static let focusFilter = "focusFilter.v1"
}

nonisolated struct FocusFilterStore {
    /// Posted after the Focus filter changed the stored selection, so a running app re-reads it.
    static let didChange = Notification.Name("com.caritos.stark.focusFilterDidChange")

    let defaults: UserDefaults
    let widgetDefaults: UserDefaults?

    init(defaults: UserDefaults = .standard,
         widgetDefaults: UserDefaults? = UserDefaults(suiteName: SelectionMirror.suiteName)) {
        self.defaults = defaults
        self.widgetDefaults = widgetDefaults
    }

    var excluded: Set<String> {
        Set(defaults.stringArray(forKey: StoredKeys.excludedCalendars) ?? [])
    }

    var state: FocusFilterState? {
        FocusFilterState.decode(defaults.data(forKey: StoredKeys.focusFilter))
    }

    var sets: CalendarSets {
        CalendarSets.decode(defaults.data(forKey: StoredKeys.calendarSets))
    }

    /// The stored default calendar and list (always shown). When unset the system default is not
    /// known here; the app's next `CalendarSetsModel.sync()` re-applies the active set.
    var alwaysShown: Set<String> {
        Set([defaults.string(forKey: StoredKeys.defaultCalendar),
             defaults.string(forKey: StoredKeys.defaultList)].compactMap { $0 })
    }

    /// Writes the selection the app reads, mirrors it for the widget and reloads the widget.
    func writeExcluded(_ ids: Set<String>) {
        defaults.set(ids.sorted(), forKey: StoredKeys.excludedCalendars)
        if let widgetDefaults { SelectionMirror.write(ids, to: widgetDefaults) }
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func writeState(_ state: FocusFilterState?) {
        if let state {
            defaults.set(state.encoded(), forKey: StoredKeys.focusFilter)
        } else {
            defaults.removeObject(forKey: StoredKeys.focusFilter)
        }
    }

    /// A Focus with a set turned on. `allIDs` empty (no access or no calendars) changes nothing.
    func turnOn(setID: UUID, allIDs: Set<String>) {
        guard let result = FocusFilter.turnOn(setID: setID, current: excluded, state: state, sets: sets,
                                              allIDs: allIDs, alwaysShown: alwaysShown) else { return }
        writeState(result.state)
        if result.selection != excluded { writeExcluded(result.selection) }
    }

    /// The Focus turned off, or its filter has no set chosen.
    func turnOff() {
        let result = FocusFilter.turnOff(current: excluded, state: state)
        writeState(result.state)
        if let selection = result.selection, selection != excluded { writeExcluded(selection) }
    }
}
