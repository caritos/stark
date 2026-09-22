// ios/Tests/StarkKitTests/RepeatEndTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("RepeatEnd")
struct RepeatEndTests {
    private let cal = Calendar(identifier: .gregorian)

    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }
    private func midnight(_ iso: String) -> Date { cal.startOfDay(for: d(iso)) }

    @Test("reads the end off a rule: count, until, or never")
    func reading() {
        #expect(RepeatEnd(rule: nil) == .never)
        #expect(RepeatEnd(rule: RecurrenceRule(frequency: .weekly)) == .never)
        #expect(RepeatEnd(rule: RecurrenceRule(frequency: .weekly, count: 10)) == .afterCount(10))
        #expect(RepeatEnd(rule: RecurrenceRule(frequency: .weekly, until: midnight("2026-12-31"))) == .onDate(midnight("2026-12-31")))
    }

    @Test("a nonsensical count reads as never")
    func nonsenseCount() {
        #expect(RepeatEnd(rule: RecurrenceRule(frequency: .weekly, count: 0)) == .never)
        #expect(RepeatEnd(rule: RecurrenceRule(frequency: .weekly, count: -3)) == .never)
    }

    @Test("a foreign rule carrying both count and until reads as the date, and applying drops the count")
    func foreignBothEnds() throws {
        // An RRULE may not carry both COUNT and UNTIL, so when a foreign file has both the date wins.
        let rule = RecurrenceRule(frequency: .weekly, count: 3, until: midnight("2026-12-31"))
        #expect(RepeatEnd(rule: rule) == .onDate(midnight("2026-12-31")))
        let applied = try #require(RepeatEnd(rule: rule).applied(to: rule.withoutEnd))
        #expect(applied.until == midnight("2026-12-31"))
        #expect(applied.count == nil)
    }

    @Test("a foreign until with a time of day snaps to the start of its day, and the serialized rule is unchanged")
    func foreignUntilWithTime() throws {
        let lateUntil = try #require(cal.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 59)))
        let original = RecurrenceRule(frequency: .weekly, until: lateUntil)
        let applied = try #require(RepeatEnd(rule: original).applied(to: original.withoutEnd))
        #expect(applied.until == midnight("2026-12-31"))
        // The codec writes UNTIL date-only, so snapping does not change what is saved.
        #expect(RRuleCodec.encode(applied) == RRuleCodec.encode(original))
    }

    @Test("a foreign count of 0 reads as never and applying writes no end")
    func foreignZeroCount() throws {
        // Documents that a nonsense foreign count becomes unbounded on save.
        let rule = RecurrenceRule(frequency: .weekly, count: 0)
        #expect(RepeatEnd(rule: rule) == .never)
        let applied = try #require(RepeatEnd(rule: rule).applied(to: rule.withoutEnd))
        #expect(applied.count == nil)
        #expect(applied.until == nil)
    }

    @Test("applying replaces any earlier end and keeps every other part of the rule")
    func applying() throws {
        let base = RecurrenceRule(frequency: .weekly, interval: 2, byDay: [.monday])

        let onDate = try #require(RepeatEnd.onDate(d("2026-12-31")).applied(to: base))
        #expect(onDate.until == midnight("2026-12-31"))
        #expect(onDate.count == nil)
        #expect(onDate.frequency == .weekly)
        #expect(onDate.interval == 2)
        #expect(onDate.byDay == [.monday])

        let withUntil = RecurrenceRule(frequency: .weekly, until: midnight("2026-10-01"))
        let counted = try #require(RepeatEnd.afterCount(5).applied(to: withUntil))
        #expect(counted.count == 5)
        #expect(counted.until == nil)

        let withCount = RecurrenceRule(frequency: .weekly, count: 8)
        let never = try #require(RepeatEnd.never.applied(to: withCount))
        #expect(never.count == nil)
        #expect(never.until == nil)
    }

    @Test("a count below 1 is applied as 1, and applying to no rule gives no rule")
    func clampAndNil() throws {
        let base = RecurrenceRule(frequency: .daily)
        #expect(try #require(RepeatEnd.afterCount(0).applied(to: base)).count == 1)
        #expect(RepeatEnd.never.applied(to: nil) == nil)
        #expect(RepeatEnd.onDate(d("2026-12-31")).applied(to: nil) == nil)
        #expect(RepeatEnd.afterCount(3).applied(to: nil) == nil)
    }

    @Test("opening a rule and applying its own end to its stripped self is a no-op")
    func unchangedRoundTrip() {
        let rules: [RecurrenceRule?] = [
            nil,
            RecurrenceRule(frequency: .weekly),
            RecurrenceRule(frequency: .weekly, interval: 2, count: 10),
            RecurrenceRule(frequency: .daily, until: midnight("2026-12-31")),
            RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .fourth, dayType: .weekday(.friday))], until: midnight("2027-03-01")),
        ]
        for rule in rules {
            let end = RepeatEnd(rule: rule)
            #expect(end.applied(to: rule?.withoutEnd) == rule)
        }
    }

    @Test("withoutEnd clears count and until only")
    func withoutEnd() {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, byDay: [.monday], count: 4)
        let stripped = rule.withoutEnd
        #expect(stripped.count == nil)
        #expect(stripped.until == nil)
        #expect(stripped.frequency == .weekly)
        #expect(stripped.interval == 2)
        #expect(stripped.byDay == [.monday])
    }

    @Test("an end date before the start's day moves up to the start's day; later dates and other ends are untouched")
    func clamping() {
        let start = d("2026-09-20")
        #expect(RepeatEnd.onDate(midnight("2026-09-01")).clamped(toStartOn: start) == .onDate(midnight("2026-09-20")))
        #expect(RepeatEnd.onDate(midnight("2026-09-20")).clamped(toStartOn: start) == .onDate(midnight("2026-09-20")))
        #expect(RepeatEnd.onDate(midnight("2026-12-31")).clamped(toStartOn: start) == .onDate(midnight("2026-12-31")))
        #expect(RepeatEnd.never.clamped(toStartOn: start) == .never)
        #expect(RepeatEnd.afterCount(3).clamped(toStartOn: start) == .afterCount(3))
    }

    @Test("summary strings")
    func summaries() {
        #expect(RepeatEnd.never.summary == "Never")
        #expect(RepeatEnd.afterCount(1).summary == "1 time")
        #expect(RepeatEnd.afterCount(10).summary == "10 times")
        #expect(RepeatEnd.onDate(midnight("2026-12-31")).summary == "Dec 31, 2026")
    }
}
