// ios/App/Stark/Stark/AgendaRow.swift
import SwiftUI
import StarkKit

/// One agenda row, Fantastical-style structure in Braun styling: a fixed-width marker column
/// (square checkbox for reminders; for events a small filled square, a filled square with a
/// check when attended, and an outlined square with a cross when skipped) and a text column
/// with a small time line, the title (an incomplete reminder's priority marks `!`/`!!`/`!!!`
/// come before it, in the accent colour), (a `%birthday`/`%anniversary` event) an emoji before the title and an age note under it, and (events) the location. The date lives in the section header, so the row never shows one
/// except for an overdue reminder's missed date.
///
/// A read-only Apple Calendar / Reminders row (`item.isReadOnly`) dims its marker (it is never a
/// working checkbox) and adds a source line: a 6 pt square in the calendar's own colour and the
/// calendar's title.
///
/// This view is **visuals only** — nothing in it is tappable. The taps live in
/// `AgendaRowTargets`, laid over the whole row by `AgendaView` (see the note there).
struct AgendaRowView: View {
    let item: AgendaItem
    /// A completion the user has started but that hasn't been committed yet (the 2.5s undo
    /// window, see `PendingCompletions`). It looks exactly like a completed reminder.
    var isPending = false
    /// The real today, for the overdue row's "N days overdue" suffix. Nil (Search, Weekly Review)
    /// shows no suffix.
    var today: Date? = nil

    private static let markerSize: CGFloat = 16
    /// A read-only row's marker is drawn, but dimmed so it never looks like a working checkbox.
    private static let readOnlyMarkerOpacity: CGFloat = 0.4

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

    /// The row's calendar colour: the Apple calendar's own colour, else the local-event purple.
    private var calendarColor: Color {
        item.appleSource?.colorRGB.map { Color(hex: $0) } ?? Colors.eventDot
    }

    /// A reminder's checkbox outline: the list colour, `checkboxBorder` for Stark's own.
    private var listColor: Color {
        item.appleSource?.colorRGB.map { Color(hex: $0) } ?? Colors.checkboxBorder
    }

    private var isAllDayEvent: Bool {
        if case .event(let event) = item.kind { return event.isAllDay && item.plannedRange == nil }
        return false
    }

    private var isReminder: Bool {
        if case .reminder = item.kind { return true }
        return false
    }

    var body: some View {
        if isAllDayEvent {
            allDayChip
        } else {
            standardRow
        }
    }

    /// An all-day event: a rounded chip filled with the calendar colour, white text, hugging
    /// the leading margin (not the full row width).
    private var allDayChip: some View {
        HStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                if let milestone = item.milestone {
                    Text(milestone.emoji).accessibilityHidden(true)
                }
                Text(item.title)
                    .font(.subheadline)
                    .strikethrough(hasOutcome)
                    .lineLimit(2)
                outcomeGlyph(color: .white)
                if item.isNotImported {
                    Text("· Not imported")
                        .font(.caption)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(calendarColor.opacity(hasOutcome ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 0)
        }
    }

    private var standardRow: some View {
        let timeLine = self.timeLine
        let milestone = item.milestone
        let isTimedEvent = !isReminder
        return HStack(alignment: .top, spacing: Spacing.sm) {
            if isTimedEvent {
                // 4 pt rounded bar in the calendar colour; the 16 pt column keeps the text aligned
                // with the reminders' checkbox column.
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(calendarColor)
                        .frame(width: 4)
                    Spacer(minLength: 0)
                }
                .frame(width: Self.markerSize)
            } else {
                marker
                    .frame(width: Self.markerSize, height: Self.markerSize)
                    .opacity(item.isReadOnly ? Self.readOnlyMarkerOpacity : 1)
                    .padding(.top, timeLine == nil ? 2 : 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let timeLine {
                    Text(drawnTimeText(timeLine))
                        .font(Font.footnote.monospacedDigit())
                        .foregroundStyle(timeLine.isAccent ? Color.red : Colors.textSecondary)
                }
                if let secondary = planLines?.secondary {
                    Text(secondary)
                        .font(Font.caption.monospacedDigit())
                        .foregroundStyle(Colors.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    if showsPriorityMarks {
                        Text(item.priority.marks)
                            .font(.body)
                            .foregroundStyle(Colors.accent)
                    }
                    // A birthday's cake / an anniversary's party popper, in front of the title so it
                    // survives truncation. Hidden from VoiceOver: `accessibilitySummary` says it.
                    if let milestone {
                        Text(milestone.emoji)
                            .accessibilityHidden(true)
                    }
                    (Text(item.title)
                        .strikethrough(looksDone || hasOutcome)
                     + repeatGlyph)
                        .foregroundStyle(looksDone || hasOutcome ? Colors.textSecondary : Colors.text)
                    outcomeGlyph(color: Colors.textSecondary)
                }
                if let note = milestone?.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Colors.textSecondary)
                }
                if let location {
                    Text(location)
                        .font(.footnote)
                        .foregroundStyle(Colors.textSecondary)
                        .lineLimit(2)
                }
                // The calendar colour already shows in the bar / checkbox; a source line stays
                // only where it says "read only".
                if let source = item.appleSource, item.isReadOnly {
                    AppleSourceLabel(source: source)
                }
                if item.isNotImported {
                    NotImportedLabel()
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The repeat glyph after the title of a repeating item (concatenated so it follows the
    /// title's last line instead of floating off at the row's edge).
    private var repeatGlyph: Text {
        guard item.showsRepeatGlyph else { return Text("") }
        return Text(" ") + Text(Image(systemName: "arrow.triangle.2.circlepath"))
            .font(.footnote)
            .foregroundColor(Colors.textSecondary)
    }

    /// An attended check / a "didn't attend" cross after an event's title.
    @ViewBuilder
    private func outcomeGlyph(color: Color) -> some View {
        switch item.outcome {
        case .attended:
            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(color)
        case .skipped:
            Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(color)
        case nil:
            EmptyView()
        }
    }

    /// What the time line draws: an overdue reminder shows only its missed date and time (red);
    /// the "N days overdue" text stays in `timeLine` for VoiceOver and the detail sheet.
    private func drawnTimeText(_ line: (text: String, isAccent: Bool)) -> String {
        guard line.isAccent, case .reminder = item.kind, item.isOverdue, planLines == nil else { return line.text }
        return AgendaFormat.overdueLabel(item.occurrence)
    }

    // MARK: Marker

    @ViewBuilder
    private var marker: some View {
        if looksDone {
            checkedMarker
        } else {
            // Outlined rounded square in the list colour; an overdue one is red.
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(item.isOverdue ? Color.red : listColor, lineWidth: 1.5)
        }
    }

    /// The filled rounded square with a check: a completed reminder.
    private var checkedMarker: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(listColor)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    // MARK: Accessibility

    /// What VoiceOver reads for the row's "open details" button: the same information the
    /// (hidden) visuals show.
    var accessibilitySummary: String {
        var parts: [String] = []
        if let range = item.plannedRange {
            parts.append("planned \(AgendaFormat.time(range.lowerBound)) to \(AgendaFormat.time(range.upperBound))")
            if let secondary = planLines?.secondary { parts.append(secondary) }
        } else if let timeLine { parts.append(timeLine.text) }
        parts.append(item.title)
        if let milestone = item.milestone {
            parts.append(milestone.kind == .birthday ? "birthday" : "anniversary")
            if let note = milestone.note { parts.append(note) }
        }
        if showsPriorityMarks { parts.append("\(priorityWord) priority") }
        if let location { parts.append(location) }
        if let source = item.appleSource { parts.append("from \(source.calendarTitle), read only") }
        if item.isNotImported { parts.append("not imported into Apple") }
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

    /// The overdue label for an overdue reminder row, as the unplanned row shows it.
    private var overdueText: String? {
        guard case .reminder = item.kind, item.isOverdue else { return nil }
        var text = AgendaFormat.overdueLabel(item.occurrence)
        if let today, let days = item.daysOverdue(today: today) {
            text += " · \(OverdueLabel.text(daysOverdue: days))"
        }
        return text
    }

    /// A planned row's range line and its secondary "due" line; nil for an unplanned row.
    private var planLines: PlanRowText.Lines? {
        guard let range = item.plannedRange, case .reminder = item.kind else { return nil }
        return PlanRowText.make(occurrence: item.occurrence, overdueText: overdueText,
                                range: range, time: AgendaFormat.time, monthDay: AgendaFormat.monthDay)
    }

    /// The row's small time line (also the read-only Apple detail's, so both read the same).
    var timeLine: (text: String, isAccent: Bool)? {
        if let planLines { return (planLines.primary, false) }
        switch item.kind {
        case .event(let event):
            if event.isAllDay { return ("All day", false) }
            // `item.occurrence` is this occurrence's start; the master's `end` belongs to its
            // first instance, so carry the master's duration over to this occurrence.
            let end = event.end.map { item.occurrence.addingTimeInterval($0.timeIntervalSince(event.start)) }
            return (AgendaFormat.eventTimeRange(start: item.occurrence, end: end), false)
        case .reminder:
            if item.isOverdue {
                var text = AgendaFormat.overdueLabel(item.occurrence)
                if let today, let days = item.daysOverdue(today: today) {
                    text += " · \(OverdueLabel.text(daysOverdue: days))"
                }
                return (text, true)
            }
            if item.isCompleted, let note = item.completionNote { return (note, false) }
            // An undated Apple reminder's occurrence is a sentinel: no time of day to show.
            if item.isUndatedApple { return nil }
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
    /// Nil for events, which have no checkbox, and for read-only (Apple) rows.
    let onToggleComplete: (() -> Void)?
    /// A read-only reminder row: the 44pt strip stays as an inert spacer (no button, so a tap
    /// there does nothing) and the layout matches a Stark reminder row.
    var showsInertCheckboxStrip = false

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
            } else if showsInertCheckboxStrip {
                Color.clear
                    .frame(width: Self.checkboxWidth)
                    .accessibilityHidden(true)
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

/// The source line of a read-only Apple row (and of its detail sheet): a 6 pt square in the
/// calendar's own colour (`AppleSource.colorRGB`; that colour is data, the only non-token colour
/// in the app, falling back to the secondary text colour) and the calendar title.
/// The "not imported" mark on a row of Stark's own item that Apple cannot hold (its repeat), so
/// it stays in Stark's files (Settings > Import Stark's own items lists why).
struct NotImportedLabel: View {
    var font: Font = .caption

    var body: some View {
        Label("Not imported", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            .font(font)
            .foregroundStyle(Colors.textSecondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }
}

struct AppleSourceLabel: View {
    let source: AppleSource
    var font: Font = .footnote

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Rectangle()
                .fill(source.colorRGB.map { Color(hex: $0) } ?? Colors.textSecondary)
                .frame(width: 6, height: 6)
            Text(source.calendarTitle)
                .font(font)
                .foregroundStyle(Colors.textSecondary)
                .lineLimit(1)
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
    private static let monthNameFormatter = formatter("LLLL")
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
    /// e.g. "September". Unlike `Calendar.standaloneMonthSymbols`, this is correctly localized —
    /// a bare `Calendar(identifier:)`'s `.locale` defaults to an empty "fixed" locale with no
    /// symbol data, so `standaloneMonthSymbols` falls back to locale-invariant identifiers
    /// ("M01".."M12") — but `DateFormatter`'s default locale is `Locale.current`-derived, so
    /// routing through the same formatter machinery as `monthYear` sidesteps the bug entirely
    /// (issue #102).
    static func monthName(_ date: Date) -> String { monthNameFormatter.string(from: date) }

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
