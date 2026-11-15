// ios/Tests/StarkKitTests/AppleFetchWindowTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("AppleFetchWindow")
struct AppleFetchWindowTests {
    private func day(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + n * 86_400) }

    @Test func emptyWindowCoversNothing() {
        #expect(AppleFetchWindow().covering == nil)
    }

    @Test func singleScreenIsItsOwnRange() {
        var window = AppleFetchWindow()
        window.set(.agenda, day(0)...day(10))
        #expect(window.covering == day(0)...day(10))
    }

    @Test func gridMonthDoesNotNarrowTheAgendaRange() {
        // The month grid's reload must not drop the agenda's items (they share one snapshot).
        var window = AppleFetchWindow()
        window.set(.agenda, day(-14)...day(60))
        window.set(.monthGrid, day(-5)...day(36))
        #expect(window.covering == day(-14)...day(60))
    }

    @Test func coveringIsTheHullOfDisjointRanges() {
        var window = AppleFetchWindow()
        window.set(.agenda, day(0)...day(10))
        window.set(.year, day(100)...day(465))
        #expect(window.covering == day(0)...day(465))
    }

    @Test func replacingAScreensRangeForgetsTheOldOne() {
        var window = AppleFetchWindow()
        window.set(.agenda, day(0)...day(10))
        window.set(.agenda, day(50)...day(60))
        #expect(window.covering == day(50)...day(60))
    }

    @Test func releasingAScreenShrinksTheHull() {
        var window = AppleFetchWindow()
        window.set(.agenda, day(0)...day(10))
        window.set(.year, day(-1000)...day(-635))
        window.set(.year, nil)
        #expect(window.covering == day(0)...day(10))
    }

    @Test func releasingTheLastScreenCoversNothing() {
        var window = AppleFetchWindow()
        window.set(.monthGrid, day(0)...day(10))
        window.set(.monthGrid, nil)
        #expect(window.covering == nil)
    }
}
