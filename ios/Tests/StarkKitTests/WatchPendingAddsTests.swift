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

/// Unreachable until `reachable` is set; a live send then suspends until `release`.
private final class GateTransport: WatchTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<WatchReply, Never>?
    private var _reachable = false
    private var _sends = 0
    private var _queued: [WatchEnvelope] = []
    var reachable: Bool { get { lock.withLock { _reachable } } set { lock.withLock { _reachable = newValue } } }
    var sends: Int { lock.withLock { _sends } }
    var queued: [WatchEnvelope] { lock.withLock { _queued } }
    var isReachable: Bool { reachable }
    func send(_ envelope: WatchEnvelope) async throws -> WatchReply {
        await withCheckedContinuation { c in lock.withLock { _sends += 1; continuation = c } }
    }
    func release(_ reply: WatchReply) { lock.withLock { let c = continuation; continuation = nil; return c }?.resume(returning: reply) }
    func queue(_ envelope: WatchEnvelope) { lock.withLock { _queued.append(envelope) } }
    func reply(_ reply: WatchReplyEnvelope) {}
}

@MainActor
@Suite struct WatchPendingAddsRetryTests {
    @Test func aRetryDoubleTapSendsOneEnvelopeAndLeavesOneEntry() async throws {
        let t = GateTransport()
        let outbox = WatchOutbox(transport: t, pending: InMemoryPendingStore())
        let pending = WatchPendingAdds(outbox: outbox)
        let m = WatchAddModel(outbox: outbox, pendingAdds: pending, now: { t0 })
        m.dictated("Call mom")
        await m.confirm()
        m.cancel()
        let firstID = try #require(t.queued.first?.id)
        outbox.receive(WatchReplyEnvelope(id: firstID, reply: .failed("No calendar")))
        t.reachable = true
        let first = Task { await pending.retry(firstID) }
        while t.sends == 0 { await Task.yield() }
        await pending.retry(firstID)  // the second tap
        t.release(.failed("still no"))
        await first.value
        #expect(t.sends == 1)
        #expect(pending.entries.count == 1)
        #expect(pending.entries[0].id != firstID)
        #expect(pending.entries[0].state == .failed("still no"))
    }

    @Test func aRetryRefusedByAFullQueueLeavesTheFailedEntryRetryable() async throws {
        let t = GateTransport()
        let outbox = WatchOutbox(transport: t, pending: InMemoryPendingStore(), maxWaiting: 1)
        let pending = WatchPendingAdds(outbox: outbox)
        let m = WatchAddModel(outbox: outbox, pendingAdds: pending, now: { t0 })
        m.dictated("A")
        await m.confirm()
        m.cancel()
        let aID = try #require(t.queued.first?.id)
        outbox.receive(WatchReplyEnvelope(id: aID, reply: .failed("No calendar")))
        m.dictated("B")
        await m.confirm()  // fills the one waiting slot
        m.cancel()
        await pending.retry(aID)
        #expect(pending.entries.first { $0.id == aID }?.state == .failed("No calendar"))
        // Free the slot: B answers, then the retry goes through.
        let bID = try #require(t.queued.last?.id)
        outbox.receive(WatchReplyEnvelope(id: bID, reply: .done(notice: nil, warning: nil)))
        await pending.retry(aID)
        #expect(pending.entries.count == 1)
        #expect(pending.entries[0].id != aID)
        #expect(pending.entries[0].state == .waiting)
    }

    @Test func relaunchEntriesComeInSendOrder() async {
        let store = InMemoryPendingStore()
        let clock = TestClock(t0)
        let o1 = WatchOutbox(transport: GateTransport(), pending: store, now: { clock.now })
        await o1.submit(.add(WatchAddDraft.make(dictation: "one", now: t0)!))
        clock.now = t0.addingTimeInterval(10)
        await o1.submit(.add(WatchAddDraft.make(dictation: "two", now: t0)!))
        clock.now = t0.addingTimeInterval(20)
        await o1.submit(.add(WatchAddDraft.make(dictation: "three", now: t0)!))
        let relaunched = WatchPendingAdds(outbox: WatchOutbox(transport: GateTransport(), pending: store))
        #expect(relaunched.entries.map(\.draft.title) == ["one", "two", "three"])
    }
}
