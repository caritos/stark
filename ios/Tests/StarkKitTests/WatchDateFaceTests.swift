import Foundation
import Testing
@testable import StarkKit

@Suite("Watch date face")
struct WatchDateFaceTests {
    private func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    private func date(_ c: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test("a week reads Sun, Mon, Tues, Wed, Thurs, Fri, Sat with the day of the month")
    func week() {
        let c = calendar("America/New_York")
        let faces = (22...28).map { WatchDateFace(date: date(c, 2026, 11, $0, 12), calendar: c) }
        #expect(faces.map(\.weekday) == ["Sun", "Mon", "Tues", "Wed", "Thurs", "Fri", "Sat"])
        #expect(faces.map(\.day) == ["22", "23", "24", "25", "26", "27", "28"])
        #expect(faces[4].accessibilityLabel == "Thursday 26")
    }

    @Test("the day is the one in the calendar's time zone")
    func zone() {
        let tokyo = calendar("Asia/Tokyo")
        let instant = date(tokyo, 2026, 12, 1, 1)
        #expect(WatchDateFace(date: instant, calendar: tokyo).day == "1")
        #expect(WatchDateFace(date: instant, calendar: calendar("Pacific/Honolulu")).day == "30")
    }

    @Test("the timeline gets each of the next seven midnights, in order and once, across a DST change")
    func midnights() {
        let c = calendar("America/New_York")
        let now = date(c, 2026, 10, 30, 22)
        let first = date(c, 2026, 10, 31)
        let dates = WatchDateFace.timelineDates([now, first, date(c, 2026, 10, 31, 9)], now: now, calendar: c)
        let expected = [now, first, date(c, 2026, 10, 31, 9)]
            + (1...7).dropFirst().map { c.date(byAdding: .day, value: $0 - 1, to: first)! }
        #expect(dates == expected)
        #expect(dates.dropFirst(3).allSatisfy { c.component(.hour, from: $0) == 0 })
    }
}
