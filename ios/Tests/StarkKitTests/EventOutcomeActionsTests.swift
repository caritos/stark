// ios/Tests/StarkKitTests/EventOutcomeActionsTests.swift
import Testing
@testable import StarkKit

@Suite("EventOutcomeActions")
struct EventOutcomeActionsTests {
    @Test("Remove This Occurrence is offered only for recurring events")
    func removeOccurrenceOnlyWhenRecurring() {
        #expect(EventOutcomeActions(isRecurring: true).showsRemoveOccurrence)
        #expect(!EventOutcomeActions(isRecurring: false).showsRemoveOccurrence)
    }
}
