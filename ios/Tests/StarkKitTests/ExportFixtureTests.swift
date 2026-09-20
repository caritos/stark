// ios/Tests/StarkKitTests/ExportFixtureTests.swift
//
// Parses the golden fixtures produced for the todo.txt migration with the REAL ICSParser.
// The TypeScript converter (shared/commands/exportIcs.ts) must reproduce these files byte for
// byte; this test proves the files mean what the migration spec says they mean to the app.
import Testing
import Foundation
@testable import StarkKit

private let expectedDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // StarkKitTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // ios
    .deletingLastPathComponent()   // repo root
    .appendingPathComponent("shared/tests/fixtures/ics/expected")

private func load(_ name: String) throws -> ICSParseResult {
    let text = try String(contentsOf: expectedDir.appendingPathComponent(name), encoding: .utf8)
    return ICSParser.parse(text)
}

private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func iso(_ date: Date) -> String { DateMath.isoDate(from: date) }

@Suite("Migration export fixtures")
struct ExportFixtureTests {
    @Test("fixtures are CRLF, as the Swift serializer writes them")
    func fixturesAreCRLF() throws {
        let text = try String(contentsOf: expectedDir.appendingPathComponent("2026-09.ics"), encoding: .utf8)
        #expect(text.contains("\r\n"))
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
    }

    @Test("recurring.ics: every recurrence form parses to the intended rule")
    func recurring() throws {
        let r = try load("recurring.ics")
        #expect(r.warnings.isEmpty)
        #expect(r.events.map(\.id) == ["L04", "L05", "L06", "L07"])
        #expect(r.reminders.map(\.id) == ["L08", "L10"])

        let standup = r.events[0]
        #expect(standup.title == "Standup")
        #expect(standup.start == local(2026, 9, 21, 9, 0))
        #expect(standup.end == local(2026, 9, 21, 9, 15))
        #expect(standup.recurrence?.frequency == .weekly)
        #expect(standup.recurrence?.byDay == [.monday, .wednesday, .friday])
        #expect(standup.recurrence?.until.map(iso) == "2026-12-18")
        #expect(standup.exceptionDates.map(iso) == ["2026-09-23", "2026-09-25"])

        #expect(r.events[1].recurrence?.byPositionalDay == [PositionalDay(position: .first, dayType: .weekday(.wednesday))])
        #expect(r.events[2].recurrence?.byPositionalDay == [PositionalDay(position: .last, dayType: .anyDay)])

        let birthday = r.events[3]
        #expect(birthday.title == "Mom's birthday %birthday")
        #expect(birthday.isAllDay)
        #expect(birthday.start == local(1975, 5, 15))
        #expect(birthday.recurrence?.frequency == .yearly)

        let rent = r.reminders[0]
        #expect(rent.dueDate == local(2026, 10, 1))
        #expect(rent.recurrence?.frequency == .monthly)
        #expect(!rent.isCompleted)

        let water = r.reminders[1]
        #expect(water.dueDate == local(2026, 9, 27, 7, 0))
        #expect(water.recurrence?.frequency == .weekly)
        #expect(water.recurrence?.interval == 2)
    }

    @Test("2026-08.ics: a completed reminder due on its own start date")
    func august() throws {
        let r = try load("2026-08.ics")
        #expect(r.warnings.isEmpty)
        #expect(r.events.isEmpty)
        #expect(r.reminders.count == 1)
        #expect(r.reminders[0].title == "Renew passport")
        #expect(r.reminders[0].isCompleted)
        #expect(r.reminders[0].dueDate == local(2026, 8, 25))
        #expect(r.reminders[0].completedDate == local(2026, 8, 30))
    }

    @Test("2026-09.ics: escaping, notes, location, priority, undated and completed reminders")
    func september() throws {
        let r = try load("2026-09.ics")
        #expect(r.warnings.isEmpty)
        #expect(r.events.map(\.id) == ["L01", "L13", "L17"])
        #expect(r.reminders.map(\.id) == ["L09", "L11", "L15", "L16"])

        let dentist = r.events[0]
        #expect(dentist.start == local(2026, 9, 22, 14, 30))
        #expect(dentist.end == local(2026, 9, 22, 15, 30))
        #expect(dentist.notes == "Bring forms, insurance card")
        #expect(dentist.location == "123 Main St")
        #expect(dentist.recurrence == nil)

        #expect(r.events[2].title == "Lunch; with, commas \\ backslash 🍜")

        let call = r.reminders[0]
        #expect(call.title == "Call insurance ~sam %phone bus:16:00")
        #expect(call.dueDate == local(2026, 9, 25, 10, 0))
        #expect(call.priority == 1)

        let trash = r.reminders[1]
        #expect(trash.isCompleted)
        #expect(trash.dueDate == local(2026, 9, 18))
        #expect(trash.completedDate == local(2026, 9, 18))

        #expect(r.reminders[2].title == "Buy milk")
        #expect(r.reminders[2].dueDate == nil)
        #expect(r.reminders[3].title == "Meet Sam at 9:00")
        #expect(r.reminders[3].dueDate == local(2026, 9, 24, 9, 0))
    }

    @Test("2026-10.ics: all-day, multi-day, and the unsupported fifth-Friday rule as a one-off")
    func october() throws {
        let r = try load("2026-10.ics")
        #expect(r.warnings.isEmpty)
        #expect(r.events.map(\.id) == ["L02", "L03", "L14"])
        #expect(r.events[0].isAllDay)
        #expect(r.events[0].start == local(2026, 10, 12))
        #expect(r.events[1].isAllDay)
        #expect(r.events[1].end == local(2026, 10, 8))
        #expect(r.events[2].recurrence == nil)
        #expect(r.events[2].start == local(2026, 10, 30, 18, 0))
    }
}
