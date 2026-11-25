import Foundation
import Testing
@testable import StarkKit

private final class MemoryStore: WatchSnapshotStore, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: WatchSnapshot?
    init(_ snapshot: WatchSnapshot? = nil) { self.snapshot = snapshot }
    func load() -> WatchSnapshot? { lock.withLock { snapshot } }
    func save(_ snapshot: WatchSnapshot) { lock.withLock { self.snapshot = snapshot } }
}

private struct NullTransport: WatchTransport {
    var isReachable: Bool { false }
    func send(_ envelope: WatchEnvelope) async throws -> WatchReply { .failed("no") }
    func queue(_ envelope: WatchEnvelope) {}
    func reply(_ reply: WatchReplyEnvelope) {}
}

private struct NullPending: WatchPendingStore {
    func load() -> [WatchEnvelope: Date] { [:] }
    func save(_ pending: [WatchEnvelope: Date]) {}
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func row(_ title: String) -> WatchSnapshotRow {
    WatchSnapshotRow(item: WidgetItem(id: "apple-\(title)", title: title, isReminder: true, isAllDay: false,
                                      start: t0, end: nil, colorHex: nil, isOverdue: false),
                     reminderIdentifier: title, externalID: nil, occurrence: t0)
}

@MainActor
private func model(_ store: MemoryStore, now: @escaping @Sendable () -> Date = { t0 }) -> WatchAgendaModel {
    WatchAgendaModel(store: store, outbox: WatchOutbox(transport: NullTransport(), pending: NullPending()), now: now)
}

@MainActor
@Suite struct WatchAgendaModelTests {
    @Test func noSnapshotYetIsWaitingForPhone() {
        let m = model(MemoryStore())
        #expect(m.state == .waitingForPhone)
        #expect(m.updatedAt == nil)
    }

    @Test func aStoredSnapshotShowsAtLaunch() {
        let snap = WatchSnapshot(generatedAt: t0, state: .items, rows: [row("a")])
        let m = model(MemoryStore(snap))
        #expect(m.state == .items([row("a")]))
        #expect(m.updatedAt == t0)
    }

    @Test func receiveReplacesAndSavesTheSnapshot() {
        let store = MemoryStore(WatchSnapshot(generatedAt: t0, state: .items, rows: [row("a")]))
        let m = model(store)
        let next = WatchSnapshot(generatedAt: t0.addingTimeInterval(60), state: .items, rows: [row("b")])
        m.receive(next)
        #expect(m.state == .items([row("b")]))
        #expect(m.updatedAt == next.generatedAt)
        #expect(store.load() == next)
    }

    @Test func anOlderSnapshotDoesNotReplaceANewerOne() {
        let newer = WatchSnapshot(generatedAt: t0, state: .items, rows: [row("new")])
        let store = MemoryStore()
        let m = model(store)
        m.receive(newer)
        m.receive(WatchSnapshot(generatedAt: t0.addingTimeInterval(-60), state: .items, rows: [row("old")]))
        #expect(m.state == .items([row("new")]))
        #expect(m.updatedAt == t0)
        #expect(store.load() == newer)
        let same = WatchSnapshot(generatedAt: t0, state: .items, rows: [row("same")])
        m.receive(same)
        #expect(m.state == .items([row("same")]))
    }

    @Test func eachSnapshotStateMapsToItsModelState() {
        let m = model(MemoryStore())
        let cases: [(WatchSnapshot.State, WatchAgendaModel.State)] = [
            (.accessNeeded("x"), .accessNeeded("x")), (.noSources, .noSources),
            (.empty, .empty), (.failed("boom"), .failed("boom")),
        ]
        for (input, expected) in cases {
            m.receive(WatchSnapshot(generatedAt: t0, state: input, rows: []))
            #expect(m.state == expected)
        }
    }

    @Test func staleIsTrueAfterThreeHours() {
        let box = NowBox(t0)
        let m = model(MemoryStore(WatchSnapshot(generatedAt: t0, state: .empty, rows: [])), now: { box.value })
        #expect(!m.stale())
        box.value = t0.addingTimeInterval(3 * 3600 - 1)
        #expect(!m.stale())
        box.value = t0.addingTimeInterval(3 * 3600 + 1)
        #expect(m.stale())
        #expect(model(MemoryStore()).stale())  // nothing received counts as stale
    }
}

@MainActor
private func completionModel(_ transport: FakeWatchTransport, rows: [WatchSnapshotRow])
    -> (WatchAgendaModel, MemoryStore) {
    let store = MemoryStore(WatchSnapshot(generatedAt: t0, state: .items, rows: rows))
    let m = WatchAgendaModel(store: store, outbox: WatchOutbox(transport: transport, pending: InMemoryPendingStore()),
                             now: { t0 })
    return (m, store)
}

private func event(_ title: String) -> WatchSnapshotRow {
    WatchSnapshotRow(item: WidgetItem(id: "apple-ev", title: title, isReminder: false, isAllDay: false,
                                      start: t0, end: nil, colorHex: nil, isOverdue: false),
                     reminderIdentifier: nil, externalID: nil, occurrence: nil)
}

@MainActor
@Suite struct WatchCompleteTests {
    @Test func completingSubmitsOneCompleteCommandBuiltFromTheRow() async {
        let transport = FakeWatchTransport(reachable: true)
        let (m, _) = completionModel(transport, rows: [row("a")])
        await m.complete(row("a"))
        #expect(transport.sent.map(\.command) == [.complete(identifier: "a", externalID: nil, occurrence: t0)])
    }

    @Test func theRowLeavesTheListAtOnce() async {
        let transport = FakeWatchTransport(reachable: true)
        let (m, _) = completionModel(transport, rows: [row("a"), row("b")])
        await m.complete(row("a"))
        #expect(m.state == .items([row("b")]))
    }

    @Test func aSecondTapWhileInFlightIsIgnored() async {
        let transport = FakeWatchTransport(reachable: false)
        let (m, _) = completionModel(transport, rows: [row("a")])
        await m.complete(row("a"))
        await m.complete(row("a"))
        #expect(transport.queued.count == 1)
    }

    @Test func aFailedReplyPutsTheRowBackAndSetsLastError() async {
        let transport = FakeWatchTransport(reachable: true, result: .success(.failed("Reminder not found")))
        let (m, _) = completionModel(transport, rows: [row("a")])
        await m.complete(row("a"))
        #expect(m.state == .items([row("a")]))
        #expect(m.outbox.statuses.values.contains(.failed("Reminder not found")))
        #expect(m.lastError == "Reminder not found")
    }

    @Test func anUnreachablePhoneKeepsTheRowMarkedWaiting() async {
        let transport = FakeWatchTransport(reachable: false)
        let (m, _) = completionModel(transport, rows: [row("a")])
        await m.complete(row("a"))
        #expect(m.waiting(row("a")))
        #expect(m.waitingRows == [row("a")])
        #expect(m.state == .empty)
    }

    @Test func completingAnEventDoesNothing() async {
        let transport = FakeWatchTransport(reachable: true)
        let (m, _) = completionModel(transport, rows: [event("Meet")])
        await m.complete(event("Meet"))
        #expect(transport.sent.isEmpty && transport.queued.isEmpty)
        #expect(m.state == .items([event("Meet")]))
    }

    @Test func aNewSnapshotDoesNotBringBackARowWaitingToComplete() async {
        let transport = FakeWatchTransport(reachable: false)
        let (m, _) = completionModel(transport, rows: [row("a"), row("b")])
        await m.complete(row("a"))
        m.receive(WatchSnapshot(generatedAt: t0.addingTimeInterval(30), state: .items, rows: [row("a"), row("b")]))
        #expect(m.state == .items([row("b")]))
    }

    @Test func aLateFailureBringsTheRowBack() async throws {
        let transport = FakeWatchTransport(reachable: false)
        let (m, _) = completionModel(transport, rows: [row("a")])
        await m.complete(row("a"))
        let id = try #require(transport.queued.first?.id)
        m.outbox.receive(WatchReplyEnvelope(id: id, reply: .failed("nope")))
        #expect(m.state == .items([row("a")]))
    }
}

/// A transport whose live send suspends until `release` is called.
private final class SuspendingTransport: WatchTransport, @unchecked Sendable {
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

private func snap(_ rows: [WatchSnapshotRow], _ dt: TimeInterval) -> WatchSnapshot {
    WatchSnapshot(generatedAt: t0.addingTimeInterval(dt), state: .items, rows: rows)
}

@MainActor
@Suite struct WatchCompleteFixTests {
    @Test func outcomeIsPerCall() async {
        let live = FakeWatchTransport(reachable: true)
        let (m, _) = completionModel(live, rows: [row("a")])
        #expect(await m.complete(row("a")) == .sent)
        let off = FakeWatchTransport(reachable: false)
        let (m2, _) = completionModel(off, rows: [row("a"), event("e")])
        #expect(await m2.complete(row("a")) == .queued)
        #expect(await m2.complete(row("a")) == .ignored)
        #expect(await m2.complete(event("e")) == .ignored)
        let bad = FakeWatchTransport(reachable: true, result: .success(.failed("boom")))
        let (m3, _) = completionModel(bad, rows: [row("a")])
        #expect(await m3.complete(row("a")) == .failed("boom"))
    }

    @Test func anUnrelatedEarlierFailureDoesNotMakeALaterCompletionFail() async {
        let transport = FakeWatchTransport(reachable: true, result: .success(.failed("boom")))
        let (m, _) = completionModel(transport, rows: [row("a"), row("b")])
        #expect(await m.complete(row("a")) == .failed("boom"))
        transport.result = .success(.done(notice: "ok", warning: nil))
        #expect(await m.complete(row("b")) == .sent)
    }

    @Test func aFailedRowThatLeavesTheSnapshotClearsTheError() async {
        let transport = FakeWatchTransport(reachable: true, result: .success(.failed("boom")))
        let (m, _) = completionModel(transport, rows: [row("a"), row("b")])
        _ = await m.complete(row("a"))
        #expect(m.lastError == "boom")
        m.receive(snap([row("b")], 30))
        #expect(m.lastError == nil)
    }

    @Test func aSecondTapDuringASuspendedLiveSendIsIgnored() async {
        let transport = SuspendingTransport()
        let (m, _) = completionModel(FakeWatchTransport(reachable: true), rows: [])
        let model = WatchAgendaModel(store: MemoryStore(snap([row("a")], 0)),
                                     outbox: WatchOutbox(transport: transport, pending: InMemoryPendingStore()), now: { t0 })
        _ = m
        let first = Task { await model.complete(row("a")) }
        while transport.sends == 0 { await Task.yield() }
        #expect(await model.complete(row("a")) == .ignored)
        transport.release(.done(notice: "ok", warning: nil))
        #expect(await first.value == .sent)
        #expect(transport.sends == 1)
    }

    @Test func aSnapshotBeforeTheDoneReplyKeepsTheRowHidden() async {
        let transport = SuspendingTransport()
        let model = WatchAgendaModel(store: MemoryStore(snap([row("a")], 0)),
                                     outbox: WatchOutbox(transport: transport, pending: InMemoryPendingStore()), now: { t0 })
        let first = Task { await model.complete(row("a")) }
        while transport.sends == 0 { await Task.yield() }
        model.receive(snap([row("a")], 30))
        #expect(model.state == .empty)
        transport.release(.done(notice: "ok", warning: nil))
        _ = await first.value
        #expect(model.state == .empty)
    }

    @Test func doneThenASnapshotDroppingTheRowThenListingItAgainShowsIt() async {
        let transport = FakeWatchTransport(reachable: true)
        let (m, _) = completionModel(transport, rows: [row("a"), row("b")])
        _ = await m.complete(row("a"))
        m.receive(snap([row("b")], 30))
        m.receive(snap([row("a"), row("b")], 60))
        #expect(m.state == .items([row("a"), row("b")]))
    }

    @Test func aReopenedRowListedByEverySnapshotIsNotHiddenForever() async {
        let transport = FakeWatchTransport(reachable: true)
        let (m, _) = completionModel(transport, rows: [row("a"), row("b")])
        _ = await m.complete(row("a"))
        m.receive(snap([row("a"), row("b")], 30))  // stale generation
        m.receive(snap([row("a"), row("b")], 60))
        #expect(m.state == .items([row("a"), row("b")]))
    }

    @Test func theNextOccurrenceOfARepeatingReminderShowsAfterCompletion() async {
        let transport = FakeWatchTransport(reachable: true)
        let (m, _) = completionModel(transport, rows: [row("a")])
        _ = await m.complete(row("a"))
        let next = WatchSnapshotRow(item: row("a").item, reminderIdentifier: "a", externalID: nil,
                                    occurrence: t0.addingTimeInterval(86_400))
        m.receive(snap([next], 30))
        #expect(m.state == .items([next]))
    }

    @Test func waitingSurvivesARelaunch() async {
        let transport = FakeWatchTransport(reachable: false)
        let pending = InMemoryPendingStore()
        let store = MemoryStore(snap([row("a"), row("b")], 0))
        let first = WatchAgendaModel(store: store, outbox: WatchOutbox(transport: transport, pending: pending), now: { t0 })
        _ = await first.complete(row("a"))
        let again = FakeWatchTransport(reachable: false)
        let relaunched = WatchAgendaModel(store: store, outbox: WatchOutbox(transport: again, pending: pending), now: { t0 })
        #expect(relaunched.state == .items([row("b")]))
        #expect(relaunched.waitingRows == [row("a")])
        #expect(relaunched.waiting(row("a")))
        #expect(await relaunched.complete(row("a")) == .ignored)
        #expect(again.queued.isEmpty && again.sent.isEmpty)
    }
}

private final class NowBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Date
    init(_ v: Date) { _value = v }
    var value: Date { get { lock.withLock { _value } } set { lock.withLock { _value = newValue } } }
}
