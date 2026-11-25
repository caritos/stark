import Foundation
import Testing
@testable import StarkKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private final class SuspendingAddTransport: WatchTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<WatchReply, Never>?
    private var _sends = 0
    var sends: Int { lock.withLock { _sends } }
    var isReachable: Bool { true }
    func send(_ envelope: WatchEnvelope) async throws -> WatchReply {
        await withCheckedContinuation { c in lock.withLock { _sends += 1; continuation = c } }
    }
    func release(_ reply: WatchReply) { lock.withLock { let c = continuation; continuation = nil; return c }?.resume(returning: reply) }
    func queue(_ envelope: WatchEnvelope) {}
    func reply(_ reply: WatchReplyEnvelope) {}
}

@MainActor
private func addModel(_ transport: WatchTransport) -> WatchAddModel {
    let outbox = WatchOutbox(transport: transport, pending: InMemoryPendingStore())
    return WatchAddModel(outbox: outbox, pendingAdds: WatchPendingAdds(outbox: outbox), now: { t0 })
}

@MainActor
@Suite struct WatchAddModelTests {
    @Test func dictatedTextGoesToConfirmingAndSendsNothing() {
        let t = FakeWatchTransport(reachable: true)
        let m = addModel(t)
        m.dictated("Call mom")
        guard case .confirming(let draft) = m.phase else { Issue.record("not confirming: \(m.phase)"); return }
        #expect(draft.title == "Call mom")
        #expect(t.sent.isEmpty && t.queued.isEmpty)
    }

    @Test func emptyDictationStaysIdle() {
        let t = FakeWatchTransport(reachable: true)
        let m = addModel(t)
        m.dictated("   \n")
        #expect(m.phase == .idle)
        #expect(t.sent.isEmpty)
    }

    @Test func confirmSendsOneAddCommandWithTheDraft() async throws {
        let t = FakeWatchTransport(reachable: true)
        let m = addModel(t)
        m.dictated("Call mom")
        guard case .confirming(let draft) = m.phase else { return }
        await m.confirm()
        #expect(t.sent.count == 1)
        #expect(try #require(t.sent.first).command == .add(draft))
    }

    @Test func aDoneReplyShowsTheNoticeAndWarning() async {
        let t = FakeWatchTransport(reachable: true, result: .success(.done(notice: "Added to Home · iCloud", warning: "Stays on this iPhone")))
        let m = addModel(t)
        m.dictated("Call mom")
        await m.confirm()
        #expect(m.phase == .saved(notice: "Added to Home · iCloud", warning: "Stays on this iPhone"))
    }

    @Test func anUnreachablePhoneShowsWaiting() async {
        let t = FakeWatchTransport(reachable: false)
        let m = addModel(t)
        m.dictated("Call mom")
        await m.confirm()
        #expect(m.phase == .waiting)
        #expect(t.queued.count == 1)
    }

    @Test func aLateReplyMovesWaitingToSaved() async throws {
        let t = FakeWatchTransport(reachable: false)
        let m = addModel(t)
        m.dictated("Call mom")
        await m.confirm()
        let id = try #require(t.queued.first?.id)
        m.outbox.receive(WatchReplyEnvelope(id: id, reply: .done(notice: "Added", warning: nil)))
        #expect(m.phase == .saved(notice: "Added", warning: nil))
    }

    @Test func aLateFailureMovesWaitingToFailedAndKeepsTheDraft() async throws {
        let t = FakeWatchTransport(reachable: false)
        let m = addModel(t)
        m.dictated("Call mom")
        await m.confirm()
        let id = try #require(t.queued.first?.id)
        m.outbox.receive(WatchReplyEnvelope(id: id, reply: .failed("No calendar")))
        #expect(m.phase == .failed("No calendar"))
        t.isReachable = true
        await m.confirm()
        #expect(t.sent.count == 1)
    }

    @Test func confirmWhileWaitingSendsNoSecondEnvelope() async {
        let t = FakeWatchTransport(reachable: false)
        let m = addModel(t)
        m.dictated("Call mom")
        await m.confirm()
        await m.confirm()
        #expect(t.queued.count == 1 && t.sent.isEmpty)
    }

    @Test func aFailedReplyKeepsTheDraftSoItCanBeRetried() async {
        let t = FakeWatchTransport(reachable: true, result: .success(.failed("boom")))
        let m = addModel(t)
        m.dictated("Call mom")
        await m.confirm()
        #expect(m.phase == .failed("boom"))
        t.result = .success(.done(notice: "Added", warning: nil))
        await m.confirm()
        #expect(m.phase == .saved(notice: "Added", warning: nil))
        #expect(t.sent.count == 2)
        #expect(t.sent[0].command == t.sent[1].command)
    }

    @Test func aDoubleTapSendsExactlyOneEnvelope() async {
        let t = SuspendingAddTransport()
        let m = addModel(t)
        m.dictated("Call mom")
        let first = Task { await m.confirm() }
        while t.sends == 0 { await Task.yield() }
        #expect(m.phase == .sending)
        await m.confirm()
        t.release(.done(notice: "Added", warning: nil))
        await first.value
        #expect(t.sends == 1)
        #expect(m.phase == .saved(notice: "Added", warning: nil))
    }

    @Test func aFullQueueFailsVisiblyAndKeepsTheDraft() async {
        let t = FakeWatchTransport(reachable: false)
        let outbox = WatchOutbox(transport: t, pending: InMemoryPendingStore(), maxWaiting: 0)
        let m = WatchAddModel(outbox: outbox, pendingAdds: WatchPendingAdds(outbox: outbox), now: { t0 })
        m.dictated("Call mom")
        await m.confirm()
        #expect(m.phase == .failed(WatchOutbox.fullMessage))
        #expect(t.queued.isEmpty)
    }

    @Test func cancelSendsNothing() {
        let t = FakeWatchTransport(reachable: true)
        let m = addModel(t)
        m.dictated("Call mom")
        m.cancel()
        #expect(m.phase == .idle)
        #expect(t.sent.isEmpty && t.queued.isEmpty)
    }

    @Test func retryUsesANewEnvelopeIdWithTheSameDraft() async {
        let t = FakeWatchTransport(reachable: true, result: .success(.failed("boom")))
        let m = addModel(t)
        m.dictated("Call mom")
        guard case .confirming(let draft) = m.phase else { return }
        await m.confirm()
        await m.confirm()
        #expect(t.sent.count == 2)
        #expect(t.sent[0].id != t.sent[1].id)
        #expect(t.sent[1].command == .add(draft))
    }

    @Test func cancelWhileWaitingThenALateReplyKeepsThePhaseIdle() async throws {
        let t = FakeWatchTransport(reachable: false)
        let m = addModel(t)
        m.dictated("Call mom")
        await m.confirm()
        m.cancel()
        let id = try #require(t.queued.first?.id)
        m.outbox.receive(WatchReplyEnvelope(id: id, reply: .done(notice: "Added", warning: nil)))
        #expect(m.phase == .idle)
    }

    @Test func dismissingDuringSubmittingGoesIdleAfterTheSendAndHandsOver() async {
        let t = SuspendingAddTransport()
        let outbox = WatchOutbox(transport: t, pending: InMemoryPendingStore())
        let pending = WatchPendingAdds(outbox: outbox)
        let m = WatchAddModel(outbox: outbox, pendingAdds: pending, now: { t0 })
        m.dictated("Call mom")
        let first = Task { await m.confirm() }
        while t.sends == 0 { await Task.yield() }
        m.cancel()
        t.release(.failed("No calendar"))
        await first.value
        #expect(m.phase == .idle)
        #expect(pending.entries.count == 1)
        #expect(pending.entries.first?.state == .failed("No calendar"))
    }
}
