// ios/Tests/StarkKitTests/AppleWritableTests.swift
import Foundation
import Testing
@testable import StarkKit

@Suite("Apple calendar writability")
struct AppleWritableTests {
    private let when = Date(timeIntervalSince1970: 1_800_000_000)

    private func info(writable: Bool? = nil, reminders: Bool = false) -> AppleCalendarInfo {
        if let writable {
            return AppleCalendarInfo(id: "c", title: "Holidays", accountName: "Subscribed", colorHex: nil,
                                     isReminderList: reminders, isWritable: writable)
        }
        return AppleCalendarInfo(id: "c", title: "Home", accountName: "iCloud", colorHex: nil,
                                 isReminderList: reminders)
    }

    @Test func calendarInfoIsWritableByDefault() {
        #expect(info().isWritable)
        #expect(info(writable: false).isWritable == false)
        #expect(AppleSource(calendarID: "c", calendarTitle: "C", colorHex: nil, isReminder: false).isWritable)
    }

    @Test func mergeCarriesWritabilityOntoTheRowSource() {
        let readOnly = AppleCalendarEvent(id: "e", title: "Holiday", notes: nil, location: nil, url: nil,
                                          start: when, end: nil, isAllDay: true, calendar: info(writable: false))
        let writable = AppleReminder(id: "r", title: "Call", notes: nil, due: when, dueHasTime: true,
                                     isCompleted: false, completedAt: nil, priority: nil,
                                     calendar: info(reminders: true))
        let merged = mergeAppleItems([], snapshot: AppleSnapshot(events: [readOnly], reminders: [writable]),
                                     in: when.addingTimeInterval(-86_400)...when.addingTimeInterval(86_400),
                                     today: when)
        #expect(merged.count == 2)
        #expect(merged.first { $0.appleSource?.isReminder == false }?.appleSource?.isWritable == false)
        #expect(merged.first { $0.appleSource?.isReminder == true }?.appleSource?.isWritable == true)
    }
}
