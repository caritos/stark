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
}
