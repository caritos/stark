// ios/Tests/StarkKitTests/SearchResultsTests.swift
import Testing
import Foundation
@testable import StarkKit

struct SearchResultsTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("matches title, notes, and location for events; title and notes for reminders")
    func matchesRelevantFields() {
        let today = DateMath.date(from: "2026-09-23")
        let events = [
            Event(title: "Team Standup", start: DateMath.date(from: "2026-09-24")),
            Event(title: "Unrelated", notes: "mentions standup in notes", start: DateMath.date(from: "2026-09-25")),
            Event(title: "Also unrelated", start: DateMath.date(from: "2026-09-26"), location: "Standup Room"),
            Event(title: "Nothing matches here", start: DateMath.date(from: "2026-09-27")),
        ]
        let reminders = [
            Reminder(title: "Standup notes", dueDate: DateMath.date(from: "2026-09-24")),
            Reminder(title: "Something else", notes: "standup follow-up", dueDate: DateMath.date(from: "2026-09-25")),
            Reminder(title: "No match", dueDate: DateMath.date(from: "2026-09-26")),
        ]

        let results = SearchResults.find(events: events, reminders: reminders, query: "standup", today: today)

        #expect(results.count == 5)
    }

    @Test("case-insensitive")
    func caseInsensitive() {
        let today = DateMath.date(from: "2026-09-23")
        let events = [Event(title: "BIRTHDAY PARTY", start: today)]
        let results = SearchResults.find(events: events, reminders: [], query: "birthday", today: today)
        #expect(results.count == 1)
    }

    @Test("empty query returns no results")
    func emptyQueryReturnsNothing() {
        let today = DateMath.date(from: "2026-09-23")
        let events = [Event(title: "Anything", start: today)]
        #expect(SearchResults.find(events: events, reminders: [], query: "", today: today).isEmpty)
    }

    @Test("a recurring event's result carries the next upcoming occurrence, not the series anchor")
    func recurringEventUsesUpcomingOccurrence() {
        let today = DateMath.date(from: "2026-09-23")
        // Anchor is far in the past; weekly on the anchor's weekday (Wednesday).
        let anchor = DateMath.date(from: "2024-01-03")
        let event = Event(
            title: "Weekly Sync",
            start: anchor,
            recurrence: RecurrenceRule(frequency: .weekly, interval: 1)
        )

        let results = SearchResults.find(events: [event], reminders: [], query: "sync", today: today)

        #expect(results.count == 1)
        let occurrence = results[0].occurrence
        #expect(occurrence >= today)
        #expect(!calendar.isDate(occurrence, inSameDayAs: anchor))
    }

    @Test("a recurring reminder past its recur-until falls back to its most recent occurrence")
    func recurringReminderPastEndUsesLastOccurrence() {
        let today = DateMath.date(from: "2026-09-23")
        let anchor = DateMath.date(from: "2026-01-01")
        let until = DateMath.date(from: "2026-02-01")
        let reminder = Reminder(
            title: "Ended Series",
            dueDate: anchor,
            recurrence: RecurrenceRule(frequency: .weekly, interval: 1, until: until)
        )

        let results = SearchResults.find(events: [], reminders: [reminder], query: "ended", today: today)

        #expect(results.count == 1)
        #expect(results[0].occurrence <= until)
    }

    @Test("a reminder with no due date is not lost -- sorts to the very beginning, not 'now'")
    func undatedReminderSortsFirst() {
        let today = DateMath.date(from: "2026-09-23")
        let dated = Reminder(title: "Dated Match", dueDate: today)
        let undated = Reminder(title: "Undated Match", dueDate: nil)

        let results = SearchResults.find(events: [], reminders: [dated, undated], query: "match", today: today)

        #expect(results.count == 2)
        #expect(results[0].title == "Undated Match")
    }

    @Test("results are sorted by occurrence date")
    func sortedByDate() {
        let today = DateMath.date(from: "2026-09-23")
        let events = [
            Event(title: "Match Later", start: DateMath.date(from: "2026-10-01")),
            Event(title: "Match Earlier", start: DateMath.date(from: "2026-09-24")),
        ]
        let results = SearchResults.find(events: events, reminders: [], query: "match", today: today)
        #expect(results.map(\.title) == ["Match Earlier", "Match Later"])
    }
}
