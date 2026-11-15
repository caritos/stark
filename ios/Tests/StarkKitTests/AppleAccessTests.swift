// ios/Tests/StarkKitTests/AppleAccessTests.swift
import Testing
@testable import StarkKit

@Suite("AppleAccess.combined")
struct AppleAccessTests {
    @Test func grantedOnlyWhenBothGranted() {
        #expect(AppleAccess.combined(events: .granted, reminders: .granted) == .granted)
    }

    @Test func oneGrantedOtherNotAskedIsNotAsked() {
        #expect(AppleAccess.combined(events: .granted, reminders: .notAsked) == .notAsked)
        #expect(AppleAccess.combined(events: .notAsked, reminders: .granted) == .notAsked)
        #expect(AppleAccess.combined(events: .notAsked, reminders: .notAsked) == .notAsked)
    }

    @Test func anyDeniedIsDenied() {
        #expect(AppleAccess.combined(events: .denied, reminders: .granted) == .denied)
        #expect(AppleAccess.combined(events: .granted, reminders: .denied) == .denied)
        #expect(AppleAccess.combined(events: .denied, reminders: .notAsked) == .denied)
        #expect(AppleAccess.combined(events: .writeOnly, reminders: .denied) == .denied)
    }

    @Test func writeOnlyWithoutDenialIsWriteOnly() {
        #expect(AppleAccess.combined(events: .writeOnly, reminders: .granted) == .writeOnly)
        #expect(AppleAccess.combined(events: .writeOnly, reminders: .notAsked) == .writeOnly)
    }
}
