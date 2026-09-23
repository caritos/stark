// ios/Tests/StarkKitTests/MilestoneTests.swift
import Testing
import Foundation
@testable import StarkKit

struct MilestoneTests {
    private static let cal = Calendar(identifier: .gregorian)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Self.cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: kind

    @Test("a %birthday or %anniversary tag in the title marks the event")
    func detectsInTitle() {
        #expect(MilestoneTag.kind(title: "~amelia %birthday", notes: nil) == .birthday)
        #expect(MilestoneTag.kind(title: "Mom & Dad %anniversary", notes: nil) == .anniversary)
    }

    @Test("the tag is found in the notes too")
    func detectsInNotes() {
        #expect(MilestoneTag.kind(title: "Amelia", notes: "party at 5 %birthday") == .birthday)
    }

    @Test("matching ignores case and trailing punctuation")
    func caseAndPunctuation() {
        #expect(MilestoneTag.kind(title: "Amelia %Birthday", notes: nil) == .birthday)
        #expect(MilestoneTag.kind(title: "Amelia %BIRTHDAY!", notes: nil) == .birthday)
        #expect(MilestoneTag.kind(title: "(Amelia %anniversary),", notes: nil) == .anniversary)
    }

    @Test("only the whole tag counts")
    func wholeTagOnly() {
        #expect(MilestoneTag.kind(title: "birthday party", notes: nil) == nil)
        #expect(MilestoneTag.kind(title: "%birthdays", notes: nil) == nil)
        #expect(MilestoneTag.kind(title: "%birthday-party", notes: nil) == nil)
        #expect(MilestoneTag.kind(title: "%bday", notes: nil) == nil)
        #expect(MilestoneTag.kind(title: "Plain event", notes: "no tags") == nil)
    }

    @Test("a birthday wins when both tags are present")
    func birthdayWins() {
        #expect(MilestoneTag.kind(title: "%anniversary %birthday", notes: nil) == .birthday)
    }

    // MARK: years

    @Test("years are the difference between the occurrence's year and the start's year")
    func yearsBetween() {
        #expect(MilestoneTag.years(start: day(2010, 11, 11), occurrence: day(2026, 11, 11)) == 16)
        #expect(MilestoneTag.years(start: day(2025, 3, 1), occurrence: day(2026, 3, 1)) == 1)
    }

    @Test("no years for the original date or anything before it")
    func noYearsForOriginal() {
        #expect(MilestoneTag.years(start: day(2010, 11, 11), occurrence: day(2010, 11, 11)) == nil)
        #expect(MilestoneTag.years(start: day(2010, 11, 11), occurrence: day(2009, 11, 11)) == nil)
    }

    // MARK: note

    @Test("a birthday reads 'Turns N'")
    func birthdayNote() {
        #expect(MilestoneTag.note(for: .birthday, years: 16) == "Turns 16")
        #expect(MilestoneTag.note(for: .birthday, years: 1) == "Turns 1")
    }

    @Test("an anniversary reads 'N years', singular for one")
    func anniversaryNote() {
        #expect(MilestoneTag.note(for: .anniversary, years: 16) == "16 years")
        #expect(MilestoneTag.note(for: .anniversary, years: 1) == "1 year")
    }

    @Test("no note without a year count")
    func noNoteWithoutYears() {
        #expect(MilestoneTag.note(for: .birthday, years: nil) == nil)
    }

    @Test("a birthday gets a cake and an anniversary a party popper")
    func emoji() {
        #expect(Milestone.birthday.emoji == "🎂")
        #expect(Milestone.anniversary.emoji == "🎉")
    }

    // MARK: AgendaItem

    @Test("an event occurrence exposes its milestone and age")
    func agendaItemMilestone() {
        let event = Event(title: "~amelia %birthday", start: day(2010, 11, 11), isAllDay: true)
        let item = AgendaItem(kind: .event(event), occurrence: day(2026, 11, 11),
                              displayDate: day(2026, 11, 11), isOverdue: false)
        #expect(item.milestone?.kind == .birthday)
        #expect(item.milestone?.years == 16)
        #expect(item.milestone?.note == "Turns 16")
    }

    @Test("a birthday at its original date has the tag but no age")
    func agendaItemOriginalDate() {
        let event = Event(title: "~amelia %birthday", start: day(2010, 11, 11), isAllDay: true)
        let item = AgendaItem(kind: .event(event), occurrence: day(2010, 11, 11),
                              displayDate: day(2010, 11, 11), isOverdue: false)
        #expect(item.milestone?.kind == .birthday)
        #expect(item.milestone?.note == nil)
    }

    @Test("untagged events and reminders have no milestone")
    func agendaItemNone() {
        let event = Event(title: "Dentist", start: day(2026, 5, 1))
        #expect(AgendaItem(kind: .event(event), occurrence: day(2026, 5, 1),
                           displayDate: day(2026, 5, 1), isOverdue: false).milestone == nil)
        let reminder = Reminder(title: "call %birthday person", dueDate: day(2026, 5, 1))
        #expect(AgendaItem(kind: .reminder(reminder), occurrence: day(2026, 5, 1),
                           displayDate: day(2026, 5, 1), isOverdue: false).milestone == nil)
    }
}
