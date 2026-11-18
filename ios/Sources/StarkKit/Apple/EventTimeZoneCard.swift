// ios/Sources/StarkKit/Apple/EventTimeZoneCard.swift
import Foundation

/// "Tokyo · 9:00 AM–10:00 AM JST (your time 7:00 PM–8:00 PM)" for a timed event whose time zone
/// is not the phone's at the event's start.
public struct EventTimeZoneCard: Equatable, Sendable {
    /// The zone's city, e.g. "Tokyo".
    public let zoneName: String
    /// The event's range in its own zone with the zone abbreviation, e.g. "9:00 AM–10:00 AM JST".
    public let eventRange: String
    /// The same range on the phone, e.g. "7:00 PM–8:00 PM".
    public let yourRange: String

    public init(zoneName: String, eventRange: String, yourRange: String) {
        self.zoneName = zoneName
        self.eventRange = eventRange
        self.yourRange = yourRange
    }

    public var summary: String { "\(zoneName) · \(eventRange) (your time \(yourRange))" }
}

extension AgendaItem {
    /// The conference link of an Apple event row; nil for reminders and Stark's own rows.
    public var conferenceLink: ConferenceLink? {
        guard case .event = kind, let source = appleSource, !source.isReminder else { return nil }
        return source.conferenceLink
    }

    /// The row shows a video glyph: a timed event with a join link (all-day chips and reminders
    /// never do).
    public var showsJoinGlyph: Bool {
        guard case .event(let event) = kind, !event.isAllDay else { return false }
        return conferenceLink != nil
    }

    /// The time zone card of an Apple event row, nil when the event has no other zone.
    public func timeZoneCard(phoneZone: TimeZone, locale: Locale) -> EventTimeZoneCard? {
        guard case .event(let event) = kind, let source = appleSource, !source.isReminder else { return nil }
        return EventTimeZoneCardMaker.make(start: event.start, end: event.end, isAllDay: event.isAllDay,
                                           timeZoneID: source.timeZoneID, phoneZone: phoneZone, locale: locale)
    }
}

public enum EventTimeZoneCardMaker {
    /// Nil for an all-day or floating event, an unknown zone ID, or a zone whose offset at `start`
    /// equals the phone's (so London and Dublin in winter show nothing). A day ("Thu, Nov 19,") is
    /// put in front of the start in the event's zone when that day differs from the start's day on
    /// the phone, and in front of the end, in either zone, when the end is on another day than the
    /// start in that zone. The phone's own start never carries a day.
    public static func make(start: Date, end: Date?, isAllDay: Bool, timeZoneID: String?,
                            phoneZone: TimeZone, locale: Locale) -> EventTimeZoneCard? {
        guard !isAllDay, let timeZoneID, let zone = TimeZone(identifier: timeZoneID),
              zone.secondsFromGMT(for: start) != phoneZone.secondsFromGMT(for: start) else { return nil }
        let end = end.flatMap { $0 > start ? $0 : nil }

        func calendar(_ tz: TimeZone) -> Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = tz
            return calendar
        }
        func dayKey(_ date: Date, in tz: TimeZone) -> DateComponents {
            calendar(tz).dateComponents([.year, .month, .day], from: date)
        }
        func range(in tz: TimeZone, showStartDay: Bool) -> String {
            let time = DateFormatter()
            time.locale = locale
            time.timeZone = tz
            time.dateStyle = .none
            time.timeStyle = .short
            let day = DateFormatter()
            day.locale = locale
            day.calendar = calendar(tz)
            day.timeZone = tz
            day.setLocalizedDateFormatFromTemplate("EEEMMMd")
            // Newer systems put a narrow no-break space before AM/PM; a plain space reads the same
            // and keeps the text comparable.
            func timeText(_ date: Date) -> String {
                time.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
            }
            var text = (showStartDay ? "\(day.string(from: start)), " : "") + timeText(start)
            if let end {
                let endDay = dayKey(end, in: tz) != dayKey(start, in: tz) ? "\(day.string(from: end)), " : ""
                text += "–\(endDay)\(timeText(end))"
            }
            return text
        }

        let style: NSTimeZone.NameStyle = zone.isDaylightSavingTime(for: start) ? .shortDaylightSaving : .shortStandard
        var abbreviation = zone.localizedName(for: style, locale: locale) ?? zone.abbreviation(for: start) ?? ""
        if abbreviation == "GMT+0" { abbreviation = "GMT" }
        // An Etc/ID has no city: "Etc/GMT-9" is UTC+9, and a name of "GMT-9" would contradict "GMT+9".
        let name = timeZoneID.hasPrefix("Etc/") && !abbreviation.isEmpty
            ? abbreviation
            : (timeZoneID.split(separator: "/").last.map(String.init) ?? timeZoneID).replacingOccurrences(of: "_", with: " ")
        let showStartDay = dayKey(start, in: zone) != dayKey(start, in: phoneZone)
        return EventTimeZoneCard(zoneName: name,
                                 eventRange: "\(range(in: zone, showStartDay: showStartDay)) \(abbreviation)"
                                     .trimmingCharacters(in: .whitespaces),
                                 yourRange: range(in: phoneZone, showStartDay: false))
    }
}
