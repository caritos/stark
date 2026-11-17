import Testing
@testable import StarkKit

@Suite("DestinationLabel")
struct DestinationLabelTests {
    private func info(_ title: String = "Calendar", account: String = "iCloud", local: Bool = false) -> AppleCalendarInfo {
        AppleCalendarInfo(id: "\(title)-\(account)", title: title, accountName: account, colorHex: nil,
                          isReminderList: false, isLocalOnly: local)
    }

    @Test func subtitleIsAccountName() {
        #expect(DestinationLabel.subtitle(info(account: "iCloud")) == "iCloud")
    }

    @Test func subtitleFallsBackWhenAccountEmpty() {
        #expect(DestinationLabel.subtitle(info(account: "")) == "Unknown account")
    }

    @Test func twoSameTitledCalendarsGetDifferentSubtitles() {
        let a = info(account: "iCloud"), b = info(account: "On My iPhone", local: true)
        #expect(a.title == b.title)
        #expect(DestinationLabel.subtitle(a) != DestinationLabel.subtitle(b))
    }

    @Test func warningOnlyForLocalOnly() {
        #expect(DestinationLabel.warning(for: info(local: true)) != nil)
        #expect(DestinationLabel.warning(for: info(local: false)) == nil)
        #expect(DestinationLabel.warning(for: nil) == nil)
    }

    @Test func warningTextIsExact() {
        #expect(DestinationLabel.localOnlyWarning == "Stays on this iPhone; it won't sync to your other devices.")
        #expect(DestinationLabel.warning(for: info(local: true)) == "Stays on this iPhone; it won't sync to your other devices.")
    }

    @Test func addedNoticeNamesCalendarAndAccount() {
        #expect(DestinationLabel.addedNotice(calendar: info("Home", account: "iCloud")) == "Added to Home · iCloud")
        #expect(DestinationLabel.addedNotice(calendar: info("Home", account: "")) == "Added to Home · Unknown account")
    }

    @Test func addedNoticeFallsBackToPlainAddedWhenCalendarMissing() {
        #expect(DestinationLabel.addedNotice(calendar: nil) == "Added")
    }

    @Test func veryLongTitleIsNotTruncatedByTheKit() {
        let title = String(repeating: "Long ", count: 60)
        #expect(DestinationLabel.addedNotice(calendar: info(title)) == "Added to \(title) · iCloud")
    }
}
