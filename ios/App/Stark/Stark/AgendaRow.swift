// ios/App/Stark/Stark/AgendaRow.swift
import SwiftUI
import StarkKit

/// One agenda row, Fantastical-style structure in Braun styling: a fixed-width marker column
/// (square checkbox for reminders, small filled square for events) and a text column with a
/// small time line, the title, and (events) the location. The date lives in the section header,
/// so the row never shows one except for an overdue reminder's missed date.
struct AgendaRowView: View {
    let item: AgendaItem

    private static let markerSize: CGFloat = 16

    var body: some View {
        let timeLine = self.timeLine
        HStack(alignment: .top, spacing: Spacing.sm) {
            marker
                .frame(width: Self.markerSize, height: Self.markerSize)
                .padding(.top, timeLine == nil ? 2 : 0)

            VStack(alignment: .leading, spacing: 2) {
                if let timeLine {
                    Text(timeLine.text)
                        .font(Fonts.mono(12))
                        .foregroundStyle(timeLine.isAccent ? Colors.accent : Colors.textSecondary)
                }
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Colors.textSecondary : Colors.text)
                if let location {
                    Text(location)
                        .font(.footnote)
                        .foregroundStyle(Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Marker

    @ViewBuilder
    private var marker: some View {
        switch item.kind {
        case .event:
            Rectangle()
                .fill(Colors.accent)
                .frame(width: 8, height: 8)
        case .reminder:
            if item.isCompleted {
                Rectangle()
                    .fill(Colors.accent)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Colors.background)
                    }
            } else {
                Rectangle()
                    .strokeBorder(Colors.checkboxBorder, lineWidth: 1.5)
            }
        }
    }

    // MARK: Text

    private var location: String? {
        guard case .event(let event) = item.kind, let location = event.location, !location.isEmpty else { return nil }
        return location
    }

    private var timeLine: (text: String, isAccent: Bool)? {
        switch item.kind {
        case .event(let event):
            if event.isAllDay { return ("All day", false) }
            // `item.occurrence` is this occurrence's start; the master's `end` belongs to its
            // first instance, so carry the master's duration over to this occurrence.
            let end = event.end.map { item.occurrence.addingTimeInterval($0.timeIntervalSince(event.start)) }
            return (AgendaFormat.eventTimeRange(start: item.occurrence, end: end), false)
        case .reminder:
            if item.isOverdue {
                return (AgendaFormat.overdueLabel(item.occurrence), true)
            }
            guard !AgendaFormat.isMidnight(item.occurrence) else { return nil }
            return (AgendaFormat.time(item.occurrence), false)
        }
    }
}

/// Explicit, locale-independent-in-structure formatting for agenda text.
enum AgendaFormat {
    private static let calendar = Calendar(identifier: .gregorian)

    private static func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = pattern
        return formatter
    }

    private static let monthDayFormatter = formatter("MMM d")
    private static let weekdayFormatter = formatter("EEEE")
    private static let shortDateFormatter = formatter("M/d/yy")
    private static let monthYearFormatter = formatter("LLLL yyyy")
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func monthDay(_ date: Date) -> String { monthDayFormatter.string(from: date) }
    static func weekdayName(_ date: Date) -> String { weekdayFormatter.string(from: date) }
    /// M/d/yy, e.g. "9/20/26".
    static func shortDate(_ date: Date) -> String { shortDateFormatter.string(from: date) }
    /// e.g. "September 2026".
    static func monthYear(_ date: Date) -> String { monthYearFormatter.string(from: date) }

    static func isMidnight(_ date: Date) -> Bool { calendar.startOfDay(for: date) == date }

    /// "Sep 19 at 6:00 AM", or just "Sep 19" for a date-only (midnight) occurrence.
    static func overdueLabel(_ occurrence: Date) -> String {
        guard !isMidnight(occurrence) else { return monthDay(occurrence) }
        return "\(monthDay(occurrence)) at \(time(occurrence))"
    }

    /// "2:30 – 3:30 PM" (the shared AM/PM is written once), "9:00 AM – 1:00 PM" when the
    /// periods differ, the bare start when there's no end, and "9:00 AM – Oct 25" when the
    /// event ends on a different day.
    static func eventTimeRange(start: Date, end: Date?) -> String {
        let startText = time(start)
        guard let end, end > start else { return startText }
        guard calendar.isDate(start, inSameDayAs: end) else {
            return "\(startText) – \(monthDay(end))"
        }
        let endText = time(end)
        // Drop the start's AM/PM only when both share the same one, in a 12-hour locale.
        for symbol in [timeFormatter.amSymbol, timeFormatter.pmSymbol].compactMap({ $0 }) {
            if startText.hasSuffix(symbol), endText.hasSuffix(symbol) {
                let trimmed = String(startText.dropLast(symbol.count))
                    .trimmingCharacters(in: .whitespaces)
                return "\(trimmed) – \(endText)"
            }
        }
        return "\(startText) – \(endText)"
    }
}
