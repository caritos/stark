// ios/Tests/StarkKitTests/AppleSelectionTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("AppleSelection")
struct AppleSelectionTests {
    private let when = Date(timeIntervalSince1970: 1_800_000_000)

    private func cal(_ id: String, reminders: Bool = false) -> AppleCalendarInfo {
        AppleCalendarInfo(id: id, title: id, accountName: "iCloud", colorHex: nil, isReminderList: reminders)
    }

    @Test func emptySelectionShowsEverythingIncludingNewCalendars() {
        let selection = AppleSelection()
        #expect(selection.excludedIDs.isEmpty)
        #expect(selection.isShown("a"))
        #expect(selection.isShown("brand-new"))
    }

    @Test func excludedCalendarHidden() {
        let selection = AppleSelection(excludedIDs: ["a"])
        #expect(!selection.isShown("a"))
        #expect(selection.isShown("b"))
    }

    @Test func prunedDropsRemovedCalendarIDs() {
        let selection = AppleSelection(excludedIDs: ["a", "gone"])
        let pruned = selection.pruned(toExisting: ["a", "b"])
        #expect(pruned.excludedIDs == ["a"])
    }

    @Test func filteredRemovesItemsOfExcludedCalendars() {
        func event(_ id: String, _ c: AppleCalendarInfo) -> AppleCalendarEvent {
            AppleCalendarEvent(id: id, title: id, notes: nil, location: nil, url: nil,
                               start: when, end: nil, isAllDay: false, calendar: c)
        }
        func reminder(_ id: String, _ c: AppleCalendarInfo) -> AppleReminder {
            AppleReminder(id: id, title: id, notes: nil, due: when, dueHasTime: true,
                          isCompleted: false, completedAt: nil, priority: nil, calendar: c)
        }
        let snapshot = AppleSnapshot(
            events: [event("e1", cal("a")), event("e2", cal("b"))],
            reminders: [reminder("r1", cal("a", reminders: true)), reminder("r2", cal("c", reminders: true))])
        let filtered = AppleSelection(excludedIDs: ["a"]).filtered(snapshot)
        #expect(filtered.events.map(\.id) == ["e2"])
        #expect(filtered.reminders.map(\.id) == ["r2"])
        #expect(AppleSelection().filtered(snapshot) == snapshot)
    }
}
