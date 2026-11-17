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

    // MARK: floored / keepingUntouchedTime (what the picker shows, and a date-only change)

    @Test("floored is the quarter hour at or before the date, seconds dropped")
    func flooredIsTheQuarterAtOrBefore() {
        #expect(QuarterHour.floored(at(2026, 11, 17, 10, 7, 42), calendar: local) == at(2026, 11, 17, 10, 0))
        #expect(QuarterHour.floored(at(2026, 11, 17, 10, 13), calendar: local) == at(2026, 11, 17, 10, 0))
        #expect(QuarterHour.floored(at(2026, 11, 17, 10, 59), calendar: local) == at(2026, 11, 17, 10, 45))
        #expect(QuarterHour.floored(at(2026, 11, 17, 10, 30), calendar: local) == at(2026, 11, 17, 10, 30))
    }

    @Test("a pick that only changed the day keeps the previous odd time on the new day")
    func dateOnlyChangeKeepsOddTime() {
        // The picker showed 10:00 for 10:07; the owner picked the 18th; the picker reports 18th 10:00.
        let previous = at(2026, 11, 17, 10, 7, 31)
        let picked = at(2026, 11, 18, 10, 0)
        #expect(QuarterHour.keepingUntouchedTime(picked: picked, previous: previous, calendar: local)
                == at(2026, 11, 18, 10, 7, 31))
    }

    @Test("a pick that changed the time is taken as is")
    func timeChangeIsTaken() {
        let previous = at(2026, 11, 17, 10, 7)
        #expect(QuarterHour.keepingUntouchedTime(picked: at(2026, 11, 17, 10, 15), previous: previous,
                                                 calendar: local) == at(2026, 11, 17, 10, 15))
        #expect(QuarterHour.keepingUntouchedTime(picked: at(2026, 11, 18, 11, 0), previous: previous,
                                                 calendar: local) == at(2026, 11, 18, 11, 0))
        #expect(QuarterHour.keepingUntouchedTime(picked: at(2026, 11, 17, 9, 45), previous: previous,
                                                 calendar: local) == at(2026, 11, 17, 9, 45))
    }

    @Test("a previous value already on a quarter hour gives the pick unchanged")
    func onQuarterPreviousGivesPick() {
        let previous = at(2026, 11, 17, 10, 0)
        let picked = at(2026, 11, 19, 10, 0)
        #expect(QuarterHour.keepingUntouchedTime(picked: picked, previous: previous, calendar: local) == picked)
    }

    @Test("a date-only change across the fall-back day keeps the wall-clock time")
    func dateOnlyChangeAcrossDST() {
        let ny = newYork()
        let previous = at(2026, 10, 31, 10, 7, calendar: ny)
        let picked = at(2026, 11, 2, 10, 0, calendar: ny)
        let kept = QuarterHour.keepingUntouchedTime(picked: picked, previous: previous, calendar: ny)
        #expect(kept == at(2026, 11, 2, 10, 7, calendar: ny))
    }

    // MARK: review fixes: independent of how UIKit rounds the shown time

    @Test("a day change restores the odd time whether UIKit reports it floored, nearest or exact")
    func dayChangeRestoresWhateverTheRounding() {
        let previous = at(2026, 11, 17, 10, 13)
        for reported in [at(2026, 11, 18, 10, 0), at(2026, 11, 18, 10, 15), at(2026, 11, 18, 10, 13)] {
            #expect(QuarterHour.keepingUntouchedTime(picked: reported, previous: previous, calendar: local)
                    == at(2026, 11, 18, 10, 13))
        }
    }

    @Test("on the same day the pick always wins, even the rounded-down or nearest time")
    func sameDayPickAlwaysWins() {
        let previous = at(2026, 11, 17, 10, 13)
        #expect(QuarterHour.keepingUntouchedTime(picked: at(2026, 11, 17, 10, 15), previous: previous,
                                                 calendar: local) == at(2026, 11, 17, 10, 15))
        #expect(QuarterHour.keepingUntouchedTime(picked: at(2026, 11, 17, 10, 0), previous: previous,
                                                 calendar: local) == at(2026, 11, 17, 10, 0))
    }

    @Test("a day change with the hour moved by two hours keeps the pick")
    func dayChangeAndHourMovedKeepsPick() {
        let previous = at(2026, 11, 17, 10, 13)
        let picked = at(2026, 11, 18, 12, 0)
        #expect(QuarterHour.keepingUntouchedTime(picked: picked, previous: previous, calendar: local) == picked)
    }

    @Test("23:50 to the next day at 00:05 is a real change, not a restore to the old day")
    func acrossMidnightKeepsPick() {
        let previous = at(2026, 11, 17, 23, 50)
        let picked = at(2026, 11, 18, 0, 5)
        #expect(QuarterHour.keepingUntouchedTime(picked: picked, previous: previous, calendar: local) == picked)
        // The day before, the same: the pick stands.
        let earlier = at(2026, 11, 16, 23, 45)
        #expect(QuarterHour.keepingUntouchedTime(picked: earlier, previous: at(2026, 11, 17, 0, 5),
                                                 calendar: local) == earlier)
    }

    @Test("day change, then the hour away and back: the later same-day picks are taken")
    func hourRoundTripIsTaken() {
        var value = at(2026, 11, 17, 10, 13)
        value = QuarterHour.keepingUntouchedTime(picked: at(2026, 11, 18, 10, 0), previous: value, calendar: local)
        #expect(value == at(2026, 11, 18, 10, 13))
        value = QuarterHour.keepingUntouchedTime(picked: at(2026, 11, 18, 11, 0), previous: value, calendar: local)
        #expect(value == at(2026, 11, 18, 11, 0))
        value = QuarterHour.keepingUntouchedTime(picked: at(2026, 11, 18, 10, 0), previous: value, calendar: local)
        #expect(value == at(2026, 11, 18, 10, 0))
    }

    @Test("fall back: a day change onto 01:00 EDT or 01:00 EST lands 7 minutes after the pick, never an hour off")
    func fallBackRestoreStaysNextToThePick() {
        let ny = newYork()
        let previous = at(2026, 10, 31, 1, 7, calendar: ny)
        let firstOne = at(2026, 11, 1, 1, 0, calendar: ny)
        #expect(ny.timeZone.isDaylightSavingTime(for: firstOne))
        let secondOne = firstOne.addingTimeInterval(3600)
        #expect(ny.component(.hour, from: secondOne) == 1)
        for picked in [firstOne, secondOne] {
            let kept = QuarterHour.keepingUntouchedTime(picked: picked, previous: previous, calendar: ny)
            #expect(kept.timeIntervalSince(picked) == 7 * 60)
            #expect(ny.dateComponents([.hour, .minute], from: kept) == DateComponents(hour: 1, minute: 7))
        }
    }

    @Test("spring forward: an odd time inside the missing hour never moves the item an hour")
    func springForwardStaysNextToThePick() {
        let ny = newYork()
        // 02:07 does not exist on 2026-03-08; whatever UIKit reports, the item stays next to the pick.
        let previous = at(2026, 3, 7, 2, 7, calendar: ny)
        let reported = at(2026, 3, 8, 3, 0, calendar: ny) // 02:00 does not exist either
        let kept = QuarterHour.keepingUntouchedTime(picked: reported, previous: previous, calendar: ny)
        #expect(abs(kept.timeIntervalSince(reported)) <= 15 * 60)
        // An odd time on the DST day itself, moved to the next day, keeps its wall-clock time.
        let onDSTDay = at(2026, 3, 8, 3, 7, calendar: ny)
        let nextDay = QuarterHour.keepingUntouchedTime(picked: at(2026, 3, 9, 3, 0, calendar: ny),
                                                       previous: onDSTDay, calendar: ny)
        #expect(nextDay == at(2026, 3, 9, 3, 7, calendar: ny))
    }

    @Test("floored on the DST days stays on the wall-clock quarter")
    func flooredOnDSTDays() {
        let ny = newYork()
        #expect(QuarterHour.floored(at(2026, 3, 8, 3, 7, calendar: ny), calendar: ny)
                == at(2026, 3, 8, 3, 0, calendar: ny))
        let firstOneSeven = at(2026, 11, 1, 1, 7, calendar: ny)
        #expect(QuarterHour.floored(firstOneSeven, calendar: ny).timeIntervalSince(firstOneSeven) == -7 * 60)
        let secondOneSeven = firstOneSeven.addingTimeInterval(3600)
        #expect(QuarterHour.floored(secondOneSeven, calendar: ny).timeIntervalSince(secondOneSeven) == -7 * 60)
    }

    // MARK: savedTimeCaption

    @Test("the caption names the saved odd time in the locale's format, nil on a quarter hour")
    func savedTimeCaption() {
        var gb = Calendar(identifier: .gregorian)
        gb.timeZone = TimeZone(identifier: "Europe/London")!
        let odd = gb.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10, minute: 7))!
        #expect(QuarterHour.savedTimeCaption(for: odd, calendar: gb, locale: Locale(identifier: "en_GB"))
                == "Saved time 10:07")
        let us = QuarterHour.savedTimeCaption(for: odd, calendar: gb, locale: Locale(identifier: "en_US"))
        #expect(us?.hasPrefix("Saved time 10:07") == true)
        #expect(us?.contains("AM") == true)
        let quarter = gb.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10, minute: 15))!
        #expect(QuarterHour.savedTimeCaption(for: quarter, calendar: gb, locale: Locale(identifier: "en_GB")) == nil)
        // Seconds alone do not change what the picker shows: no caption.
        let withSeconds = quarter.addingTimeInterval(31)
        #expect(QuarterHour.savedTimeCaption(for: withSeconds, calendar: gb,
                                             locale: Locale(identifier: "en_GB")) == nil)
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
