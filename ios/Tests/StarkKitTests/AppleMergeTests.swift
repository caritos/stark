// ios/Tests/StarkKitTests/AppleMergeTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("AppleMerge")
struct AppleMergeTests {
    private let when = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(source: AppleSource? = nil) -> AgendaItem {
        let event = Event(id: "e", title: "Lunch", start: when)
        if let source {
            return AgendaItem(kind: .event(event), occurrence: when, displayDate: when, isOverdue: false, appleSource: source)
        }
        return AgendaItem(kind: .event(event), occurrence: when, displayDate: when, isOverdue: false)
    }

    @Test func appleSourceDefaultsToNil() {
        #expect(item().appleSource == nil)
    }

    @Test func appleSourceKeptByInit() {
        let source = AppleSource(calendarID: "c1", calendarTitle: "Work", colorHex: "#FF0000", isReminder: false)
        let built = item(source: source)
        #expect(built.appleSource == source)
        #expect(built.id == item().id)
    }

    @Test func appleItemIsReadOnlyStarkItemIsNot() {
        let source = AppleSource(calendarID: "c1", calendarTitle: "Work", colorHex: "#FF0000", isReminder: false)
        #expect(item(source: source).isReadOnly)
        #expect(!item().isReadOnly)
    }
}
