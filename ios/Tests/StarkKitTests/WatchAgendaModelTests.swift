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

private final class NowBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Date
    init(_ v: Date) { _value = v }
    var value: Date { get { lock.withLock { _value } } set { lock.withLock { _value = newValue } } }
}
