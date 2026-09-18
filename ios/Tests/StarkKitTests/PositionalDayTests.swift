import Testing
@testable import StarkKit

@Suite("PositionalDay")
struct PositionalDayTests {
    @Test("equality holds for identical position and day type")
    func equality() {
        let a = PositionalDay(position: .second, dayType: .weekday(.tuesday))
        let b = PositionalDay(position: .second, dayType: .weekday(.tuesday))
        #expect(a == b)
    }

    @Test("Month raw values run January...December as 1...12")
    func monthRawValues() {
        #expect(Month.january.rawValue == 1)
        #expect(Month.december.rawValue == 12)
    }

    @Test("Position raw values match RRULE BYMONTHDAY/ordinal-BYDAY encoding directly")
    func positionRawValues() {
        #expect(Position.first.rawValue == 1)
        #expect(Position.fourth.rawValue == 4)
        #expect(Position.last.rawValue == -1)
    }
}
