import Foundation
import Testing
@testable import StarkKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
private func make(_ t: FakeWatchTransport, store: InMemoryPendingStore = InMemoryPendingStore())
    -> (WatchAddModel, WatchPendingAdds, WatchOutbox) {
    let outbox = WatchOutbox(transport: t, pending: store)
    let pending = WatchPendingAdds(outbox: outbox)
    return (WatchAddModel(outbox: outbox, pendingAdds: pending, now: { t0 }), pending, outbox)
}

@MainActor
@Suite struct WatchPendingAddsTests {
    @Test func aWaitingAddSurvivesDismissingTheSheetAndShowsALateFailure() async throws {
        let t = FakeWatchTransport(reachable: false)
        let (m, pending, outbox) = make(t)
        m.dictated("Call mom")
        await m.confirm()
        m.cancel()
        #expect(pending.entries.count == 1)
        #expect(pending.entries[0].state == .waiting)
        #expect(pending.entries[0].draft.title == "Call mom")
        let id = try #require(t.queued.first?.id)
        outbox.receive(WatchReplyEnvelope(id: id, reply: .failed("No calendar")))
        #expect(pending.entries.count == 1)
        #expect(pending.entries[0].state == .failed("No calendar"))
    }

    @Test func aLateDoneRemovesTheEntry() async throws {
        let t = FakeWatchTransport(reachable: false)
        let (m, pending, outbox) = make(t)
        m.dictated("Call mom")
        await m.confirm()
        m.cancel()
        let id = try #require(t.queued.first?.id)
        outbox.receive(WatchReplyEnvelope(id: id, reply: .done(notice: "Added", warning: nil)))
        #expect(pending.entries.isEmpty)
    }

    @Test func aRelaunchShowsTheWaitingAdd() async {
        let store = InMemoryPendingStore()
        let t = FakeWatchTransport(reachable: false)
        let (m, _, _) = make(t, store: store)
        m.dictated("Call mom")
        await m.confirm()
        let (_, relaunched, _) = make(FakeWatchTransport(reachable: false), store: store)
        #expect(relaunched.entries.count == 1)
        #expect(relaunched.entries[0].state == .waiting)
        #expect(relaunched.entries[0].draft.title == "Call mom")
    }

    @Test func retrySendsOneNewEnvelopeWithTheSameDraftAndReplacesTheFailedEntry() async throws {
        let t = FakeWatchTransport(reachable: false)
        let (m, pending, outbox) = make(t)
        m.dictated("Call mom")
        guard case .confirming(let draft) = m.phase else { return }
        await m.confirm()
        m.cancel()
        let firstID = try #require(t.queued.first?.id)
        outbox.receive(WatchReplyEnvelope(id: firstID, reply: .failed("No calendar")))
        t.isReachable = true
        await pending.retry(pending.entries[0].id)
        #expect(t.sent.count == 1)
        #expect(t.sent[0].id != firstID)
        #expect(t.sent[0].command == .add(draft))
        #expect(pending.entries.isEmpty)  // the new send was answered done
    }

    @Test func retryOfAStillFailingAddLeavesOneFailedEntry() async throws {
        let t = FakeWatchTransport(reachable: true, result: .success(.failed("boom")))
        let (m, pending, _) = make(t)
        m.dictated("Call mom")
        await m.confirm()
        m.cancel()
        let old = pending.entries[0].id
        await pending.retry(old)
        #expect(pending.entries.count == 1)
        #expect(pending.entries[0].id != old)
        #expect(pending.entries[0].state == .failed("boom"))
    }

    @Test func dismissRemovesTheEntry() async {
        let t = FakeWatchTransport(reachable: true, result: .success(.failed("boom")))
        let (m, pending, _) = make(t)
        m.dictated("Call mom")
        await m.confirm()
        m.cancel()
        pending.dismiss(pending.entries[0].id)
        #expect(pending.entries.isEmpty)
    }

    @Test func cancelOfAnUnsubmittedDraftSendsNothingAndMakesNoEntry() {
        let t = FakeWatchTransport(reachable: true)
        let (m, pending, _) = make(t)
        m.dictated("Call mom")
        m.cancel()
        #expect(t.sent.isEmpty && t.queued.isEmpty)
        #expect(pending.entries.isEmpty)
    }

    @Test func aSavedAddLeavesNoEntry() async {
        let t = FakeWatchTransport(reachable: true)
        let (m, pending, _) = make(t)
        m.dictated("Call mom")
        await m.confirm()
        m.cancel()
        #expect(pending.entries.isEmpty)
    }
}
