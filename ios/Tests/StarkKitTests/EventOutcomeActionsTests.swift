// ios/Tests/StarkKitTests/EventOutcomeActionsTests.swift
import Testing
@testable import StarkKit

@Suite("EventOutcomeActions")
struct EventOutcomeActionsTests {
    @Test("an unmarked event offers both marks and no Clear")
    func unmarked() {
        let actions = EventOutcomeActions(outcome: nil, isRecurring: false)
        #expect(actions.showsAttended)
        #expect(actions.showsDidntAttend)
        #expect(!actions.showsClear)
    }

    @Test("an attended event hides Attended and offers Didn't Attend and Clear")
    func attended() {
        let actions = EventOutcomeActions(outcome: .attended, isRecurring: false)
        #expect(!actions.showsAttended)
        #expect(actions.showsDidntAttend)
        #expect(actions.showsClear)
    }

    @Test("a skipped event hides Didn't Attend and offers Attended and Clear")
    func skipped() {
        let actions = EventOutcomeActions(outcome: .skipped, isRecurring: false)
        #expect(actions.showsAttended)
        #expect(!actions.showsDidntAttend)
        #expect(actions.showsClear)
    }

    @Test("Remove This Occurrence is offered only for recurring events")
    func removeOccurrenceOnlyWhenRecurring() {
        #expect(EventOutcomeActions(outcome: nil, isRecurring: true).showsRemoveOccurrence)
        #expect(EventOutcomeActions(outcome: .attended, isRecurring: true).showsRemoveOccurrence)
        #expect(!EventOutcomeActions(outcome: nil, isRecurring: false).showsRemoveOccurrence)
    }
}
