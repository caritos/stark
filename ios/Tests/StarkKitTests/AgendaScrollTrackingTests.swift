// ios/Tests/StarkKitTests/AgendaScrollTrackingTests.swift
import Testing
@testable import StarkKit

struct AgendaScrollTrackingTests {
    private let order = ["day-1", "item-a", "item-b", "day-2", "day-3", "tail"]

    @Test("the top row is the earliest displayed row in list order, not set order")
    func picksEarliestInListOrder() {
        #expect(AgendaScrollTracking.topRowID(displayed: ["day-3", "item-b", "day-2"], orderedRowIDs: order) == "item-b")
        #expect(AgendaScrollTracking.topRowID(displayed: ["tail", "day-3"], orderedRowIDs: order) == "day-3")
    }

    @Test("a single displayed row is the top row")
    func singleRow() {
        #expect(AgendaScrollTracking.topRowID(displayed: ["day-2"], orderedRowIDs: order) == "day-2")
    }

    @Test("nothing displayed means no top row")
    func emptyDisplayed() {
        #expect(AgendaScrollTracking.topRowID(displayed: [], orderedRowIDs: order) == nil)
    }

    @Test("displayed ids that are no longer rows are ignored")
    func ignoresStaleIDs() {
        // A row that left the list (window moved) can still be in the displayed set for a beat.
        #expect(AgendaScrollTracking.topRowID(displayed: ["gone", "day-2"], orderedRowIDs: order) == "day-2")
        #expect(AgendaScrollTracking.topRowID(displayed: ["gone"], orderedRowIDs: order) == nil)
    }
}
