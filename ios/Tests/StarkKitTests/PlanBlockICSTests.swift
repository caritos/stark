import Testing
import Foundation
@testable import StarkKit

@Suite struct PlanBlockICSTests {
    private let reminder = Reminder(id: "r1", title: "Write", dueDate: Date(timeIntervalSince1970: 1_800_000_000))

    private func block() -> PlanBlock {
        PlanBlock(id: "p1", reminderID: "r1",
                  occurrence: Date(timeIntervalSince1970: 1_800_000_000),
                  start: Date(timeIntervalSince1970: 1_800_003_600), minutes: 45)
    }

    @Test func roundTrip() {
        let b = block()
        let text = ICSSerializer.serialize(events: [], reminders: [reminder], plans: [b])
        let parsed = ICSParser.parse(text)
        #expect(parsed.plans == [b])
        #expect(parsed.reminders.count == 1)
        #expect(parsed.warnings.isEmpty)
        #expect(b.end == b.start.addingTimeInterval(45 * 60))
    }

    @Test func noPlansIsByteIdentical() {
        let a = ICSSerializer.serialize(events: [], reminders: [reminder])
        let b = ICSSerializer.serialize(events: [], reminders: [reminder], plans: [])
        #expect(a == b)
        #expect(!a.contains("X-STARK-PLAN"))
    }

    @Test func malformedPlanWarns() {
        let text = [
            "BEGIN:VCALENDAR",
            "BEGIN:X-STARK-PLAN",
            "UID:p1",
            "X-STARK-PLAN-OCCURRENCE:20270115T090000",
            "DTSTART:20270115T100000",
            "X-STARK-PLAN-MINUTES:30",
            "END:X-STARK-PLAN",
            "END:VCALENDAR",
        ].joined(separator: "\r\n") + "\r\n"
        let parsed = ICSParser.parse(text)
        #expect(parsed.plans.isEmpty)
        #expect(parsed.warnings.count == 1)
        #expect(parsed.warnings.first?.contains("X-STARK-PLAN") == true)
    }

    @Test func unknownComponentIgnored() {
        let text = [
            "BEGIN:VCALENDAR",
            "BEGIN:X-OTHER",
            "UID:zzz",
            "END:X-OTHER",
            "BEGIN:VTODO",
            "UID:r1",
            "SUMMARY:Write",
            "END:VTODO",
            "END:VCALENDAR",
        ].joined(separator: "\r\n") + "\r\n"
        let parsed = ICSParser.parse(text)
        #expect(parsed.reminders.count == 1)
        #expect(parsed.plans.isEmpty)
        #expect(parsed.warnings.isEmpty)
    }
}
