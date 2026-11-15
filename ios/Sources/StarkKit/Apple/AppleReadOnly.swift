// ios/Sources/StarkKit/Apple/AppleReadOnly.swift
import Foundation

extension AgendaItem {
    /// The one gate for Apple Calendar / Reminders overlay rows: they are shown, never changed.
    /// A read-only item must never reach a `PlannerStore` call or a Stark edit, plan, convert,
    /// skip or complete path.
    public var isReadOnly: Bool { appleSource != nil }
}

/// What tapping an agenda or Search row opens. The only way to get an `AgendaItem` for the
/// Stark edit sheet is `editable`, which is nil for a read-only (Apple) item.
public enum AgendaItemDetail: Identifiable, Equatable {
    case edit(AgendaItem)
    case readOnly(AgendaItem)

    public init(_ item: AgendaItem) {
        self = item.isReadOnly ? .readOnly(item) : .edit(item)
    }

    public var id: String {
        switch self {
        case .edit(let item), .readOnly(let item): return item.id
        }
    }

    /// The item for the Stark edit sheet, or nil when the item is read-only.
    public var editable: AgendaItem? {
        guard case .edit(let item) = self else { return nil }
        return item
    }
}

/// The URL that opens a read-only Apple item in Calendar or Reminders, or nil for a Stark item.
///
/// - Event: `calshow:<seconds since 2001-01-01>` of the tapped occurrence (Calendar opens on
///   that day).
/// - Reminder: `x-apple-reminderkit://REMCDReminder/<calendarItemIdentifier>`, the identifier
///   being the item id without its `apple-` prefix.
///
/// Neither scheme is documented by Apple; both are to be confirmed on a device (plan Task 9) and
/// the link removed if they do not open the app.
public func appleOpenURL(for item: AgendaItem) -> URL? {
    guard let source = item.appleSource else { return nil }
    switch item.kind {
    case .event:
        guard !source.isReminder else { return nil }
        return URL(string: "calshow:\(Int(item.occurrence.timeIntervalSinceReferenceDate))")
    case .reminder(let reminder):
        let prefix = "apple-"
        guard reminder.id.hasPrefix(prefix) else { return nil }
        let identifier = String(reminder.id.dropFirst(prefix.count))
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard !identifier.isEmpty,
              let encoded = identifier.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "x-apple-reminderkit://REMCDReminder/\(encoded)")
    }
}

extension AppleSource {
    /// The calendar's colour as `0xRRGGBB`, parsed from `colorHex` ("#RRGGBB"); nil when absent
    /// or malformed.
    public var colorRGB: UInt32? {
        guard let hex = colorHex, hex.count == 7, hex.first == "#" else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits, radix: 16)
    }
}
