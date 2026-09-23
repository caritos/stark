// ios/Tests/StarkKitTests/DisplayNameTests.swift
import Testing
@testable import StarkKit

@Suite("Weekday and Month display names")
struct DisplayNameTests {
    @Test("every weekday has its expected display name, in calendar order")
    func weekdayNames() {
        #expect(Weekday.allCases.map(\.displayName) == [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ])
    }

    @Test("every month has its expected display name, in calendar order")
    func monthNames() {
        #expect(Month.allCases.map(\.displayName) == [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ])
    }
}
