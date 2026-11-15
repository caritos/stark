// ios/Tests/StarkKitTests/AppleAccessChangeTests.swift
import Testing
@testable import StarkKit

@Suite("AppleAccessChange")
struct AppleAccessChangeTests {
    private func action(_ previous: AppleAccess, _ current: AppleAccess, on: Bool) -> AppleAccessChange {
        AppleAccessChange.action(previous: previous, current: current, isEnabled: on)
    }

    @Test func unchangedGrantedDoesNothing() {
        #expect(action(.granted, .granted, on: true) == .none)
    }

    @Test func becomingGrantedWithSwitchOnReloads() {
        #expect(action(.denied, .granted, on: true) == .reload)
        #expect(action(.notAsked, .granted, on: true) == .reload)
        #expect(action(.writeOnly, .granted, on: true) == .reload)
    }

    @Test func becomingGrantedWithSwitchOffDoesNothing() {
        #expect(action(.denied, .granted, on: false) == .none)
    }

    @Test func losingGrantedClears() {
        #expect(action(.granted, .denied, on: true) == .clear)
        #expect(action(.granted, .writeOnly, on: true) == .clear)
        #expect(action(.granted, .notAsked, on: true) == .clear)
    }

    @Test func losingGrantedWithSwitchOffDoesNothingAsTheSnapshotIsAlreadyEmpty() {
        #expect(action(.granted, .denied, on: false) == .none)
    }

    @Test func notGrantedToAnotherNotGrantedDoesNothing() {
        #expect(action(.denied, .writeOnly, on: true) == .none)
        #expect(action(.notAsked, .denied, on: true) == .none)
        #expect(action(.denied, .denied, on: true) == .none)
    }
}
