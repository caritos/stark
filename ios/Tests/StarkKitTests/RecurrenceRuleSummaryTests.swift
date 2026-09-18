// ios/Tests/StarkKitTests/RecurrenceRuleSummaryTests.swift
import Testing
@testable import StarkKit

@Suite("RecurrenceRule.summary")
struct RecurrenceRuleSummaryTests {
    @Test("a plain rule with no extra fields produces just the base frequency+interval string")
    func plainRule() {
        #expect(RecurrenceRule(frequency: .daily).summary == "Every day")
        #expect(RecurrenceRule(frequency: .weekly).summary == "Every week")
        #expect(RecurrenceRule(frequency: .monthly).summary == "Every month")
        #expect(RecurrenceRule(frequency: .yearly, interval: 3).summary == "Every 3 years")
    }

    @Test("a weekly rule with byDay includes the specific days, not just 'Every Week'")
    func weeklyWithByDay() {
        let rule = RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday, .friday])
        #expect(rule.summary == "Every week on Monday, Wednesday, Friday")
    }

    @Test("a monthly rule with byPositionalDay describes the position and day-type, not just 'Every Month'")
    func monthlyWithPositionalDay() {
        let rule = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .second, dayType: .weekday(.tuesday))])
        #expect(rule.summary == "Every month on the 2nd Tuesday")

        let lastWeekday = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .weekdayOnly)])
        #expect(lastWeekday.summary == "Every month on the last weekday")

        let lastDay = RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .anyDay)])
        #expect(lastDay.summary == "Every month on the last day")
    }

    @Test("a yearly rule with byMonth includes the months")
    func yearlyWithByMonth() {
        let rule = RecurrenceRule(frequency: .yearly, byMonth: [.march, .september])
        #expect(rule.summary == "Every year in March, September")
    }

    @Test("a monthly rule with byMonthDay includes ordinal day numbers")
    func monthlyWithByMonthDay() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [1, 15])
        #expect(rule.summary == "Every month on the 1st, 15th")
    }

    @Test("a yearly rule combines byMonth and byPositionalDay (e.g. Thanksgiving)")
    func yearlyWithMonthAndPositionalDay() {
        let rule = RecurrenceRule(frequency: .yearly, byPositionalDay: [PositionalDay(position: .fourth, dayType: .weekday(.thursday))], byMonth: [.november])
        #expect(rule.summary == "Every year in November on the 4th Thursday")
    }

    @Test("ordinal suffixes handle the 11th/12th/13th exception correctly")
    func ordinalTeensException() {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [11, 12, 13, 21])
        #expect(rule.summary == "Every month on the 11th, 12th, 13th, 21st")
    }
}
