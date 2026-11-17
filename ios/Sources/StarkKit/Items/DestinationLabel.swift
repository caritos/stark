import Foundation

/// Every string that tells the owner where a new item goes (issue #123). Pure, so views only render.
public enum DestinationLabel {
    public static let localOnlyWarning = "Stays on this iPhone; it won't sync to your other devices."
    public static let unknownAccount = "Unknown account"

    /// The account line under a calendar or list title: the account name, never empty.
    public static func subtitle(_ info: AppleCalendarInfo) -> String {
        info.accountName.isEmpty ? unknownAccount : info.accountName
    }

    /// "Home · iCloud": the title plus its account, so same-titled calendars differ.
    public static func named(_ info: AppleCalendarInfo) -> String {
        "\(info.title) · \(subtitle(info))"
    }

    /// The local-only warning, or nil when the destination syncs (or is unknown).
    public static func warning(for info: AppleCalendarInfo?) -> String? {
        info?.isLocalOnly == true ? localOnlyWarning : nil
    }

    /// "Added to Home · iCloud", or plain "Added" when the calendar's info is not available.
    public static func addedNotice(calendar: AppleCalendarInfo?) -> String {
        guard let calendar else { return "Added" }
        return "Added to \(named(calendar))"
    }
}
