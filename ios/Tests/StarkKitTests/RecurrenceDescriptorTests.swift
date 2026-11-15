import Testing
import Foundation
@testable import StarkKit

@Suite("RecurrenceDescriptor")
struct RecurrenceDescriptorTests {
    private func roundTrip(_ rule: RecurrenceRule, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let descriptor = try RecurrenceDescriptor(rule)
        #expect(try descriptor.asStarkRule() == rule, sourceLocation: sourceLocation)
        #expect(descriptor.isRepresentableInStark, sourceLocation: sourceLocation)
    }

    private func reason(_ descriptor: RecurrenceDescriptor) -> String? {
        do {
            _ = try descriptor.asStarkRule()
            return nil
        } catch ItemRepositoryError.unrepresentable(let why) {
            return why
        } catch {
            return "wrong error \(error)"
        }
    }

    private var day: Date {
        Calendar(identifier: .gregorian).startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    }

    // MARK: round trips (every shape the spike marked supported)

    @Test func weeklySeveralWeekdays() throws {
        try roundTrip(RecurrenceRule(frequency: .weekly, byDay: [.monday, .wednesday, .friday]))
    }
    @Test func weeklyNoDays() throws { try roundTrip(RecurrenceRule(frequency: .weekly)) }
    @Test func monthlyDayN() throws { try roundTrip(RecurrenceRule(frequency: .monthly, byMonthDay: [15])) }
    @Test func monthlyTwoDays() throws { try roundTrip(RecurrenceRule(frequency: .monthly, byMonthDay: [1, 15])) }
    @Test func monthlyDay31() throws { try roundTrip(RecurrenceRule(frequency: .monthly, byMonthDay: [31])) }
    @Test func lastDayOfMonth() throws {
        try roundTrip(RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .anyDay)]))
    }
    @Test func secondTuesday() throws {
        try roundTrip(RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .second, dayType: .weekday(.tuesday))]))
    }
    @Test func lastFriday() throws {
        try roundTrip(RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .weekday(.friday))]))
    }
    @Test func firstAndThirdMonday() throws {
        try roundTrip(RecurrenceRule(frequency: .monthly, byPositionalDay: [
            PositionalDay(position: .first, dayType: .weekday(.monday)),
            PositionalDay(position: .third, dayType: .weekday(.monday))]))
    }
    @Test func lastWeekdayAndFirstWeekendDay() throws {
        try roundTrip(RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .last, dayType: .weekdayOnly)]))
        try roundTrip(RecurrenceRule(frequency: .monthly, byPositionalDay: [PositionalDay(position: .first, dayType: .weekendDay)]))
    }
    @Test func untilIsInclusiveStartOfDay() throws {
        let rule = RecurrenceRule(frequency: .weekly, byDay: [.tuesday], until: day)
        let descriptor = try RecurrenceDescriptor(rule)
        #expect(descriptor.end == .until(day))
        try roundTrip(rule)
    }
    @Test func untilIsNormalisedToStartOfDay() throws {
        let rule = RecurrenceRule(frequency: .daily, until: day.addingTimeInterval(9 * 3600))
        #expect(try RecurrenceDescriptor(rule).end == .until(day))
    }
    @Test func count() throws {
        let rule = RecurrenceRule(frequency: .daily, count: 5)
        #expect(try RecurrenceDescriptor(rule).end == .count(5))
        try roundTrip(rule)
    }
    @Test func interval2() throws {
        try roundTrip(RecurrenceRule(frequency: .weekly, interval: 2, byDay: [.tuesday, .thursday]))
        try roundTrip(RecurrenceRule(frequency: .daily, interval: 2))
        try roundTrip(RecurrenceRule(frequency: .monthly, interval: 3, byMonthDay: [10]))
    }
    @Test func yearlyShapes() throws {
        try roundTrip(RecurrenceRule(frequency: .yearly))
        try roundTrip(RecurrenceRule(frequency: .yearly, byMonthDay: [10], byMonth: [.march, .september]))
        try roundTrip(RecurrenceRule(
            frequency: .yearly,
            byPositionalDay: [PositionalDay(position: .second, dayType: .weekday(.thursday))],
            byMonth: [.november]))
    }
    @Test func daily() throws { try roundTrip(RecurrenceRule(frequency: .daily)) }

    @Test func descriptorFieldsMirrorEventKit() throws {
        let second = PositionalDay(position: .second, dayType: .weekday(.tuesday))
        let d = try RecurrenceDescriptor(RecurrenceRule(frequency: .monthly, byPositionalDay: [second]))
        #expect(d.frequency == .monthly)
        #expect(d.interval == 1)
        #expect(d.daysOfTheWeek == [.init(.tuesday, weekNumber: 2)])
        #expect(d.daysOfTheMonth.isEmpty && d.setPositions.isEmpty)
        let lastDay = PositionalDay(position: .last, dayType: .anyDay)
        let last = try RecurrenceDescriptor(RecurrenceRule(frequency: .monthly, byPositionalDay: [lastDay]))
        #expect(last.daysOfTheMonth == [-1])
        let lastWeekday = PositionalDay(position: .last, dayType: .weekdayOnly)
        let wk = try RecurrenceDescriptor(RecurrenceRule(frequency: .monthly, byPositionalDay: [lastWeekday]))
        #expect(wk.daysOfTheWeek.map(\.weekday) == [.monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(wk.setPositions == [-1])
    }

    // MARK: Apple alternative forms are read

    @Test func readsAppleAlternativeForms() throws {
        let allDays = Weekday.allCases.map { RecurrenceDescriptor.DayOfWeek($0) }
        let lastDay = RecurrenceDescriptor(frequency: .monthly, daysOfTheWeek: allDays, setPositions: [-1])
        #expect(try lastDay.asStarkRule().byPositionalDay == [PositionalDay(position: .last, dayType: .anyDay)])
        let second = RecurrenceDescriptor(frequency: .monthly, daysOfTheWeek: [.init(.tuesday)], setPositions: [2])
        #expect(try second.asStarkRule().byPositionalDay == [PositionalDay(position: .second, dayType: .weekday(.tuesday))])
    }

    // MARK: unrepresentable

    @Test func mixedPerWeekdayWeekNumbersAreUnrepresentable() {
        let d = RecurrenceDescriptor(frequency: .monthly, daysOfTheWeek: [
            .init(.monday, weekNumber: 1), .init(.wednesday, weekNumber: 3)])
        #expect(!d.isRepresentableInStark)
        #expect(reason(d)?.contains("different weeks") == true)
    }
    @Test func unrepresentableShapesCarryAReason() {
        let cases: [RecurrenceDescriptor] = [
            .init(frequency: .monthly, daysOfTheWeek: [.init(.monday, weekNumber: 5)]),
            .init(frequency: .monthly, daysOfTheWeek: [.init(.monday, weekNumber: 2)], daysOfTheMonth: [15]),
            .init(frequency: .monthly, daysOfTheMonth: [15], setPositions: [1]),
            .init(frequency: .monthly, daysOfTheWeek: [.init(.monday), .init(.tuesday, weekNumber: 2)]),
            .init(frequency: .monthly, daysOfTheWeek: [.init(.monday)]),
            .init(frequency: .weekly, daysOfTheMonth: [3]),
            .init(frequency: .daily, daysOfTheWeek: [.init(.monday)]),
            .init(frequency: .monthly, monthsOfTheYear: [3]),
            .init(frequency: .yearly, monthsOfTheYear: [13]),
            .init(frequency: .monthly, setPositions: [1]),
            .init(frequency: .monthly, daysOfTheMonth: [-2]),
            .init(frequency: .monthly, daysOfTheWeek: [.init(.monday)], setPositions: [3, 9]),
            .init(frequency: .daily, interval: 0),
        ]
        for d in cases {
            let why = reason(d)
            #expect(why != nil && why!.count > 10 && !why!.hasPrefix("wrong error"), "\(d) -> \(String(describing: why))")
            #expect(!d.isRepresentableInStark)
        }
    }
    /// The device checklist's example of a repeat Stark can't hold (Calendar: Custom > Monthly >
    /// On the... > fifth > Monday). Stark's `Position` has 1st-4th and last only, so both ways
    /// EventKit can spell it are refused.
    @Test func fifthMondayIsUnrepresentable() {
        let weekNumber = RecurrenceDescriptor(frequency: .monthly, daysOfTheWeek: [.init(.monday, weekNumber: 5)])
        let setPosition = RecurrenceDescriptor(frequency: .monthly, daysOfTheWeek: [.init(.monday)], setPositions: [5])
        for d in [weekNumber, setPosition] {
            #expect(!d.isRepresentableInStark, "\(d)")
            #expect(reason(d)?.contains("1st to 4th and the last") == true, "\(d)")
        }
        // The 2nd Tuesday, by contrast, is representable (`secondTuesday`).
        #expect(RecurrenceDescriptor(frequency: .monthly, daysOfTheWeek: [.init(.tuesday, weekNumber: 2)]).isRepresentableInStark)
    }
    @Test func representableDescriptorsReportTrue() {
        #expect(RecurrenceDescriptor(frequency: .daily).isRepresentableInStark)
        #expect(RecurrenceDescriptor(frequency: .weekly, daysOfTheWeek: [.init(.monday)]).isRepresentableInStark)
    }

    // MARK: byMonthDay -1 is pinned

    @Test func byMonthDayMinusOneBecomesPositionalLastDay() throws {
        let rule = RecurrenceRule(frequency: .monthly, byMonthDay: [-1])
        let descriptor = try RecurrenceDescriptor(rule)
        #expect(descriptor.daysOfTheMonth == [-1])
        let back = try descriptor.asStarkRule()
        #expect(back.byMonthDay == nil)
        #expect(back.byPositionalDay == [PositionalDay(position: .last, dayType: .anyDay)])
    }

    @Test func byMonthDayMinusOneAndPositionalLastDayGiveSameDates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let anchor = calendar.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 9))!
        let end = calendar.date(from: DateComponents(year: 2028, month: 4, day: 30, hour: 23))!
        let plain = RecurrenceRule(frequency: .monthly, byMonthDay: [-1])
        let positional = try RecurrenceDescriptor(plain).asStarkRule()
        #expect(positional != plain)
        let a = OccurrenceExpander.occurrences(anchor: anchor, rule: plain, exceptionDates: [], in: anchor...end)
        let b = OccurrenceExpander.occurrences(anchor: anchor, rule: positional, exceptionDates: [], in: anchor...end)
        #expect(a == b)
        let days = a.map { calendar.dateComponents([.year, .month, .day], from: $0) }
        #expect(days.count == 16)
        #expect(days.contains(DateComponents(year: 2027, month: 2, day: 28)))
        #expect(days.contains(DateComponents(year: 2028, month: 2, day: 29)))
    }

    // MARK: named weekdays with several set positions

    @Test func oneWeekdayAtSeveralSetPositions() throws {
        let d = RecurrenceDescriptor(frequency: .monthly, daysOfTheWeek: [.init(.monday)], setPositions: [1, 3])
        #expect(try d.asStarkRule().byPositionalDay == [
            PositionalDay(position: .first, dayType: .weekday(.monday)),
            PositionalDay(position: .third, dayType: .weekday(.monday))])
        #expect(d.isRepresentableInStark)
    }

    @Test func twoWeekdaysAtTheLastSetPosition() throws {
        let d = RecurrenceDescriptor(frequency: .monthly, daysOfTheWeek: [.init(.monday), .init(.friday)], setPositions: [-1])
        #expect(try d.asStarkRule().byPositionalDay == [
            PositionalDay(position: .last, dayType: .weekday(.monday)),
            PositionalDay(position: .last, dayType: .weekday(.friday))])
    }

    @Test func repeatedWeekdayIsListedOnce() throws {
        let d = RecurrenceDescriptor(frequency: .monthly, daysOfTheWeek: [.init(.monday), .init(.monday)], setPositions: [1, 3])
        #expect(try d.asStarkRule().byPositionalDay?.count == 2)
    }

    // MARK: conflicting Stark rules throw instead of dropping data

    private func conflictReason(_ rule: RecurrenceRule) -> String? {
        do {
            _ = try RecurrenceDescriptor(rule)
            return nil
        } catch ItemRepositoryError.unrepresentable(let why) {
            return why
        } catch {
            return "wrong error \(error)"
        }
    }

    @Test func untilAndCountConflict() {
        let why = conflictReason(RecurrenceRule(frequency: .daily, count: 3, until: day))
        #expect(why?.contains("until") == true && why?.contains("count") == true)
    }
    @Test func byDayAndPositionalConflict() {
        let why = conflictReason(RecurrenceRule(
            frequency: .weekly, byDay: [.monday],
            byPositionalDay: [PositionalDay(position: .first, dayType: .weekday(.monday))]))
        #expect(why?.contains("byDay") == true && why?.contains("byPositionalDay") == true)
    }
    @Test func positionalAndMonthDayConflict() {
        for positional in [PositionalDay(position: .second, dayType: .weekday(.tuesday)),
                           PositionalDay(position: .last, dayType: .anyDay),
                           PositionalDay(position: .last, dayType: .weekdayOnly)] {
            let why = conflictReason(RecurrenceRule(frequency: .monthly, byMonthDay: [15], byPositionalDay: [positional]))
            #expect(why?.contains("byMonthDay") == true && why?.contains("byPositionalDay") == true)
        }
    }
    @Test func byDayOnNonWeeklyConflict() {
        for frequency in [RecurrenceRule.Frequency.daily, .monthly, .yearly] {
            let why = conflictReason(RecurrenceRule(frequency: frequency, byDay: [.monday]))
            #expect(why?.contains("byDay") == true && why?.contains("weekly") == true)
        }
    }

    // MARK: priority

    @Test func priorityScalesAgree() {
        for p in 1...9 {
            #expect(appleReminderPriority(p) == p)
            #expect(icalPriority(fromApple: p) == p)
        }
        #expect(appleReminderPriority(nil) == 0)
        #expect(icalPriority(fromApple: 0) == nil)
    }
    @Test func priorityOutOfRangeMeansNone() {
        #expect(appleReminderPriority(0) == 0)
        #expect(appleReminderPriority(10) == 0)
        #expect(icalPriority(fromApple: 10) == nil)
        #expect(icalPriority(fromApple: -1) == nil)
    }
}
