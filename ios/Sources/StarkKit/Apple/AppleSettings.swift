// ios/Sources/StarkKit/Apple/AppleSettings.swift
import Foundation

/// One account's calendars and reminder lists in the Settings > "Apple Calendar and Reminders"
/// screen.
public struct AppleAccountGroup: Equatable, Identifiable, Sendable {
    public let accountName: String
    public let calendars: [AppleCalendarInfo]

    public var id: String { accountName }

    public init(accountName: String, calendars: [AppleCalendarInfo]) {
        self.accountName = accountName
        self.calendars = calendars
    }
}

/// Presentation logic for the Apple overlay's Settings screen, so the view stays thin.
public enum AppleSettings {
    /// The header for calendars that report no account (local ones).
    public static let localAccountName = "On My iPhone"

    /// Groups by account (case-insensitive, then exact), and within an account lists calendars
    /// before reminder lists, each by title (case-insensitive) with the id as the tiebreak, so
    /// the order never depends on EventKit's.
    public static func groupedByAccount(_ calendars: [AppleCalendarInfo]) -> [AppleAccountGroup] {
        let byAccount = Dictionary(grouping: calendars) { $0.accountName.isEmpty ? localAccountName : $0.accountName }
        return byAccount.keys
            .sorted { lhs, rhs in
                let order = lhs.caseInsensitiveCompare(rhs)
                return order == .orderedSame ? lhs < rhs : order == .orderedAscending
            }
            .map { name in
                AppleAccountGroup(accountName: name, calendars: byAccount[name, default: []].sorted(by: calendarOrder))
            }
    }

    /// One short word or two for the status row's value.
    public static func statusLabel(_ access: AppleAccess) -> String {
        switch access {
        case .notAsked: "Not asked"
        case .granted: "Full access"
        case .denied: "Denied"
        case .writeOnly: "Add only"
        }
    }

    /// The access state in plain words.
    public static func statusText(_ access: AppleAccess) -> String {
        switch access {
        case .notAsked: "Not asked yet. Stark asks for access when you turn this on."
        case .granted: "Stark can read your calendars and reminders. It never changes them."
        case .denied: "Access is off. Allow Stark full access to Calendars and Reminders in iOS Settings."
        case .writeOnly: "Stark can only add events, not read them. Allow full access in iOS Settings."
        }
    }

    /// A row that opens iOS Settings, the only place a refusal can be undone.
    public static func showsOpenSettings(_ access: AppleAccess) -> Bool {
        access == .denied || access == .writeOnly
    }

    /// The per-calendar toggles, only when the overlay is on and can read.
    public static func showsCalendars(isEnabled: Bool, access: AppleAccess) -> Bool {
        isEnabled && access == .granted
    }

    private static func calendarOrder(_ lhs: AppleCalendarInfo, _ rhs: AppleCalendarInfo) -> Bool {
        if lhs.isReminderList != rhs.isReminderList { return !lhs.isReminderList }
        let order = lhs.title.caseInsensitiveCompare(rhs.title)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id < rhs.id
    }
}

extension AppleCalendarInfo {
    /// The calendar's colour as `0xRRGGBB` (same parsing as `AppleSource.colorRGB`).
    public var colorRGB: UInt32? { AppleColor.rgb(colorHex) }
}

enum AppleColor {
    /// Parses "#RRGGBB"; nil when absent or malformed.
    static func rgb(_ hex: String?) -> UInt32? {
        guard let hex, hex.count == 7, hex.first == "#" else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits, radix: 16)
    }
}
