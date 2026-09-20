// ios/Tests/StarkKitTests/ReminderPriorityTests.swift
import Testing
@testable import StarkKit

@Suite("ReminderPriority")
struct ReminderPriorityTests {
    @Test("each level writes the Apple Reminders iCal value; none writes nothing")
    func icalValues() {
        #expect(ReminderPriority.none.icalValue == nil)
        #expect(ReminderPriority.low.icalValue == 9)
        #expect(ReminderPriority.medium.icalValue == 5)
        #expect(ReminderPriority.high.icalValue == 1)
    }

    @Test("an existing iCal value maps to the nearest level")
    func bucketsExistingValues() {
        #expect(ReminderPriority(icalValue: nil) == .none)
        #expect(ReminderPriority(icalValue: 0) == .none)
        #expect(ReminderPriority(icalValue: 1) == .high)
        #expect(ReminderPriority(icalValue: 4) == .high)
        #expect(ReminderPriority(icalValue: 5) == .medium)
        #expect(ReminderPriority(icalValue: 6) == .low)
        #expect(ReminderPriority(icalValue: 9) == .low)
        #expect(ReminderPriority(icalValue: 10) == .none)
        #expect(ReminderPriority(icalValue: -3) == .none)
    }

    @Test("every level survives a write-then-read round trip")
    func roundTrip() {
        for level in ReminderPriority.allCases {
            #expect(ReminderPriority(icalValue: level.icalValue) == level)
        }
    }

    @Test("marks and picker labels")
    func labels() {
        #expect(ReminderPriority.none.marks == "")
        #expect(ReminderPriority.low.marks == "!")
        #expect(ReminderPriority.medium.marks == "!!")
        #expect(ReminderPriority.high.marks == "!!!")
        #expect(ReminderPriority.none.pickerLabel == "None")
        #expect(ReminderPriority.high.pickerLabel == "!!!")
    }

    @Test("an untouched level keeps the original value; a changed level writes the new one")
    func updatedKeepsOriginalWhenUnchanged() {
        #expect(ReminderPriority.updated(original: 3, chosen: .high) == 3)
        #expect(ReminderPriority.updated(original: 0, chosen: .none) == 0)
        #expect(ReminderPriority.updated(original: nil, chosen: .none) == nil)
        #expect(ReminderPriority.updated(original: 3, chosen: .low) == 9)
        #expect(ReminderPriority.updated(original: 3, chosen: .none) == nil)
        #expect(ReminderPriority.updated(original: nil, chosen: .medium) == 5)
    }
}
