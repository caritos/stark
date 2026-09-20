// ios/App/Stark/Stark/AgendaRow.swift
import SwiftUI
import StarkKit

/// One agenda row, Fantastical-style structure in Braun styling: a fixed-width marker column
/// (square checkbox for reminders; for events a small filled square, a filled square with a
/// check when attended, and an outlined square with a cross when skipped) and a text column
/// with a small time line, the title (an incomplete reminder's priority marks `!`/`!!`/`!!!`
/// come before it, in the accent colour), and (events) the location. The date lives in the section header, so the row never shows one
/// except for an overdue reminder's missed date.
///
/// This view is **visuals only** — nothing in it is tappable. The taps live in
/// `AgendaRowTargets`, laid over the whole row by `AgendaView` (see the note there).
struct AgendaRowView: View {
    let item: AgendaItem
    /// A completion the user has started but that hasn't been committed yet (the 2.5s undo
    /// window, see `PendingCompletions`). It looks exactly like a completed reminder.
    var isPending = false

    private static let markerSize: CGFloat = 16

    /// Completed, or about to be: the filled check, struck-through secondary-colour title.
    private var looksDone: Bool { item.isCompleted || isPending }

    /// An event occurrence the user marked attended or "didn't attend": still shown, but dimmed
    /// and struck like a completed reminder. The marker (check vs cross) says which.
    private var hasOutcome: Bool { item.outcome != nil }

    /// The `!` / `!!` / `!!!` prefix: only for a reminder that has a priority and doesn't yet
    /// look done. It is a prefix so it survives the title's truncation.
    private var showsPriorityMarks: Bool { item.priority != .none && !looksDone }

    private var priorityWord: String {
        switch item.priority {
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        case .none: ""
        }
    }

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
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    if showsPriorityMarks {
                        Text(item.priority.marks)
                            .font(Fonts.mono(14))
                            .foregroundStyle(Colors.accent)
                    }
                    Text(item.title)
                        .strikethrough(looksDone || hasOutcome)
                        .foregroundStyle(looksDone || hasOutcome ? Colors.textSecondary : Colors.text)
                }
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
            switch item.outcome {
            case nil:
                Rectangle()
                    .fill(Colors.accent)
                    .frame(width: 8, height: 8)
            case .attended:
                checkedMarker
            case .skipped:
                Rectangle()
                    .strokeBorder(Colors.checkboxBorder, lineWidth: 1.5)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Colors.textSecondary)
                    }
            }
        case .reminder:
            if looksDone {
                checkedMarker
            } else {
                // An overdue reminder's outline is accent-coloured (the Expo app's
                // `agendaIconOverdue`); a pending one is `looksDone` and never gets here.
                Rectangle()
                    .strokeBorder(item.isOverdue ? Colors.accent : Colors.checkboxBorder, lineWidth: 1.5)
            }
        }
    }

    /// The filled accent square with a check: a completed reminder, or an attended event.
    private var checkedMarker: some View {
        Rectangle()
            .fill(Colors.accent)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Colors.background)
            }
    }

    // MARK: Accessibility

    /// What VoiceOver reads for the row's "open details" button: the same information the
    /// (hidden) visuals show.
    var accessibilitySummary: String {
        var parts: [String] = []
        if let timeLine { parts.append(timeLine.text) }
        parts.append(item.title)
        if showsPriorityMarks { parts.append("\(priorityWord) priority") }
        if let location { parts.append(location) }
        if looksDone { parts.append("completed") }
        if item.outcome == .attended {
            parts.append("attended")
        } else if item.outcome == .skipped {
            parts.append("didn't attend")
        }
        return parts.joined(separator: ", ")
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

/// The row's tap targets, laid over the row's visuals with `.overlay` (see `AgendaView`).
///
/// **Why it is built this way.** The row used to be one `Button` wrapping everything, so the
/// checkbox was just a picture inside the "open details" button: tapping it opened the sheet.
/// The two taps must never compete, so this makes it impossible for them to:
///
/// 1. **No nesting.** A `Button` inside another `Button`'s label does not work in SwiftUI (the
///    outer one swallows the tap). The two buttons here are siblings in an `HStack`, and neither
///    contains the other or any other interactive view.
/// 2. **No overlap.** The `HStack` partitions the row rectangle exactly: the checkbox button
///    gets a fixed 44pt-wide strip from the row's leading edge, the details button gets all the
///    rest, and both stretch the full row height. Every point of the row belongs to exactly one
///    button, so no hit-test priority rule ever has to pick a winner. (Reminder rows only; an
///    event's marker is decorative, so an event row is a single details button.)
/// 3. **Explicit `.buttonStyle(.plain)` on each.** In a `List` row the default (`.automatic`)
///    button style makes the whole row one tap target that fires every `Button` inside it;
///    `.plain` (like `.borderless`) makes each `Button` its own independent target.
/// 4. **Real hit areas.** The labels are `Color.clear` with `.contentShape(Rectangle())`, since
///    a transparent view isn't hit-testable by default and a `.plain` button only responds
///    where its label's content shape is.
///
/// The visuals underneath stay exactly as they were (they aren't tappable at all — the overlay
/// sits on top), and are hidden from VoiceOver so it sees only these two labelled buttons.
struct AgendaRowTargets: View {
    /// Whether the checkbox currently *shows* done (completed, or a pending completion).
    let looksDone: Bool
    let summary: String
    let onSelect: () -> Void
    /// Nil for events, which have no checkbox.
    let onToggleComplete: (() -> Void)?

    /// Apple's minimum touch target.
    static let checkboxWidth: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            if let onToggleComplete {
                Button(action: onToggleComplete) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: Self.checkboxWidth)
                .accessibilityLabel(looksDone ? "Mark incomplete" : "Mark complete")
            }
            Button(action: onSelect) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summary)
            .accessibilityHint("Opens details")
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
