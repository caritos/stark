// ios/Sources/StarkKit/Planner/Milestone.swift
import Foundation

/// A birthday or anniversary, marked by a `%birthday` / `%anniversary` tag in an event's title
/// or notes. Like the other `%label` tags this is just text in the model (no structured field);
/// this is the one place the app reads meaning out of it, to show an age and an emoji.
public enum Milestone: Equatable, Sendable {
    case birthday
    case anniversary

    /// Shown in front of the agenda row's title (a prefix, so it survives truncation).
    public var emoji: String {
        switch self {
        case .birthday: "🎂"
        case .anniversary: "🎉"
        }
    }
}

public enum MilestoneTag {
    /// The milestone an event's title or notes mark, if any. Whole-tag match, case-insensitive,
    /// ignoring punctuation stuck to the end of the word (`%birthday,`); `%birthdays` and
    /// `%birthday-party` are not the tag. A birthday wins if both are present.
    public static func kind(title: String, notes: String?) -> Milestone? {
        var found: Set<Milestone> = []
        for text in [title, notes ?? ""] {
            for word in text.split(whereSeparator: \.isWhitespace) {
                switch normalized(word) {
                case "%birthday": found.insert(.birthday)
                case "%anniversary": found.insert(.anniversary)
                default: break
                }
            }
        }
        if found.contains(.birthday) { return .birthday }
        return found.contains(.anniversary) ? .anniversary : nil
    }

    /// Whole years from `start`'s year to `occurrence`'s year, nil for the original date or
    /// anything before it (nothing useful to say: age 0 is the birth itself). The event's own
    /// start date is the birth or wedding date, so this counts calendar years, which is exactly
    /// the age on the occurrence's day.
    public static func years(
        start: Date,
        occurrence: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Int? {
        let years = calendar.component(.year, from: occurrence) - calendar.component(.year, from: start)
        return years > 0 ? years : nil
    }

    /// "Turns 16" for a birthday, "16 years" (or "1 year") for an anniversary; nil without years.
    public static func note(for kind: Milestone, years: Int?) -> String? {
        guard let years else { return nil }
        switch kind {
        case .birthday: return "Turns \(years)"
        case .anniversary: return years == 1 ? "1 year" : "\(years) years"
        }
    }

    /// Lowercased, with trailing punctuation removed, so `%Birthday!` compares equal to
    /// `%birthday` but `%birthday-party` does not.
    private static func normalized(_ word: Substring) -> String {
        var text = word.lowercased()
        while let last = text.last, last.isPunctuation || last.isSymbol, last != "%" {
            text.removeLast()
        }
        while let first = text.first, first.isPunctuation, first != "%" {
            text.removeFirst()
        }
        return text
    }
}

/// What the agenda row shows for a birthday or anniversary occurrence.
public struct MilestoneInfo: Equatable, Sendable {
    public let kind: Milestone
    /// Nil on the original date (see `MilestoneTag.years`).
    public let years: Int?

    public var emoji: String { kind.emoji }
    public var note: String? { MilestoneTag.note(for: kind, years: years) }
}

extension AgendaItem {
    /// Set for an event tagged `%birthday` / `%anniversary`; nil for everything else (a reminder
    /// with the tag in its title is not a milestone -- only events have a start that is a birth
    /// or wedding date).
    public var milestone: MilestoneInfo? {
        guard case .event(let event) = kind,
              let milestone = MilestoneTag.kind(title: event.title, notes: event.notes) else { return nil }
        return MilestoneInfo(kind: milestone,
                             years: MilestoneTag.years(start: event.start, occurrence: occurrence))
    }
}
