// ios/Tests/StarkKitTests/AppleReadOnlyTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("AppleReadOnly")
struct AppleReadOnlyTests {
    private let when = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let eventSource = AppleSource(calendarID: "c1", calendarTitle: "Work", colorHex: "#1BADF8", isReminder: false)
    private let reminderSource = AppleSource(calendarID: "l1", calendarTitle: "Errands", colorHex: nil, isReminder: true)

    private func appleEvent(id: String = "apple-EV1") -> AgendaItem {
        AgendaItem(kind: .event(Event(id: id, title: "Standup", start: when)), occurrence: when,
                   displayDate: when, isOverdue: false, appleSource: eventSource)
    }

    private func appleReminder(id: String = "apple-RM1") -> AgendaItem {
        AgendaItem(kind: .reminder(Reminder(id: id, title: "Milk", dueDate: when)), occurrence: when,
                   displayDate: when, isOverdue: false, appleSource: reminderSource)
    }

    private func starkEvent() -> AgendaItem {
        AgendaItem(kind: .event(Event(id: "e1", title: "Lunch", start: when)), occurrence: when,
                   displayDate: when, isOverdue: false)
    }

    // MARK: Detail routing (the one gate between a tap and a Stark edit sheet)

    @Test func appleItemRoutesToReadOnlyDetail() {
        let item = appleEvent()
        #expect(AgendaItemDetail(item) == .readOnly(item))
        #expect(AgendaItemDetail(item).editable == nil)
    }

    @Test func starkItemRoutesToEditSheet() {
        let item = starkEvent()
        #expect(AgendaItemDetail(item) == .edit(item))
        #expect(AgendaItemDetail(item).editable == item)
    }

    @Test func detailIdIsTheItemId() {
        #expect(AgendaItemDetail(appleReminder()).id == appleReminder().id)
        #expect(AgendaItemDetail(starkEvent()).id == starkEvent().id)
    }

    // MARK: Open in Calendar / Reminders

    @Test func appleEventOpensCalendarAtItsOccurrence() {
        #expect(appleOpenURL(for: appleEvent())?.absoluteString == "calshow:800000000")
    }

    @Test func appleReminderOpensRemindersWithItsIdentifier() {
        #expect(appleOpenURL(for: appleReminder())?.absoluteString == "x-apple-reminderkit://REMCDReminder/RM1")
    }

    @Test func reminderIdentifierIsPercentEncoded() {
        let url = appleOpenURL(for: appleReminder(id: "apple-A B/C"))
        #expect(url?.absoluteString == "x-apple-reminderkit://REMCDReminder/A%20B%2FC")
    }

    @Test func starkItemHasNoOpenLink() {
        #expect(appleOpenURL(for: starkEvent()) == nil)
    }

    @Test func appleReminderWithoutPrefixedIdHasNoOpenLink() {
        #expect(appleOpenURL(for: appleReminder(id: "RM1")) == nil)
        #expect(appleOpenURL(for: appleReminder(id: "apple-")) == nil)
    }

    // MARK: Calendar colour

    @Test func parsesHashRGB() {
        #expect(eventSource.colorRGB == 0x1BADF8)
        #expect(AppleSource(calendarID: "c", calendarTitle: "t", colorHex: "#ff0000", isReminder: false).colorRGB == 0xFF0000)
    }

    @Test func missingOrMalformedColourIsNil() {
        for hex in [nil, "", "#", "FF0000", "#FF00", "#FF00000", "#GG0000", "#+F0000"] as [String?] {
            #expect(AppleSource(calendarID: "c", calendarTitle: "t", colorHex: hex, isReminder: false).colorRGB == nil,
                    "\(String(describing: hex))")
        }
    }
}
