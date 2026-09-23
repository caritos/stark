// ios/Sources/StarkKit/Planner/TagAutocomplete.swift
import Foundation

/// Tag-completion for the four free-form sigils this app's users write into titles, notes, and
/// locations: `+project` and `@context` (todo.txt's own two), and `%label`/`~person`
/// (app-specific, no structured meaning -- just text). None of these are parsed into a
/// structured field anywhere in `Event`/`Reminder`; this exists purely to help re-type a token
/// you've already used elsewhere (e.g. typing `~s` after already having written `~sophia`
/// somewhere suggests it back to you), mirroring a feature originally built the same way in the
/// deprecated Expo app's `AddTaskModal`.
public enum TagAutocomplete {
    private static let sigils: Set<Character> = ["+", "@", "%", "~"]

    /// The sigil-prefixed word currently being typed, if any.
    public struct Prefix: Equatable {
        public let sigil: Character
        public let partial: String
    }

    /// Looks only at the *last word* of `text` -- true to how a plain, append-as-you-type text
    /// field behaves, and the same simplification the Expo app's version made (no actual cursor-
    /// position tracking). Splitting with `omittingEmptySubsequences: false` matters here: once
    /// the user types a trailing space after finishing a tag, the "last word" becomes an empty
    /// string, which correctly closes the suggestion row instead of continuing to match the tag
    /// they just finished typing against itself.
    public static func currentPrefix(in text: String) -> Prefix? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              let first = last.first, sigils.contains(first) else {
            return nil
        }
        return Prefix(sigil: first, partial: String(last))
    }

    /// Every distinct token across `events`'/`reminders`' title and notes that starts with
    /// `prefix.sigil` and whose text starts with `prefix.partial`, case-insensitively, sorted.
    /// Scans fresh on every call rather than maintaining an index, the same choice the Expo
    /// app's version made -- fine at this app's dataset sizes (thousands of items), and much
    /// simpler than keeping a derived index in sync with every add/edit/delete.
    public static func suggestions(for prefix: Prefix, events: [Event], reminders: [Reminder]) -> [String] {
        var found: Set<String> = []
        for event in events {
            collect(from: event.title, sigil: prefix.sigil, into: &found)
            collect(from: event.notes, sigil: prefix.sigil, into: &found)
        }
        for reminder in reminders {
            collect(from: reminder.title, sigil: prefix.sigil, into: &found)
            collect(from: reminder.notes, sigil: prefix.sigil, into: &found)
        }
        let needle = prefix.partial.lowercased()
        return found.filter { $0.lowercased().hasPrefix(needle) }.sorted()
    }

    /// Replaces `text`'s last word (the one the user was typing) with `tag`, and appends a
    /// trailing space so typing can continue right after it.
    public static func applying(_ tag: String, to text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard !words.isEmpty else { return tag + " " }
        words[words.count - 1] = tag
        return words.joined(separator: " ") + " "
    }

    /// A token is the sigil plus one or more non-space characters -- a bare sigil alone (nothing
    /// after it) is never collected, matching the Expo version's `sigil\S+` regex.
    private static func collect(from text: String?, sigil: Character, into found: inout Set<String>) {
        guard let text else { return }
        for word in text.split(separator: " ") where word.first == sigil && word.count > 1 {
            found.insert(String(word))
        }
    }
}
