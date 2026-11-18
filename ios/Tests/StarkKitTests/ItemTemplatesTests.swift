import Testing
import Foundation
@testable import StarkKit

private func snap(_ kind: TemplateKind = .event, title: String = "Dentist", duration: Int? = 60,
                  allDay: Bool = false, notes: String? = nil, url: String? = nil,
                  priority: ReminderPriority = .none, recurrence: RecurrenceRule? = nil,
                  destination: String? = "cal-1") -> TemplateSnapshot {
    TemplateSnapshot(kind: kind, title: title, durationMinutes: duration, allDay: allDay, notes: notes,
                     url: url, priority: priority, recurrence: recurrence, destinationID: destination)
}

@Suite struct ItemTemplatesTests {
    @Test func addTrimsNameAndStoresFields() throws {
        var t = ItemTemplates()
        let rule = RecurrenceRule(frequency: .weekly, count: 5, until: Date(timeIntervalSince1970: 1_800_000_000))
        let made = try t.add(name: "  Dentist  ", from: snap(notes: " n ", url: "https://x.y", recurrence: rule))
        #expect(made.name == "Dentist")
        #expect(made.title == "Dentist")
        #expect(made.durationMinutes == 60)
        #expect(made.notes == "n")
        #expect(made.url == "https://x.y")
        #expect(made.recurrence == rule.withoutEnd)
        #expect(made.recurrence?.count == nil && made.recurrence?.until == nil)
        #expect(t.templates.count == 1)
    }

    @Test func blankOrWhitespaceNotesAndUrlBecomeNil() throws {
        var t = ItemTemplates()
        let made = try t.add(name: "A", from: snap(notes: "  ", url: ""))
        #expect(made.notes == nil && made.url == nil)
    }

    @Test func nameRules() throws {
        var t = ItemTemplates()
        #expect(throws: TemplateError.emptyName) { try t.add(name: "   ", from: snap()) }
        #expect(throws: TemplateError.nameTooLong) { try t.add(name: String(repeating: "a", count: 31), from: snap()) }
        _ = try t.add(name: String(repeating: "a", count: 30), from: snap())
        _ = try t.add(name: "Lunch", from: snap())
        #expect(throws: TemplateError.duplicateName) { try t.add(name: "LUNCH", from: snap()) }
        #expect(TemplateError.duplicateName.message.isEmpty == false)
        #expect(TemplateError.emptyName.message.isEmpty == false)
    }

    @Test func emptyTitleIsRefused() {
        var t = ItemTemplates()
        #expect(throws: TemplateError.emptyTitle) { try t.add(name: "X", from: snap(title: "  ")) }
    }

    @Test func fiftyOneIsRefused() throws {
        var t = ItemTemplates()
        for i in 0..<50 { _ = try t.add(name: "T\(i)", from: snap()) }
        #expect(throws: TemplateError.tooMany) { try t.add(name: "One more", from: snap()) }
        #expect(t.templates.count == 50)
    }

    @Test func renameAndDelete() throws {
        var t = ItemTemplates()
        let a = try t.add(name: "A", from: snap())
        let b = try t.add(name: "B", from: snap())
        try t.rename(a.id, to: "a")          // same template, different case: allowed
        #expect(t.templates[0].name == "a")
        #expect(throws: TemplateError.duplicateName) { try t.rename(a.id, to: "b") }
        #expect(throws: TemplateError.notFound) { try t.rename(UUID(), to: "Z") }
        t.delete(b.id)
        #expect(t.templates.map(\.id) == [a.id])
        t.delete(UUID())
        #expect(t.templates.count == 1)
    }

    @Test func filtersByKind() throws {
        var t = ItemTemplates()
        _ = try t.add(name: "E", from: snap(.event))
        _ = try t.add(name: "R", from: snap(.reminder, duration: nil))
        #expect(t.templates(for: .event).map(\.name) == ["E"])
        #expect(t.templates(for: .reminder).map(\.name) == ["R"])
    }

    @Test func allDayHasNoDurationAndReminderHasNoUrlOrDuration() throws {
        var t = ItemTemplates()
        let a = try t.add(name: "A", from: snap(duration: 120, allDay: true))
        #expect(a.durationMinutes == nil && a.allDay)
        let r = try t.add(name: "R", from: snap(.reminder, duration: 30, url: "https://x", priority: .high))
        #expect(r.durationMinutes == nil && r.url == nil && r.priority == .high)
        let e = try t.add(name: "E", from: snap(.event, priority: .high))
        #expect(e.priority == .none)
    }

    @Test func missingCorruptAndNewerDataGiveNothing() throws {
        #expect(ItemTemplates.decode(nil).templates.isEmpty)
        #expect(ItemTemplates.decode(Data("nope".utf8)).templates.isEmpty)
        #expect(ItemTemplates.decode(Data(#"{"version":2,"templates":[]}"#.utf8)).templates.isEmpty)
        #expect(ItemTemplates.decode(Data(#"{"version":1,"templates":"x"}"#.utf8)).templates.isEmpty)
    }

    @Test func roundTripKeepsRecurrenceAndEverything() throws {
        var t = ItemTemplates()
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, byDay: [.monday, .friday])
        _ = try t.add(name: "1:1", from: snap(notes: "agenda", url: "https://z", recurrence: rule))
        _ = try t.add(name: "Pay", from: snap(.reminder, duration: nil, priority: .medium, destination: nil))
        let back = ItemTemplates.decode(t.encoded())
        #expect(back == t)
        #expect(back.templates[0].recurrence == rule)
        #expect(String(decoding: t.encoded(), as: UTF8.self).contains(#""version":1"#))
    }

    @Test func formValuesEndFromDuration() throws {
        var t = ItemTemplates()
        let made = try t.add(name: "A", from: snap(duration: 90, notes: "n", url: "https://u",
                                                  recurrence: RecurrenceRule(frequency: .daily)))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let v = TemplateFormValues(made, start: start, offeredDestinationIDs: ["cal-1", "cal-2"])
        #expect(v.title == "Dentist" && v.notes == "n" && v.url == "https://u")
        #expect(v.end == start.addingTimeInterval(5400))
        #expect(v.recurrence == RecurrenceRule(frequency: .daily))
        #expect(v.allDay == false)
        #expect(v.destinationID == "cal-1")
    }

    @Test func formValuesDefaultHourWhenNoDurationOrAllDay() throws {
        var t = ItemTemplates()
        let timed = try t.add(name: "A", from: snap(duration: nil))
        let allDay = try t.add(name: "B", from: snap(duration: nil, allDay: true))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(TemplateFormValues(timed, start: start, offeredDestinationIDs: []).end == start.addingTimeInterval(3600))
        let v = TemplateFormValues(allDay, start: start, offeredDestinationIDs: [])
        #expect(v.allDay && v.end == start.addingTimeInterval(3600))
    }

    @Test func destinationFallsBackWhenGone() throws {
        var t = ItemTemplates()
        let made = try t.add(name: "A", from: snap(destination: "gone"))
        #expect(TemplateFormValues(made, start: Date(), offeredDestinationIDs: ["cal-1"]).destinationID == nil)
        let none = try t.add(name: "B", from: snap(destination: nil))
        #expect(TemplateFormValues(none, start: Date(), offeredDestinationIDs: ["cal-1"]).destinationID == nil)
    }

    @Test func templatesCarryNoDates() throws {
        var t = ItemTemplates()
        _ = try t.add(name: "A", from: snap(recurrence: RecurrenceRule(frequency: .weekly, until: Date())))
        let json = String(decoding: t.encoded(), as: UTF8.self)
        #expect(!json.contains("until") && !json.contains("count"))
    }
}

@Suite struct TemplateDurationTests {
    @Test func minutesBetweenStartAndEnd() {
        let s = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(TemplateSnapshot.durationMinutes(start: s, end: s.addingTimeInterval(90 * 60), allDay: false) == 90)
    }
    @Test func allDayHasNoDuration() {
        let s = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(TemplateSnapshot.durationMinutes(start: s, end: s.addingTimeInterval(3600), allDay: true) == nil)
    }
    @Test func endBeforeStartClampsToZero() {
        let s = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(TemplateSnapshot.durationMinutes(start: s, end: s.addingTimeInterval(-600), allDay: false) == 0)
    }
}
