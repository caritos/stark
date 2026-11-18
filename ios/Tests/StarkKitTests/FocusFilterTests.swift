import Testing
import Foundation
@testable import StarkKit

@Suite("FocusFilter")
struct FocusFilterTests {
    let all: Set<String> = ["a", "b", "c", "d"]

    private func made() throws -> (CalendarSets, CalendarSet, CalendarSet) {
        var s = CalendarSets(sets: [])
        let work = try s.add(name: "Work", includedIDs: ["a", "b"])
        let home = try s.add(name: "Home", includedIDs: ["c", "d"])
        return (s, work, home)
    }

    @Test("the first Focus on remembers the selection before it and applies the set")
    func firstOnRemembersBefore() throws {
        let (sets, work, _) = try made()
        let result = try #require(FocusFilter.turnOn(setID: work.id, current: ["d"], state: nil,
                                                     sets: sets, allIDs: all, alwaysShown: []))
        #expect(result.selection == ["c", "d"])
        #expect(result.state == FocusFilterState(before: ["d"], applied: ["c", "d"], setID: work.id))
    }

    @Test("the set is applied with the always-shown calendars left visible")
    func onKeepsAlwaysShown() throws {
        let (sets, work, _) = try made()
        let result = try #require(FocusFilter.turnOn(setID: work.id, current: [], state: nil,
                                                     sets: sets, allIDs: all, alwaysShown: ["c"]))
        #expect(result.selection == ["d"])
    }

    @Test("a second Focus on re-applies but keeps the original before")
    func secondOnKeepsOriginalBefore() throws {
        let (sets, work, home) = try made()
        let first = try #require(FocusFilter.turnOn(setID: work.id, current: [], state: nil,
                                                    sets: sets, allIDs: all, alwaysShown: []))
        let second = try #require(FocusFilter.turnOn(setID: home.id, current: first.selection, state: first.state,
                                                     sets: sets, allIDs: all, alwaysShown: []))
        #expect(second.selection == ["a", "b"])
        #expect(second.state == FocusFilterState(before: [], applied: ["a", "b"], setID: home.id))
    }

    @Test("a deleted set, a set with no calendar left, or no calendars yet change nothing")
    func unusableSetChangesNothing() throws {
        let (sets, work, _) = try made()
        #expect(FocusFilter.turnOn(setID: UUID(), current: [], state: nil,
                                   sets: sets, allIDs: all, alwaysShown: []) == nil)
        #expect(FocusFilter.turnOn(setID: work.id, current: [], state: nil,
                                   sets: sets, allIDs: [], alwaysShown: []) == nil)
        #expect(FocusFilter.turnOn(setID: work.id, current: [], state: nil,
                                   sets: sets, allIDs: ["x", "y"], alwaysShown: []) == nil)
    }

    @Test("Focus off restores the selection before when nothing was changed by hand")
    func offRestores() {
        let state = FocusFilterState(before: ["d"], applied: ["c", "d"])
        let result = FocusFilter.turnOff(current: ["c", "d"], state: state)
        #expect(result.selection == ["d"])
        #expect(result.state == nil)
    }

    @Test("Focus off leaves a selection the owner changed by hand and forgets the memory")
    func offLeavesHandChange() {
        let state = FocusFilterState(before: ["d"], applied: ["c", "d"])
        let result = FocusFilter.turnOff(current: ["c"], state: state)
        #expect(result.selection == nil)
        #expect(result.state == nil)
    }

    @Test("Focus off with nothing remembered changes nothing")
    func offWithoutStateDoesNothing() {
        let result = FocusFilter.turnOff(current: ["c"], state: nil)
        #expect(result.selection == nil)
        #expect(result.state == nil)
    }

    @Test("state round-trips; missing, corrupt or newer data decodes to nil")
    func stateDecoding() {
        let state = FocusFilterState(before: ["a"], applied: ["b", "c"])
        #expect(FocusFilterState.decode(state.encoded()) == state)
        #expect(FocusFilterState.decode(nil) == nil)
        #expect(FocusFilterState.decode(Data("not json".utf8)) == nil)
        #expect(FocusFilterState.decode(Data(#"{"version":99,"before":[],"applied":[]}"#.utf8)) == nil)
    }

    @Test("Focus off still restores when the app adjusted the selection for the same set (a new calendar was hidden with it)")
    func offRestoresAfterAutomaticAdjustment() throws {
        let (sets, work, _) = try made()
        let on = try #require(FocusFilter.turnOn(setID: work.id, current: [], state: nil,
                                                 sets: sets, allIDs: all, alwaysShown: []))
        // A calendar "e" appeared while the Focus was on; the app hid it with the set.
        let grown: Set<String> = all.union(["e"])
        let adjusted = on.selection.union(["e"])
        let result = FocusFilter.turnOff(current: adjusted, state: on.state, sets: sets, allIDs: grown, alwaysShown: [])
        #expect(result.selection == [])
        #expect(result.state == nil)
    }

    @Test("Focus off leaves a selection that no longer matches the applied set")
    func offLeavesHandChangeWithSets() throws {
        let (sets, work, _) = try made()
        let on = try #require(FocusFilter.turnOn(setID: work.id, current: [], state: nil,
                                                 sets: sets, allIDs: all, alwaysShown: []))
        let result = FocusFilter.turnOff(current: ["a"], state: on.state, sets: sets, allIDs: all, alwaysShown: [])
        #expect(result.selection == nil)
        #expect(result.state == nil)
    }

    @Test("the remembered set id survives encode and decode; an older file without it still decodes")
    func stateRoundTripsSetID() throws {
        let id = UUID()
        let state = FocusFilterState(before: ["x"], applied: ["y"], setID: id)
        #expect(FocusFilterState.decode(state.encoded()) == state)
        let old = Data(#"{"version":1,"before":["x"],"applied":["y"]}"#.utf8)
        #expect(FocusFilterState.decode(old) == FocusFilterState(before: ["x"], applied: ["y"]))
    }
}
