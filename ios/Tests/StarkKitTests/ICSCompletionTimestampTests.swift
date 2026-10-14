import Testing
import Foundation
@testable import StarkKit

@Suite("ICS completion timestamps")
struct ICSCompletionTimestampTests {
    private func stamp(_ iso: String, h: Int, m: Int) -> Date {
        let c = DateMath.components(iso)
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: c.year, month: c.month0 + 1, day: c.day, hour: h, minute: m))!
    }

    @Test("a completed reminder's completedAt and seriesID round-trip")
    func reminderRoundTrip() {
        let r = Reminder(id: "c1", title: "Walk", dueDate: stamp("2026-10-07", h: 9, m: 0), isCompleted: true,
                         completedDate: stamp("2026-10-07", h: 9, m: 0),
                         completedAt: stamp("2026-10-14", h: 10, m: 59), seriesID: "master")
        let text = ICSSerializer.serialize(events: [], reminders: [r])
        let parsed = ICSParser.parse(text).reminders
        #expect(parsed == [r])
    }

    @Test("an attended mark's recordedAt round-trips, timed and all-day")
    func outcomeRoundTrip() {
        let timed = Event(id: "e1", title: "Gym", start: stamp("2026-10-13", h: 7, m: 0),
                          outcomes: [EventOutcomeRecord(date: stamp("2026-10-13", h: 7, m: 0), outcome: .attended,
                                                        recordedAt: stamp("2026-10-14", h: 8, m: 5))])
        let allDay = Event(id: "e2", title: "Trip", start: stamp("2026-10-13", h: 0, m: 0), isAllDay: true,
                           outcomes: [EventOutcomeRecord(date: stamp("2026-10-13", h: 0, m: 0), outcome: .skipped,
                                                         recordedAt: stamp("2026-10-14", h: 8, m: 5))])
        let parsed = ICSParser.parse(ICSSerializer.serialize(events: [timed, allDay], reminders: [])).events
        #expect(parsed == [timed, allDay])
    }

    @Test("files without the new properties parse with nil timestamps and re-serialize identically")
    func oldFilesUnchanged() {
        let r = Reminder(id: "c2", title: "Old", dueDate: stamp("2026-09-01", h: 9, m: 0), isCompleted: true,
                         completedDate: stamp("2026-09-01", h: 9, m: 0))
        let e = Event(id: "e3", title: "Old event", start: stamp("2026-09-01", h: 9, m: 0),
                      outcomes: [EventOutcomeRecord(date: stamp("2026-09-01", h: 9, m: 0), outcome: .attended)])
        let text = ICSSerializer.serialize(events: [e], reminders: [r])
        #expect(!text.contains("X-STARK-COMPLETED-AT"))
        #expect(!text.contains("X-RECORDED"))
        let parsed = ICSParser.parse(text)
        #expect(parsed.reminders[0].completedAt == nil)
        #expect(parsed.reminders[0].seriesID == nil)
        #expect(parsed.events[0].outcomes[0].recordedAt == nil)
        #expect(ICSSerializer.serialize(events: parsed.events, reminders: parsed.reminders) == text)
    }
}
