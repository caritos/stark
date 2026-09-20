// ios/Tests/StarkKitTests/FormFieldsTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("FormFields")
struct FormFieldsTests {
    private let cal = Calendar(identifier: .gregorian)

    @Test("trimmedOrNil trims outer whitespace, keeps inner newlines, and turns blank into nil")
    func trimmedOrNil() {
        #expect(FormFields.trimmedOrNil("  hi \n") == "hi")
        #expect(FormFields.trimmedOrNil("a\nb") == "a\nb")
        #expect(FormFields.trimmedOrNil("   \n ") == nil)
        #expect(FormFields.trimmedOrNil("") == nil)
    }

    @Test("normalizedStart moves an all-day date to the start of its day and leaves a timed one alone")
    func normalizedStart() {
        let noon = DateMath.date(from: "2026-09-20")
        #expect(FormFields.normalizedStart(noon, allDay: true) == cal.startOfDay(for: noon))
        #expect(FormFields.normalizedStart(noon, allDay: false) == noon)
    }

    @Test("isAllDay is true exactly at local midnight")
    func isAllDay() {
        let noon = DateMath.date(from: "2026-09-20")
        #expect(FormFields.isAllDay(cal.startOfDay(for: noon)))
        #expect(!FormFields.isAllDay(noon))
        #expect(!FormFields.isAllDay(cal.startOfDay(for: noon).addingTimeInterval(60)))
    }
}
