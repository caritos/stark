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

    @Test func finishingTwiceStaysFinished() {
        // A second fetchFinished() (a later fetch, landed or failed) keeps the wait over.
        // This Kit type does not know whether a fetch failed: the failed-fetch path calls
        // fetchFinished() from AppleOverlayModel's reload (app target), and was checked on the
        // simulator, not here.
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
