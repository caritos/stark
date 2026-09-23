// ios/Tests/StarkKitTests/TagAutocompleteTests.swift
import Testing
import Foundation
@testable import StarkKit

struct TagAutocompleteTests {
    // MARK: currentPrefix

    @Test("detects a sigil-prefixed partial word at the end of the text")
    func detectsPrefix() {
        #expect(TagAutocomplete.currentPrefix(in: "Call ~s") == TagAutocomplete.Prefix(sigil: "~", partial: "~s"))
        #expect(TagAutocomplete.currentPrefix(in: "+proj") == TagAutocomplete.Prefix(sigil: "+", partial: "+proj"))
        #expect(TagAutocomplete.currentPrefix(in: "@wor") == TagAutocomplete.Prefix(sigil: "@", partial: "@wor"))
        #expect(TagAutocomplete.currentPrefix(in: "buy milk %err") == TagAutocomplete.Prefix(sigil: "%", partial: "%err"))
    }

    @Test("no prefix when the last word has no sigil")
    func noPrefixForPlainWord() {
        #expect(TagAutocomplete.currentPrefix(in: "Call sophia") == nil)
        #expect(TagAutocomplete.currentPrefix(in: "") == nil)
    }

    @Test("no prefix once a space follows the tag -- closes suggestions after the word is finished")
    func noPrefixAfterTrailingSpace() {
        #expect(TagAutocomplete.currentPrefix(in: "Call ~sophia ") == nil)
    }

    @Test("a bare sigil with nothing after it is still an active (empty) prefix")
    func bareSigilIsAPrefix() {
        #expect(TagAutocomplete.currentPrefix(in: "~") == TagAutocomplete.Prefix(sigil: "~", partial: "~"))
    }

    // MARK: suggestions

    @Test("suggests matching tokens from event and reminder titles and notes, case-insensitively")
    func suggestsFromTitlesAndNotes() {
        let events = [
            Event(title: "Dinner with ~Sophia", start: Date()),
            Event(title: "Unrelated", notes: "follow up with ~sophie", start: Date()),
        ]
        let reminders = [
            Reminder(title: "Call ~sam", dueDate: Date()),
        ]
        let prefix = TagAutocomplete.Prefix(sigil: "~", partial: "~s")

        let suggestions = TagAutocomplete.suggestions(for: prefix, events: events, reminders: reminders)

        // Plain lexicographic sort (capital letters before lowercase, matching the Expo
        // version's own plain `.sort()`) -- not case-folded.
        #expect(suggestions == ["~Sophia", "~sam", "~sophie"])
    }

    @Test("only returns tokens matching the typed prefix, not other sigils or non-matching partials")
    func filtersByPrefix() {
        let events = [
            Event(title: "~sophia +errands @home %fun", start: Date()),
        ]
        let prefix = TagAutocomplete.Prefix(sigil: "~", partial: "~s")

        let suggestions = TagAutocomplete.suggestions(for: prefix, events: [], reminders: []) // no corpus
        #expect(suggestions.isEmpty)

        let matched = TagAutocomplete.suggestions(for: prefix, events: events, reminders: [])
        #expect(matched == ["~sophia"])
    }

    @Test("a bare sigil in the corpus (nothing after it) is never suggested")
    func bareSigilNeverSuggested() {
        let events = [Event(title: "trailing ~ alone", start: Date())]
        let prefix = TagAutocomplete.Prefix(sigil: "~", partial: "~")

        #expect(TagAutocomplete.suggestions(for: prefix, events: events, reminders: []).isEmpty)
    }

    @Test("deduplicates identical tokens across multiple items")
    func deduplicates() {
        let events = [
            Event(title: "~sophia", start: Date()),
            Event(title: "~sophia again", start: Date()),
        ]
        let prefix = TagAutocomplete.Prefix(sigil: "~", partial: "~s")

        #expect(TagAutocomplete.suggestions(for: prefix, events: events, reminders: []) == ["~sophia"])
    }

    // MARK: applying

    @Test("replaces the in-progress word with the chosen tag and appends a trailing space")
    func appliesSuggestion() {
        #expect(TagAutocomplete.applying("~sophia", to: "Call ~s") == "Call ~sophia ")
        #expect(TagAutocomplete.applying("~sophia", to: "~s") == "~sophia ")
    }

    // MARK: appending (keyboard sigil buttons)

    @Test("appends the sigil to empty text with no leading space")
    func appendsToEmpty() {
        #expect(TagAutocomplete.appending("~", to: "") == "~")
    }

    @Test("adds a separating space when the text ends in a word")
    func appendsWithSeparator() {
        #expect(TagAutocomplete.appending("~", to: "Call mom") == "Call mom ~")
        #expect(TagAutocomplete.appending("+", to: "Call ~sophia") == "Call ~sophia +")
    }

    @Test("adds no extra space when the text already ends in whitespace")
    func appendsAfterWhitespace() {
        #expect(TagAutocomplete.appending("~", to: "Call mom ") == "Call mom ~")
        #expect(TagAutocomplete.appending("@", to: "line one\n") == "line one\n@")
    }

    @Test("does nothing when the last word is already a bare sigil")
    func ignoresBareSigil() {
        #expect(TagAutocomplete.appending("~", to: "Call ~") == "Call ~")
        #expect(TagAutocomplete.appending("+", to: "Call ~") == "Call ~")
        #expect(TagAutocomplete.appending("%", to: "%") == "%")
        #expect(TagAutocomplete.appending("+", to: "line one\n~") == "line one\n~")
    }

    @Test("the appended sigil is an active prefix, so suggestions show at once")
    func appendedSigilOpensSuggestions() {
        let text = TagAutocomplete.appending("~", to: "Call mom")
        #expect(TagAutocomplete.currentPrefix(in: text) == TagAutocomplete.Prefix(sigil: "~", partial: "~"))
    }

    @Test("appending a sigil to a tag that is followed by a space starts a new tag")
    func appendsAfterFinishedTag() {
        let text = TagAutocomplete.appending("+", to: TagAutocomplete.applying("~sophia", to: "Call ~s"))
        #expect(text == "Call ~sophia +")
    }
}
