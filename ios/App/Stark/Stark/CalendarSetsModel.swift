//
//  CalendarSetsModel.swift
//  Stark
//
//  The saved calendar sets (names and calendar ids, in UserDefaults on this device only). All
//  rules (names, derivation of the active set, applying) are StarkKit `CalendarSets`; this holds
//  the persistence and applies a set through `AppleOverlayModel.selection`.
//

import Foundation
import Observation
import StarkKit

@MainActor @Observable
final class CalendarSetsModel {
    static let key = "calendarSets.v1"

    private(set) var sets: CalendarSets
    /// A plain message for the sheet (a refused apply); cleared by the next action.
    var message: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let overlay: AppleOverlayModel

    init(overlay: AppleOverlayModel, defaults: UserDefaults = .standard) {
        self.overlay = overlay
        self.defaults = defaults
        // Reading never writes: a blob from a newer version stays untouched until the owner edits.
        sets = CalendarSets.decode(defaults.data(forKey: Self.key))
    }

    var allIDs: Set<String> { Set(overlay.calendars.map(\.id)) }

    var label: String { sets.label(for: overlay.selection, allIDs: allIDs) }

    var activeID: UUID? { sets.activeSetID(for: overlay.selection, allIDs: allIDs) }

    var isAllCalendars: Bool { overlay.selection.excludedIDs.intersection(allIDs).isEmpty }

    /// The ids shown right now (the starting point for a new set).
    var shownIDs: Set<String> { allIDs.filter { overlay.selection.isShown($0) } }

    func showAll() {
        message = nil
        overlay.selection = AppleSelection(excludedIDs: [])
    }

    func apply(_ id: UUID) {
        message = nil
        guard sets.canApply(id, allIDs: allIDs),
              let next = sets.selection(applying: id, allIDs: allIDs) else {
            message = "None of this set's calendars exist any more. Edit the set to choose others."
            return
        }
        overlay.selection = next
    }

    /// Returns the error to show in the editor, or nil when saved.
    func save(id: UUID?, name: String, included: Set<String>) -> CalendarSetError? {
        var next = sets
        do {
            if let id {
                try next.rename(id, to: name)
                try next.updateIncluded(id, to: included)
            } else {
                try next.add(name: name, includedIDs: included)
            }
        } catch let error as CalendarSetError {
            return error
        } catch {
            return .notFound
        }
        sets = next
        persist()
        return nil
    }

    /// Deleting leaves the current selection as it is (the label becomes "Custom").
    func delete(_ id: UUID) {
        sets.delete(id)
        persist()
    }

    private func persist() {
        defaults.set(sets.encoded(), forKey: Self.key)
    }
}
