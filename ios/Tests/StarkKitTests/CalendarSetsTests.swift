import Testing
import Foundation
@testable import StarkKit

@Suite("CalendarSets")
struct CalendarSetsTests {
    let all: Set<String> = ["a", "b", "c", "d"]

    private func made() throws -> (CalendarSets, CalendarSet, CalendarSet) {
        var s = CalendarSets(sets: [])
        let work = try s.add(name: "Work", includedIDs: ["a", "b"])
        let home = try s.add(name: "Home", includedIDs: ["c", "d"])
        return (s, work, home)
    }

    @Test("applying a set excludes every calendar not in it")
    func applyExcludesRest() throws {
        let (s, work, _) = try made()
        #expect(s.selection(applying: work.id, allIDs: all) == AppleSelection(excludedIDs: ["c", "d"]))
        #expect(s.selection(applying: UUID(), allIDs: all) == nil)
    }

    @Test("a calendar created after the set was saved is hidden under it and shown under All")
    func laterCalendarIsHiddenUnderSetShownUnderAll() throws {
        let (s, work, _) = try made()
        let later: Set<String> = all.union(["new"])
        let sel = try #require(s.selection(applying: work.id, allIDs: later))
        #expect(!sel.isShown("new"))
        #expect(s.label(for: sel, allIDs: later) == "Work")
        #expect(s.label(for: AppleSelection(), allIDs: later) == "All Calendars")
    }

    @Test("a deleted calendar id in a set is ignored and the label still matches")
    func deletedIDIgnored() throws {
        var s = CalendarSets(sets: [])
        let set = try s.add(name: "Old", includedIDs: ["a", "gone"])
        let sel = try #require(s.selection(applying: set.id, allIDs: all))
        #expect(sel.excludedIDs == ["b", "c", "d"])
        #expect(s.label(for: sel, allIDs: all) == "Old")
        // a stale excluded id in the live selection does not break matching either
        let stale = AppleSelection(excludedIDs: ["b", "c", "d", "zzz"])
        #expect(s.label(for: stale, allIDs: all) == "Old")
    }

    @Test("identical sets: the first in order is the active one")
    func identicalSets() throws {
        var s = CalendarSets(sets: [])
        let first = try s.add(name: "One", includedIDs: ["a"])
        _ = try s.add(name: "Two", includedIDs: ["a"])
        let sel = AppleSelection(excludedIDs: ["b", "c", "d"])
        #expect(s.activeSetID(for: sel, allIDs: all) == first.id)
        #expect(s.label(for: sel, allIDs: all) == "One")
    }

    @Test("no exclusions is All Calendars with no active set; otherwise Custom")
    func labels() throws {
        let (s, _, _) = try made()
        #expect(s.activeSetID(for: AppleSelection(), allIDs: all) == nil)
        #expect(s.label(for: AppleSelection(), allIDs: all) == "All Calendars")
        #expect(s.label(for: AppleSelection(excludedIDs: ["a"]), allIDs: all) == "Custom")
    }

    @Test("name rules")
    func names() throws {
        var s = CalendarSets(sets: [])
        #expect(throws: CalendarSetError.emptyName) { try s.add(name: "   ", includedIDs: ["a"]) }
        #expect(throws: CalendarSetError.emptyName) { try s.add(name: "", includedIDs: ["a"]) }
        let thirty = String(repeating: "x", count: 30)
        let ok = try s.add(name: thirty, includedIDs: ["a"])
        #expect(ok.name == thirty)
        #expect(throws: CalendarSetError.nameTooLong) {
            try s.add(name: String(repeating: "y", count: 31), includedIDs: ["a"])
        }
        // trimmed before measuring
        let padded = try s.add(name: "  Work  ", includedIDs: ["a"])
        #expect(padded.name == "Work")
        #expect(throws: CalendarSetError.duplicateName) { try s.add(name: "WORK", includedIDs: ["a"]) }
        #expect(s.sets.count == 2)
    }

    @Test("rename: own name or own case change is allowed, another's name is not")
    func rename() throws {
        var (s, work, home) = try made()
        try s.rename(work.id, to: "Work")
        try s.rename(work.id, to: "WORK")
        #expect(s.sets[0].name == "WORK")
        #expect(throws: CalendarSetError.duplicateName) { try s.rename(work.id, to: "home") }
        #expect(throws: CalendarSetError.emptyName) { try s.rename(home.id, to: " ") }
        #expect(throws: CalendarSetError.nameTooLong) {
            try s.rename(home.id, to: String(repeating: "z", count: 31))
        }
        #expect(throws: CalendarSetError.notFound) { try s.rename(UUID(), to: "Nope") }
        #expect(s.sets[1].name == "Home")
    }

    @Test("a set with no calendars is rejected on add and update")
    func emptySet() throws {
        var (s, work, _) = try made()
        #expect(throws: CalendarSetError.noCalendars) { try s.add(name: "Empty", includedIDs: []) }
        #expect(throws: CalendarSetError.noCalendars) { try s.updateIncluded(work.id, to: []) }
        #expect(s.sets[0].includedIDs == ["a", "b"])
        try s.updateIncluded(work.id, to: ["c"])
        #expect(s.sets[0].includedIDs == ["c"])
        #expect(throws: CalendarSetError.notFound) { try s.updateIncluded(UUID(), to: ["a"]) }
    }

    @Test("every error has a message")
    func messages() {
        #expect(CalendarSetError.emptyName.message == "Give the set a name.")
        #expect(CalendarSetError.nameTooLong.message == "Use 30 characters or fewer.")
        #expect(CalendarSetError.duplicateName.message == "Another set already has that name.")
        #expect(CalendarSetError.noCalendars.message == "Choose at least one calendar or list.")
        #expect(CalendarSetError.notFound.message == "That set no longer exists.")
        #expect(CalendarSetError.everyCalendar.message == "Untick at least one calendar, or use All Calendars.")
        #expect(CalendarSetError.reservedName.message == "That name is used by Stark. Pick another.")
    }

    @Test("deleting the active set leaves the selection; the label becomes Custom")
    func deleteActive() throws {
        var (s, work, _) = try made()
        let sel = try #require(s.selection(applying: work.id, allIDs: all))
        #expect(s.label(for: sel, allIDs: all) == "Work")
        let before = sel
        s.delete(work.id)
        #expect(s.sets.count == 1)
        #expect(s.sets.first?.name == "Home")
        // The selection value is untouched by the delete; only the label changes.
        #expect(sel == before)
        #expect(sel == AppleSelection(excludedIDs: ["c", "d"]))
        #expect(s.activeSetID(for: sel, allIDs: all) == nil)
        #expect(s.label(for: sel, allIDs: all) == "Custom")
    }

    @Test("reminder lists share the id space with calendars")
    func reminderLists() throws {
        var s = CalendarSets(sets: [])
        let ids: Set<String> = ["cal1", "cal2", "list1", "list2"]
        let set = try s.add(name: "Mixed", includedIDs: ["cal1", "list2"])
        let sel = try #require(s.selection(applying: set.id, allIDs: ids))
        #expect(sel.excludedIDs == ["cal2", "list1"])
    }

    @Test("round trip keeps ids, names and order")
    func roundTrip() throws {
        let (s, _, _) = try made()
        #expect(CalendarSets.decode(s.encoded()) == s)
    }

    @Test("missing or corrupt data decodes to no sets")
    func corrupt() {
        #expect(CalendarSets.decode(nil).sets.isEmpty)
        #expect(CalendarSets.decode(Data()).sets.isEmpty)
        #expect(CalendarSets.decode(Data("not json".utf8)).sets.isEmpty)
        #expect(CalendarSets.decode(Data(#"{"version":1,"sets":"x"}"#.utf8)).sets.isEmpty)
    }

    @Test("an unknown version decodes to no sets")
    func newerVersion() {
        let blob = #"{"version":2,"sets":[{"id":"\#(UUID().uuidString)","name":"X","includedIDs":["a"]}]}"#
        #expect(CalendarSets.decode(Data(blob.utf8)).sets.isEmpty)
    }

    @Test("canApply: true when at least one included id still exists")
    func canApplySome() throws {
        let (s, work, _) = try made()
        #expect(s.canApply(work.id, allIDs: ["a", "x"]))
        #expect(s.canApply(work.id, allIDs: all))
    }

    @Test("canApply: false when none of the set's ids exist, or the set is unknown")
    func canApplyNone() throws {
        let (s, work, _) = try made()
        #expect(!s.canApply(work.id, allIDs: ["x", "y"]))
        #expect(!s.canApply(work.id, allIDs: []))
        #expect(!s.canApply(UUID(), allIDs: all))
    }

    // MARK: fix wave

    @Test("a set that omits the always-shown default still matches, before and after keepShown")
    func omittedDefaultStaysActive() throws {
        var s = CalendarSets(sets: [])
        let set = try s.add(name: "Work", includedIDs: ["a", "b"])
        // "c" is the default calendar: always shown, so never excluded.
        let sel = try #require(s.selection(applying: set.id, allIDs: all, alwaysShown: ["c"]))
        #expect(sel.excludedIDs == ["d"])
        #expect(s.label(for: sel, allIDs: all, alwaysShown: ["c"]) == "Work")
        // keepShown re-shows "c": already shown, so a no-op, and the label is unchanged.
        var kept = sel
        kept.excludedIDs.remove("c")
        #expect(kept == sel)
        #expect(s.activeSetID(for: kept, allIDs: all, alwaysShown: ["c"]) == set.id)
    }

    @Test("changing the default: the set that was active is re-applied for the new default")
    func changingDefaultKeepsActive() throws {
        var s = CalendarSets(sets: [])
        let set = try s.add(name: "Work", includedIDs: ["a", "b"])
        let sel = try #require(s.selection(applying: set.id, allIDs: all, alwaysShown: ["c"]))
        #expect(sel.excludedIDs == ["d"])
        // The default moves from "c" to "d": keepShown shows "d", which empties the selection.
        var moved = sel
        moved.excludedIDs.remove("d")
        #expect(s.activeSetID(for: moved, allIDs: all, alwaysShown: ["d"]) == nil)
        let again = try #require(s.reapplied(set.id, selection: moved, allIDs: all, alwaysShown: ["d"]))
        #expect(again.excludedIDs == ["c"])
        #expect(s.activeSetID(for: again, allIDs: all, alwaysShown: ["d"]) == set.id)
        #expect(s.label(for: again, allIDs: all, alwaysShown: ["d"]) == "Work")
        // nothing to do when it already matches, or the set is gone, or its calendars are gone
        #expect(s.reapplied(set.id, selection: again, allIDs: all, alwaysShown: ["d"]) == nil)
        #expect(s.reapplied(UUID(), selection: moved, allIDs: all, alwaysShown: ["d"]) == nil)
        #expect(s.reapplied(set.id, selection: moved, allIDs: ["x", "y"], alwaysShown: []) == nil)
    }

    @Test("a calendar that appears while a set is active stays hidden and the label stays")
    func reconcileNewCalendar() throws {
        let (s, work, _) = try made()
        let sel = try #require(s.selection(applying: work.id, allIDs: all))
        let later = all.union(["new"])
        let next = try #require(s.reconciled(selection: sel, previousAllIDs: all, newAllIDs: later, alwaysShown: []))
        #expect(!next.isShown("new"))
        #expect(next.isShown("a") && next.isShown("b"))
        #expect(s.label(for: next, allIDs: later) == "Work")
    }

    @Test("reconcile: nothing active, nothing new, or an always-shown newcomer changes nothing")
    func reconcileNoChange() throws {
        let (s, work, _) = try made()
        let later = all.union(["new"])
        #expect(s.reconciled(selection: AppleSelection(), previousAllIDs: all, newAllIDs: later, alwaysShown: []) == nil)
        #expect(s.reconciled(selection: AppleSelection(excludedIDs: ["a"]), previousAllIDs: all, newAllIDs: later, alwaysShown: []) == nil)
        let sel = try #require(s.selection(applying: work.id, allIDs: all))
        #expect(s.reconciled(selection: sel, previousAllIDs: all, newAllIDs: all, alwaysShown: []) == nil)
        #expect(s.reconciled(selection: sel, previousAllIDs: all, newAllIDs: later, alwaysShown: ["new"]) == nil)
        // a calendar disappearing changes nothing
        #expect(s.reconciled(selection: sel, previousAllIDs: all, newAllIDs: ["a", "b", "c"], alwaysShown: []) == nil)
    }

    @Test("reconcile: the first fetch from an empty list never fires")
    func reconcileFirstFetch() throws {
        let (s, work, _) = try made()
        let sel = try #require(s.selection(applying: work.id, allIDs: all))
        #expect(s.reconciled(selection: sel, previousAllIDs: [], newAllIDs: all, alwaysShown: []) == nil)
    }

    @Test("reconcile never un-hides a calendar that came back after a partial list")
    func reconcileReturningCalendar() throws {
        let (s, work, _) = try made()
        let sel = try #require(s.selection(applying: work.id, allIDs: all))   // excludes c, d
        let partial: Set<String> = ["a", "b", "c"]
        // "d" missing for a moment, then back: it is new relative to the partial list
        #expect(s.reconciled(selection: sel, previousAllIDs: partial, newAllIDs: all, alwaysShown: []) == nil)
        #expect(!sel.isShown("d"))
        // had the selection forgotten "d", it is hidden again
        let forgot = AppleSelection(excludedIDs: ["c"])
        let next = try #require(s.reconciled(selection: forgot, previousAllIDs: partial, newAllIDs: all, alwaysShown: []))
        #expect(next.excludedIDs == ["c", "d"])
    }

    @Test("a set of every calendar is rejected; an unticked one is fine; stale ids do not count")
    func everyCalendar() throws {
        var s = CalendarSets(sets: [])
        #expect(throws: CalendarSetError.everyCalendar) { try s.add(name: "All", includedIDs: all, allIDs: all) }
        #expect(throws: CalendarSetError.everyCalendar) {
            try s.add(name: "All", includedIDs: all.union(["gone"]), allIDs: all)
        }
        #expect(throws: CalendarSetError.noCalendars) { try s.add(name: "Gone", includedIDs: ["gone"], allIDs: all) }
        // the always-shown default does not have to be ticked to count as "every calendar"
        #expect(throws: CalendarSetError.everyCalendar) {
            try s.add(name: "All", includedIDs: ["a", "b", "d"], allIDs: all, alwaysShown: ["c"])
        }
        let ok = try s.add(name: "Most", includedIDs: ["a", "b", "c"], allIDs: all)
        #expect(throws: CalendarSetError.everyCalendar) { try s.updateIncluded(ok.id, to: all, allIDs: all) }
        #expect(throws: CalendarSetError.noCalendars) { try s.updateIncluded(ok.id, to: ["zzz"], allIDs: all) }
        // with no list loaded yet the check is skipped
        _ = try s.add(name: "Offline", includedIDs: ["a"], allIDs: [])
    }

    @Test("the names Custom and All Calendars are reserved, case-insensitively")
    func reservedNames() throws {
        var (s, work, _) = try made()
        for name in ["Custom", "custom", "ALL CALENDARS", " All calendars "] {
            #expect(throws: CalendarSetError.reservedName) { try s.add(name: name, includedIDs: ["a"]) }
            #expect(throws: CalendarSetError.reservedName) { try s.rename(work.id, to: name) }
        }
    }

    @Test("before the list loads the label never claims All Calendars while something is hidden")
    func labelBeforeLoad() throws {
        let (s, work, _) = try made()
        let sel = try #require(s.selection(applying: work.id, allIDs: all))
        #expect(s.label(for: sel, allIDs: []) == "Calendars")
        #expect(s.label(for: AppleSelection(), allIDs: []) == "All Calendars")
        #expect(s.activeSetID(for: sel, allIDs: []) == nil)
    }
}
