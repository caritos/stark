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
import UIKit
import StarkKit

@MainActor @Observable
final class CalendarSetsModel {
    static let key = StoredKeys.calendarSets

    private(set) var sets: CalendarSets
    /// A plain message for the sheet (a refused apply); cleared by the next action.
    var message: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let overlay: AppleOverlayModel
    /// The default calendar and list: always shown, so a set never hides them (decision 11).
    @ObservationIgnored private let alwaysShownIDs: () -> Set<String>
    /// What the last `sync()` saw, to tell a new calendar or a moved default from no change.
    @ObservationIgnored private var knownIDs: Set<String> = []
    @ObservationIgnored private var knownAlways: Set<String>
    @ObservationIgnored private var lastActive: UUID?

    init(overlay: AppleOverlayModel, alwaysShown: @escaping () -> Set<String> = { [] },
         defaults: UserDefaults = .standard) {
        self.overlay = overlay
        self.defaults = defaults
        self.alwaysShownIDs = alwaysShown
        self.knownAlways = alwaysShown()
        // Reading never writes: a blob from a newer version stays untouched until the owner edits.
        sets = CalendarSets.decode(defaults.data(forKey: Self.key))
    }

    /// What `ContentView` watches to call `sync()`.
    struct SyncKey: Equatable {
        var allIDs: Set<String>
        var alwaysShown: Set<String>
        var excluded: Set<String>
    }

    var syncKey: SyncKey { SyncKey(allIDs: allIDs, alwaysShown: alwaysShown, excluded: overlay.selection.excludedIDs) }

    var allIDs: Set<String> { Set(overlay.calendars.map(\.id)) }
    var alwaysShown: Set<String> { alwaysShownIDs() }

    /// False until the first calendar fetch landed: a set cannot be matched or applied yet.
    var isLoaded: Bool { !allIDs.isEmpty }

    var label: String { sets.label(for: overlay.selection, allIDs: allIDs, alwaysShown: alwaysShown) }

    var activeID: UUID? { sets.activeSetID(for: overlay.selection, allIDs: allIDs, alwaysShown: alwaysShown) }

    var isAllCalendars: Bool { label == "All Calendars" }

    /// The ids shown right now (the starting point for a new set).
    var shownIDs: Set<String> { allIDs.filter { overlay.selection.isShown($0) } }

    /// Keeps the active set active when the calendar list or the default changes (see
    /// `CalendarSets.reconciled` and `reapplied`). Writes the selection at most once per call.
    func sync() {
        let all = allIDs, always = alwaysShown
        defer { knownIDs = all; knownAlways = always }
        guard !all.isEmpty else { return }
        let selection = overlay.selection
        if let next = sets.reconciled(selection: selection, previousAllIDs: knownIDs, newAllIDs: all, alwaysShown: always) {
            overlay.selection = next
            return
        }
        if always != knownAlways, let last = lastActive,
           sets.activeSetID(for: selection, allIDs: all, alwaysShown: always) == nil,
           let next = sets.reapplied(last, selection: selection, allIDs: all, alwaysShown: always) {
            overlay.selection = next
            return
        }
        lastActive = sets.activeSetID(for: selection, allIDs: all, alwaysShown: always)
    }

    func showAll() {
        message = nil
        lastActive = nil
        overlay.selection = AppleSelection(excludedIDs: [])
    }

    func apply(_ id: UUID) {
        message = nil
        guard isLoaded else { return fail("Your calendars are still loading. Try again in a moment.") }
        guard sets.canApply(id, allIDs: allIDs),
              let next = sets.selection(applying: id, allIDs: allIDs, alwaysShown: alwaysShown) else {
            return fail("None of this set's calendars exist any more. Edit the set to choose others.")
        }
        lastActive = id
        overlay.selection = next
    }

    private func fail(_ text: String) {
        message = text
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// Returns the error to show in the editor, or nil when saved. Saving the ACTIVE set applies
    /// it again, so the view follows the edit.
    func save(id: UUID?, name: String, included: Set<String>) -> CalendarSetError? {
        var next = sets
        let wasActive = id != nil && id == activeID
        do {
            if let id {
                try next.rename(id, to: name)
                try next.updateIncluded(id, to: included, allIDs: allIDs, alwaysShown: alwaysShown)
            } else {
                try next.add(name: name, includedIDs: included, allIDs: allIDs, alwaysShown: alwaysShown)
            }
        } catch let error as CalendarSetError {
            UIAccessibility.post(notification: .announcement, argument: error.message)
            return error
        } catch {
            return .notFound
        }
        sets = next
        persist()
        if wasActive, let id { apply(id) }
        return nil
    }

    /// Deleting leaves the current selection as it is (the label becomes "Custom").
    func delete(_ id: UUID) {
        sets.delete(id)
        if lastActive == id { lastActive = nil }
        persist()
    }

    private func persist() {
        defaults.set(sets.encoded(), forKey: Self.key)
    }
}
