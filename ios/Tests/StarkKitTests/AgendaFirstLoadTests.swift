// ios/Tests/StarkKitTests/AgendaFirstLoadTests.swift
import Testing
@testable import StarkKit

@Suite("AgendaFirstLoad")
struct AgendaFirstLoadTests {
    @Test func grantedBeforeTheFirstFetchWaits() {
        let state = AgendaFirstLoad()
        #expect(state.isWaiting(access: .granted))
        #expect(state.hidesAgenda(access: .granted, isPositioned: false))
    }

    @Test func withoutAccessNeverWaits() {
        // The access screen shows at once: no spinner for not asked, denied or write-only.
        let state = AgendaFirstLoad()
        for access in [AppleAccess.notAsked, .denied, .writeOnly] {
            #expect(!state.isWaiting(access: access))
            #expect(!state.hidesAgenda(access: access, isPositioned: false))
        }
    }

    @Test func aLandedFetchEndsTheWait() {
        var state = AgendaFirstLoad()
        state.fetchFinished()
        #expect(!state.isWaiting(access: .granted))
    }

    @Test func aFailedFetchAlsoEndsTheWait() {
        // A failed first fetch must not spin forever: it ends the wait like a landed one.
        var state = AgendaFirstLoad()
        state.fetchFinished()
        state.fetchFinished()
        #expect(state.hasFinishedOnce)
        #expect(!state.isWaiting(access: .granted))
    }

    @Test func theAgendaStaysHiddenUntilItIsScrolledIntoPlace() {
        var state = AgendaFirstLoad()
        state.fetchFinished()
        #expect(state.hidesAgenda(access: .granted, isPositioned: false))
        #expect(!state.hidesAgenda(access: .granted, isPositioned: true))
    }

    @Test func losingAndRegainingAccessDoesNotWaitAgain() {
        var state = AgendaFirstLoad()
        state.fetchFinished()
        #expect(!state.isWaiting(access: .denied))
        #expect(!state.isWaiting(access: .granted))
    }
}
