// ios/Tests/StarkKitTests/RecurrenceRulePickerFieldsTests.swift
import Testing
@testable import StarkKit

@Suite("RecurrenceRule.fromPickerFields")
struct RecurrenceRulePickerFieldsTests {
    @Test("weekly keeps byDay, sorted, and drops the monthly/yearly-only fields")
    func weeklyKeepsByDay() {
        let rule = RecurrenceRule.fromPickerFields(
            frequency: .weekly,
            interval: 2,
            byDay: [.friday, .monday],
            byMonthDay: [5],
            byPositionalDay: [PositionalDay(position: .first, dayType: .weekday(.monday))],
            byMonth: [.march]
        )
        #expect(rule.byDay == [.monday, .friday])
        #expect(rule.byMonthDay == nil)
        #expect(rule.byPositionalDay == nil)
        #expect(rule.byMonth == nil)
        #expect(rule.interval == 2)
    }

    @Test("weekly with an empty byDay set decodes to nil, not an empty array")
    func weeklyEmptyByDayIsNil() {
        let rule = RecurrenceRule.fromPickerFields(
            frequency: .weekly, interval: 1, byDay: [], byMonthDay: nil, byPositionalDay: nil, byMonth: []
        )
        #expect(rule.byDay == nil)
    }

    @Test("daily drops every extra field regardless of what's passed in")
    func dailyDropsEverything() {
        let rule = RecurrenceRule.fromPickerFields(
            frequency: .daily,
            interval: 1,
            byDay: [.monday],
            byMonthDay: [1],
            byPositionalDay: [PositionalDay(position: .last, dayType: .anyDay)],
            byMonth: [.june]
        )
        #expect(rule.byDay == nil)
        #expect(rule.byMonthDay == nil)
        #expect(rule.byPositionalDay == nil)
        #expect(rule.byMonth == nil)
    }

    @Test("monthly keeps byMonthDay and byPositionalDay but drops byDay/byMonth")
    func monthlyKeepsMonthDayAndPositional() {
        let rule = RecurrenceRule.fromPickerFields(
            frequency: .monthly,
            interval: 1,
            byDay: [.monday],
            byMonthDay: [15],
            byPositionalDay: [PositionalDay(position: .second, dayType: .weekday(.tuesday))],
            byMonth: [.june]
        )
        #expect(rule.byDay == nil)
        #expect(rule.byMonthDay == [15])
        #expect(rule.byPositionalDay == [PositionalDay(position: .second, dayType: .weekday(.tuesday))])
        #expect(rule.byMonth == nil)
    }

    @Test("yearly keeps byMonth, sorted, plus byMonthDay/byPositionalDay, but drops byDay")
    func yearlyKeepsMonthAndMonthDay() {
        let rule = RecurrenceRule.fromPickerFields(
            frequency: .yearly,
            interval: 1,
            byDay: [.monday],
            byMonthDay: [4],
            byPositionalDay: nil,
            byMonth: [.september, .march]
        )
        #expect(rule.byDay == nil)
        #expect(rule.byMonthDay == [4])
        #expect(rule.byMonth == [.march, .september])
    }

    @Test("yearly with an empty byMonth set decodes to nil, not an empty array")
    func yearlyEmptyByMonthIsNil() {
        let rule = RecurrenceRule.fromPickerFields(
            frequency: .yearly, interval: 1, byDay: [], byMonthDay: nil, byPositionalDay: nil, byMonth: []
        )
        #expect(rule.byMonth == nil)
    }
}
