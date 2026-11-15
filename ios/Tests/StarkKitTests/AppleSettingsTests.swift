// ios/Tests/StarkKitTests/AppleSettingsTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("AppleSettings")
struct AppleSettingsTests {
    private func cal(_ id: String, _ title: String, account: String, reminders: Bool = false,
                     color: String? = nil) -> AppleCalendarInfo {
        AppleCalendarInfo(id: id, title: title, accountName: account, colorHex: color, isReminderList: reminders)
    }

    // MARK: - Grouping

    @Test func groupsByAccountInCaseInsensitiveOrder() {
        let groups = AppleSettings.groupedByAccount([
            cal("1", "Work", account: "iCloud"),
            cal("2", "Holidays", account: "Gmail"),
            cal("3", "Home", account: "iCloud"),
            cal("4", "Birthdays", account: "exchange"),
        ])
        #expect(groups.map(\.accountName) == ["exchange", "Gmail", "iCloud"])
        #expect(groups.map { $0.calendars.map(\.id) } == [["4"], ["2"], ["3", "1"]])
    }

    @Test func calendarsBeforeReminderListsThenByTitle() {
        let groups = AppleSettings.groupedByAccount([
            cal("r2", "Shopping", account: "iCloud", reminders: true),
            cal("c2", "work", account: "iCloud"),
            cal("r1", "Errands", account: "iCloud", reminders: true),
            cal("c1", "Family", account: "iCloud"),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].calendars.map(\.id) == ["c1", "c2", "r1", "r2"])
    }

    @Test func equalTitlesFallBackToIDSoTheOrderIsStable() {
        let input = [
            cal("b", "Calendar", account: "iCloud"),
            cal("a", "Calendar", account: "iCloud"),
        ]
        #expect(AppleSettings.groupedByAccount(input)[0].calendars.map(\.id) == ["a", "b"])
        #expect(AppleSettings.groupedByAccount(input.reversed())[0].calendars.map(\.id) == ["a", "b"])
    }

    @Test func emptyAccountNameGetsAReadableHeader() {
        let groups = AppleSettings.groupedByAccount([cal("1", "Local", account: "")])
        #expect(groups.map(\.accountName) == ["On My iPhone"])
    }

    @Test func noCalendarsMeansNoGroups() {
        #expect(AppleSettings.groupedByAccount([]).isEmpty)
    }

    @Test func groupIDIsTheAccountName() {
        let groups = AppleSettings.groupedByAccount([cal("1", "Work", account: "iCloud")])
        #expect(groups[0].id == "iCloud")
    }

    // MARK: - Status and controls

    @Test func statusTextForEveryAccessState() {
        #expect(AppleSettings.statusText(.notAsked)
            == "Not asked yet. Stark asks on its main screen, after saying what access is for.")
        #expect(AppleSettings.statusText(.granted)
            == "Stark can read your calendars and reminders. It never changes them.")
        #expect(AppleSettings.statusText(.denied)
            == "Access is off. Allow Stark full access to Calendars and Reminders in iOS Settings.")
        #expect(AppleSettings.statusText(.writeOnly)
            == "Stark can only add events, not read them. Allow full access in iOS Settings.")
    }

    @Test func shortStatusForEveryAccessState() {
        #expect(AppleSettings.statusLabel(.notAsked) == "Not asked")
        #expect(AppleSettings.statusLabel(.granted) == "Full access")
        #expect(AppleSettings.statusLabel(.denied) == "Denied")
        #expect(AppleSettings.statusLabel(.writeOnly) == "Add only")
    }

    @Test func openSettingsShowsOnlyWhenDeniedOrWriteOnly() {
        #expect(AppleSettings.showsOpenSettings(.denied))
        #expect(AppleSettings.showsOpenSettings(.writeOnly))
        #expect(!AppleSettings.showsOpenSettings(.granted))
        #expect(!AppleSettings.showsOpenSettings(.notAsked))
    }

    @Test func calendarListShowsOnlyWhenOnAndGranted() {
        #expect(AppleSettings.showsCalendars(isEnabled: true, access: .granted))
        #expect(!AppleSettings.showsCalendars(isEnabled: false, access: .granted))
        #expect(!AppleSettings.showsCalendars(isEnabled: true, access: .denied))
        #expect(!AppleSettings.showsCalendars(isEnabled: true, access: .writeOnly))
        #expect(!AppleSettings.showsCalendars(isEnabled: true, access: .notAsked))
    }

    // MARK: - Colour

    @Test func calendarColourParsesLikeTheRowSource() {
        #expect(cal("1", "A", account: "x", color: "#FF8000").colorRGB == 0xFF8000)
        #expect(cal("1", "A", account: "x", color: nil).colorRGB == nil)
        #expect(cal("1", "A", account: "x", color: "FF8000").colorRGB == nil)
        #expect(cal("1", "A", account: "x", color: "#GG8000").colorRGB == nil)
    }
}
