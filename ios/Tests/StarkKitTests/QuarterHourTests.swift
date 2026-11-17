// ios/Tests/StarkKitTests/QuarterHourTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("QuarterHour")
struct QuarterHourTests {
    /// The process's own zone (run under TZ=Pacific/Honolulu, America/New_York, Asia/Tokyo).
    private let local = Calendar.current

    private func newYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
                    _ second: Int = 0, nanosecond: Int = 0, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? local
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour,
                                                  minute: minute, second: second,
                                                  nanosecond: nanosecond))!
    }

    @Test("a date exactly on a quarter hour is returned as is")
    func onQuarterReturnsSame() {
        let date = at(2026, 11, 17, 10, 15)
        #expect(QuarterHour.nextAfter(date, calendar: local) == date)
    }

    @Test("anything after a quarter hour rounds up to the next one")
    func justAfterRoundsUp() {
        #expect(QuarterHour.nextAfter(at(2026, 11, 17, 10, 15, 1), calendar: local) == at(2026, 11, 17, 10, 30))
        #expect(QuarterHour.nextAfter(at(2026, 11, 17, 10, 11), calendar: local) == at(2026, 11, 17, 10, 15))
        #expect(QuarterHour.nextAfter(at(2026, 11, 17, 10, 46), calendar: local) == at(2026, 11, 17, 11, 0))
        #expect(QuarterHour.nextAfter(at(2026, 11, 17, 10, 0, 30), calendar: local) == at(2026, 11, 17, 10, 15))
    }

    @Test("late evening rolls over to midnight of the next day")
    func lateEveningRollsToNextDay() {
        #expect(QuarterHour.nextAfter(at(2026, 12, 31, 23, 50), calendar: local) == at(2027, 1, 1, 0, 0))
        #expect(QuarterHour.nextAfter(at(2026, 11, 17, 23, 45), calendar: local) == at(2026, 11, 17, 23, 45))
    }

    @Test("spring forward: 01:50 EST is followed by 03:00 EDT, ten minutes later")
    func dstSpringForwardGapHour() {
        let ny = newYork()
        let before = at(2026, 3, 8, 1, 50, calendar: ny)
        let next = QuarterHour.nextAfter(before, calendar: ny)
        #expect(next.timeIntervalSince(before) == 600)
        let parts = ny.dateComponents([.hour, .minute], from: next)
        #expect(parts.hour == 3)
        #expect(parts.minute == 0)
    }

    @Test("fall back: 01:50 EDT is followed by 01:00 EST, ten minutes later")
    func dstFallBackRepeatedHour() {
        let ny = newYork()
        let firstOneFifty = at(2026, 11, 1, 1, 50, calendar: ny)
        #expect(ny.timeZone.isDaylightSavingTime(for: firstOneFifty))
        let next = QuarterHour.nextAfter(firstOneFifty, calendar: ny)
        #expect(next.timeIntervalSince(firstOneFifty) == 600)
        let parts = ny.dateComponents([.hour, .minute], from: next)
        #expect(parts.hour == 1)
        #expect(parts.minute == 0)
        #expect(!ny.timeZone.isDaylightSavingTime(for: next))
        #expect(QuarterHour.isOnQuarter(next, calendar: ny))
    }

    @Test("isOnQuarter is true only for :00, :15, :30 and :45 with no seconds")
    func isOnQuarterTrueAndFalse() {
        for minute in [0, 15, 30, 45] {
            #expect(QuarterHour.isOnQuarter(at(2026, 11, 17, 9, minute), calendar: local))
        }
        for minute in [1, 7, 14, 16, 29, 44, 59] {
            #expect(!QuarterHour.isOnQuarter(at(2026, 11, 17, 9, minute), calendar: local))
        }
        #expect(!QuarterHour.isOnQuarter(at(2026, 11, 17, 9, 15, 1), calendar: local))
        #expect(!QuarterHour.isOnQuarter(at(2026, 11, 17, 9, 15, 0, nanosecond: 500_000_000), calendar: local))
    }

    @Test("seconds and nanoseconds are dropped from the result")
    func ignoresSecondsAndNanoseconds() {
        let date = at(2026, 11, 17, 10, 7, 42, nanosecond: 123_000_000)
        let next = QuarterHour.nextAfter(date, calendar: local)
        #expect(next == at(2026, 11, 17, 10, 15))
        let parts = local.dateComponents([.second, .nanosecond], from: next)
        #expect(parts.second == 0)
        #expect((parts.nanosecond ?? 0) < 1000)
        // A quarter hour plus a fraction of a second is past it.
        #expect(QuarterHour.nextAfter(at(2026, 11, 17, 10, 15, 0, nanosecond: 1_000_000), calendar: local)
                == at(2026, 11, 17, 10, 30))
    }
}
