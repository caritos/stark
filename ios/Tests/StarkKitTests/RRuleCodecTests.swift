// ios/Tests/StarkKitTests/RRuleCodecTests.swift
import Testing
@testable import StarkKit

@Suite("RRuleCodec")
struct RRuleCodecTests {
    @Test("encodes and decodes multiple days-of-month")
    func multipleMonthDays() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [1, 15])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYMONTHDAY=1,15")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes multiple months")
    func multipleMonths() {
        let rule = RecurrenceRule(frequency: .yearly, byMonth: [.march, .september])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=YEARLY;BYMONTH=3,9")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("an empty BYMONTHDAY value decodes to nil, not an empty array")
    func emptyByMonthDayDecodesToNil() {
        let decoded = RRuleCodec.decode("FREQ=MONTHLY;BYMONTHDAY=")
        #expect(decoded?.byMonthDay == nil)
    }

    @Test("a BYMONTHDAY value with only unparseable tokens decodes to nil, not an empty array")
    func unparseableByMonthDayDecodesToNil() {
        let decoded = RRuleCodec.decode("FREQ=MONTHLY;BYMONTHDAY=abc")
        #expect(decoded?.byMonthDay == nil)
    }

    @Test("an empty BYMONTH value decodes to nil, not an empty array")
    func emptyByMonthDecodesToNil() {
        let decoded = RRuleCodec.decode("FREQ=YEARLY;BYMONTH=")
        #expect(decoded?.byMonth == nil)
    }

    @Test("encodes and decodes a specific-weekday positional day as ordinal BYDAY")
    func positionalSpecificWeekday() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .second, dayType: .weekday(.tuesday))])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYDAY=2TU")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes multiple specific-weekday positional days together")
    func positionalMultipleSpecificWeekdays() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [
            PositionalDay(position: .first, dayType: .weekday(.monday)),
            PositionalDay(position: .last, dayType: .weekday(.friday))
        ])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYDAY=1MO,-1FR")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes a generic weekday-only positional day via BYSETPOS")
    func positionalWeekdayOnly() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .weekdayOnly)])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes a generic weekend-day positional day via BYSETPOS")
    func positionalWeekendDay() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .first, dayType: .weekendDay)])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYDAY=SA,SU;BYSETPOS=1")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("encodes and decodes an anyDay positional day as BYMONTHDAY")
    func positionalAnyDay() {
        // .anyDay is only ever paired with .last (see OnWeekPickerView in Task 9) - any other
        // position would encode as a plain positive BYMONTHDAY, indistinguishable on decode from
        // a non-positional byMonthDay rule. .last's negative encoding is what makes it unambiguous.
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .anyDay)])
        let encoded = RRuleCodec.encode(rule)
        #expect(encoded == "FREQ=MONTHLY;BYMONTHDAY=-1")
        #expect(RRuleCodec.decode(encoded) == rule)
    }

    @Test("a malformed rule with both weekly byDay and a leftover byPositionalDay never encodes two BYDAY lines")
    func neverEncodesDoubleBYDAY() {
        // Reproduces the exact malformed state a stale unit-switch could leave behind
        // (CustomRepeatView.commit() previously passed byPositionalDay through unconditionally
        // regardless of unit) - constructed directly here via the StarkKit API, since encode()
        // must be safe against ANY RecurrenceRule value, not just ones the picker's own gating
        // would produce.
        let malformed = RecurrenceRule(
            frequency: .weekly,
            byDay: [.monday, .wednesday],
            byPositionalDay: [PositionalDay(position: .first, dayType: .weekday(.sunday))]
        )
        let encoded = RRuleCodec.encode(malformed)
        let byDayOccurrences = encoded.components(separatedBy: ";").filter { $0.hasPrefix("BYDAY=") }
        #expect(byDayOccurrences.count == 1)
        #expect(encoded == "FREQ=WEEKLY;BYDAY=MO,WE")
    }

    @Test("decoding a weekly BYDAY with no recognizable weekday tokens yields nil byDay, not an empty array")
    func decodeEmptyByDayYieldsNil() {
        // Simulates decoding the malformed double-BYDAY string that neverEncodesDoubleBYDAY
        // guards against ever being produced: if it somehow still occurred, the last BYDAY
        // line ("BYDAY=1SU", an ordinal token) would compact-map away to [] under the old
        // decode logic. [] must never survive decode - it must become nil, matching
        // OccurrenceExpander's "nil = default to anchor's weekday" fallback semantics.
        let decoded = RRuleCodec.decode("FREQ=WEEKLY;BYDAY=1SU")
        #expect(decoded?.byDay == nil)
    }

    @Test("end-to-end: a stale byPositionalDay alongside weekly byDay survives encode/decode/expand and matches a clean equivalent rule")
    func fix1EndToEndReproduction() {
        // This is the scenario from the Critical bug report: Repeat -> Custom -> unit: month ->
        // On Week -> Add Rule -> back -> unit: week -> Add. The resulting RecurrenceRule (as it
        // would have been BEFORE the CustomRepeatView.commit() gating fix) carries frequency:
        // .weekly, a real byDay, AND a leftover non-nil byPositionalDay from the earlier
        // month-mode interaction.
        let malformed = RecurrenceRule(
            frequency: .weekly,
            byDay: [.monday, .wednesday, .friday],
            byPositionalDay: [PositionalDay(position: .first, dayType: .weekday(.sunday))]
        )
        let clean = RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday, .friday])

        let encoded = RRuleCodec.encode(malformed)
        let decoded = RRuleCodec.decode(encoded)

        // Only one BYDAY line was ever encoded, and it round-trips back to the same clean rule -
        // the leftover byPositionalDay never survives into the weekly rule.
        #expect(decoded == clean)

        // 2026-09-01 is a Tuesday; recur Mon/Wed/Fri.
        let anchor = DateMath.date(from: "2026-09-01")
        let range = DateMath.date(from: "2026-09-01")...DateMath.date(from: "2026-09-11")
        let occurrencesFromMalformed = OccurrenceExpander.occurrences(anchor: anchor, rule: decoded, exceptionDates: [], in: range)
        let occurrencesFromClean = OccurrenceExpander.occurrences(anchor: anchor, rule: clean, exceptionDates: [], in: range)

        #expect(!occurrencesFromMalformed.isEmpty)
        #expect(occurrencesFromMalformed == occurrencesFromClean)
        #expect(occurrencesFromMalformed == [
            DateMath.date(from: "2026-09-02"), DateMath.date(from: "2026-09-04"),
            DateMath.date(from: "2026-09-07"), DateMath.date(from: "2026-09-09"),
            DateMath.date(from: "2026-09-11")
        ])
    }
}
