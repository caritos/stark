import Foundation
import Testing
@testable import StarkKit

@Suite struct PlanRowTextTests {
    static let cal = Calendar(identifier: .gregorian)
    static func date(_ h: Int, _ m: Int, day: Int = 2) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }
    static func fmt(_ d: Date) -> String {
        let h = cal.component(.hour, from: d), m = cal.component(.minute, from: d)
        return String(format: "%d:%02d %@", h % 12 == 0 ? 12 : h % 12, m, h < 12 ? "AM" : "PM")
    }
    static func md(_ d: Date) -> String { "Nov \(cal.component(.day, from: d))" }
    static func fmt24(_ d: Date) -> String {
        String(format: "%02d:%02d", cal.component(.hour, from: d), cal.component(.minute, from: d))
    }

    @Test func rangeSharesPeriodOnce() {
        let t = PlanRowText.make(occurrence: Self.date(0, 0, day: 1), overdueText: nil,
                                 range: Self.date(9, 0)...Self.date(9, 30), time: Self.fmt, monthDay: Self.md)
        #expect(t.primary == "9:00 - 9:30 AM")
        #expect(t.secondary == nil)
    }

    @Test func rangeAcrossPeriodsKeepsBoth() {
        let t = PlanRowText.make(occurrence: Self.date(0, 0), overdueText: nil,
                                 range: Self.date(11, 30)...Self.date(12, 30), time: Self.fmt, monthDay: Self.md)
        #expect(t.primary == "11:30 AM - 12:30 PM")
    }

    @Test func timedTaskShowsOriginalDue() {
        let t = PlanRowText.make(occurrence: Self.date(15, 0), overdueText: nil,
                                 range: Self.date(9, 0)...Self.date(9, 30), time: Self.fmt, monthDay: Self.md)
        #expect(t.secondary == "due 3:00 PM")
    }

    @Test func overdueTextIsSecondary() {
        let t = PlanRowText.make(occurrence: Self.date(6, 0, day: 1), overdueText: "Nov 1 at 6:00 AM - 1 day overdue",
                                 range: Self.date(9, 0)...Self.date(10, 0), time: Self.fmt, monthDay: Self.md)
        #expect(t.secondary == "Nov 1 at 6:00 AM - 1 day overdue")
    }

    @Test func twentyFourHourStyleHasNoSuffixToTrim() {
        let t = PlanRowText.make(occurrence: Self.date(0, 0), overdueText: nil,
                                 range: Self.date(9, 0)...Self.date(9, 30), time: Self.fmt24, monthDay: Self.md)
        #expect(t.primary == "09:00 - 09:30")
    }

    static let nnbsp = "\u{202F}"
    static func fmtN(_ d: Date) -> String { fmt(d).replacingOccurrences(of: " ", with: nnbsp) }

    @Test func narrowNoBreakSpaceSharedSuffixShownOnce() {
        let t = PlanRowText.make(occurrence: Self.date(0, 0), overdueText: nil,
                                 range: Self.date(9, 0)...Self.date(9, 30), time: Self.fmtN, monthDay: Self.md)
        #expect(t.primary == "9:00 - 9:30\(Self.nnbsp)AM")
    }

    @Test func narrowNoBreakSpaceAcrossNoonKeepsBoth() {
        let t = PlanRowText.make(occurrence: Self.date(0, 0), overdueText: nil,
                                 range: Self.date(11, 30)...Self.date(12, 0), time: Self.fmtN, monthDay: Self.md)
        #expect(t.primary == "11:30\(Self.nnbsp)AM - 12:00\(Self.nnbsp)PM")
    }

    @Test func realDateFormatterRange() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.calendar = Self.cal
        f.timeZone = Self.cal.timeZone
        f.dateStyle = .none
        f.timeStyle = .short
        let t = PlanRowText.make(occurrence: Self.date(0, 0), overdueText: nil,
                                 range: Self.date(9, 0)...Self.date(9, 30), time: { f.string(from: $0) }, monthDay: Self.md)
        #expect(t.primary.hasPrefix("9:00 - 9:30"))
        #expect(t.primary.hasSuffix("AM"))
        #expect(t.primary.components(separatedBy: "AM").count == 2)
    }

    @Test func rangeEndingAtMidnightKeepsBoth() {
        let t = PlanRowText.make(occurrence: Self.date(0, 0), overdueText: nil,
                                 range: Self.date(23, 30)...Self.date(0, 0, day: 3), time: Self.fmt, monthDay: Self.md)
        #expect(t.primary == "11:30 PM - 12:00 AM")
    }

    @Test func allDayDueHasNoSecondaryLine() {
        let t = PlanRowText.make(occurrence: Self.date(0, 0, day: 2), overdueText: nil,
                                 range: Self.date(9, 0)...Self.date(9, 30), time: Self.fmt, monthDay: Self.md)
        #expect(t.secondary == nil)
    }

    @Test func timedTaskPlannedOnAnotherDayIncludesDueDate() {
        let t = PlanRowText.make(occurrence: Self.date(15, 0, day: 1), overdueText: nil,
                                 range: Self.date(9, 0)...Self.date(9, 30), time: Self.fmt, monthDay: Self.md)
        #expect(t.secondary == "due Nov 1, 3:00 PM")
    }

    @Test func overdueWithTimedOriginalUsesOverdueText() {
        let t = PlanRowText.make(occurrence: Self.date(15, 0, day: 1), overdueText: "Nov 1 at 3:00 PM \u{00B7} 1 day overdue",
                                 range: Self.date(9, 0)...Self.date(9, 30), time: Self.fmt, monthDay: Self.md)
        #expect(t.secondary == "Nov 1 at 3:00 PM \u{00B7} 1 day overdue")
    }
}
