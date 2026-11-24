import Foundation
import Testing
@testable import StarkKit

/// A `WatchTransport` that records what it was asked to do and answers live sends as scripted.
final class FakeWatchTransport: WatchTransport, @unchecked Sendable {
    struct Undeliverable: Error {}

    private let lock = NSLock()
    private var _reachable: Bool
    private var _result: Result<WatchReply, Error>
    private var _sent: [WatchEnvelope] = []
    private var _queued: [WatchEnvelope] = []
    private var _replies: [WatchReplyEnvelope] = []

    init(reachable: Bool, result: Result<WatchReply, Error> = .success(.done(notice: "Added", warning: nil))) {
        _reachable = reachable
        _result = result
    }

    var isReachable: Bool {
        get { lock.withLock { _reachable } }
        set { lock.withLock { _reachable = newValue } }
    }
    var result: Result<WatchReply, Error> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }
    var sent: [WatchEnvelope] { lock.withLock { _sent } }
    var queued: [WatchEnvelope] { lock.withLock { _queued } }
    var replies: [WatchReplyEnvelope] { lock.withLock { _replies } }

    func send(_ envelope: WatchEnvelope) async throws -> WatchReply {
        let result = lock.withLock { () -> Result<WatchReply, Error> in
            _sent.append(envelope)
            return _result
        }
        return try result.get()
    }

    func queue(_ envelope: WatchEnvelope) { lock.withLock { _queued.append(envelope) } }
    func reply(_ reply: WatchReplyEnvelope) { lock.withLock { _replies.append(reply) } }
}

/// A `WatchPendingStore` in memory; one instance shared by two outboxes stands for a relaunch.
final class InMemoryPendingStore: WatchPendingStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [WatchEnvelope: Date] = [:]

    func load() -> [WatchEnvelope: Date] { lock.withLock { stored } }
    func save(_ pending: [WatchEnvelope: Date]) { lock.withLock { stored = pending } }
}

/// A clock the test moves.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ now: Date) { _now = now }
    var now: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }
}

@MainActor
@Suite("WatchOutbox")
struct WatchOutboxTests {
    static let start = Date(timeIntervalSinceReferenceDate: 815_000_000)
    static let command = WatchCommand.complete(identifier: "R1", externalID: nil, occurrence: start)

    static func outbox(_ transport: FakeWatchTransport, pending: InMemoryPendingStore = InMemoryPendingStore(),
                       clock: TestClock = TestClock(start)) -> WatchOutbox {
        WatchOutbox(transport: transport, pending: pending, now: { clock.now })
    }

    @Test("reachable sends live and marks done with the reply")
    func reachableSendsLiveAndMarksDoneWithTheReply() async throws {
        let reply = WatchReply.done(notice: "Added to Home · iCloud", warning: nil)
        let transport = FakeWatchTransport(reachable: true, result: .success(reply))
        let pending = InMemoryPendingStore()
        let outbox = Self.outbox(transport, pending: pending)

        let id = try #require(await outbox.submit(Self.command))

        #expect(outbox.statuses[id] == .done(reply))
        #expect(transport.sent.map(\.id) == [id])
        #expect(transport.sent.first?.command == Self.command)
        #expect(transport.sent.first?.sentAt == Self.start)
        #expect(transport.queued.isEmpty)
        #expect(pending.load().isEmpty)
    }

    @Test("unreachable queues and marks waiting; a failed live send queues too")
    func unreachableQueuesAndMarksWaiting() async throws {
        let transport = FakeWatchTransport(reachable: false)
        let pending = InMemoryPendingStore()
        let outbox = Self.outbox(transport, pending: pending)

        let id = try #require(await outbox.submit(Self.command))

        #expect(outbox.statuses[id] == .waiting)
        #expect(transport.sent.isEmpty)
        #expect(transport.queued.map(\.id) == [id])
        #expect(pending.load().keys.map(\.id) == [id])

        transport.isReachable = true
        transport.result = .failure(FakeWatchTransport.Undeliverable())
        let second = try #require(await outbox.submit(Self.command))
        #expect(outbox.statuses[second] == .waiting)
        #expect(transport.sent.map(\.id) == [second])
        #expect(transport.queued.map(\.id) == [id, second])
        #expect(Set(pending.load().keys.map(\.id)) == [id, second])
    }

    @Test("a later reply marks a waiting envelope done")
    func aLaterReplyMarksAWaitingEnvelopeDone() async throws {
        let transport = FakeWatchTransport(reachable: false)
        let pending = InMemoryPendingStore()
        let outbox = Self.outbox(transport, pending: pending)
        let id = try #require(await outbox.submit(Self.command))

        let reply = WatchReply.done(notice: "Added to Inbox · iCloud", warning: DestinationLabel.localOnlyWarning)
        outbox.receive(WatchReplyEnvelope(id: id, reply: reply))

        #expect(outbox.statuses[id] == .done(reply))
        #expect(pending.load().isEmpty)
        // A reply for an id the outbox never sent changes nothing.
        outbox.receive(WatchReplyEnvelope(id: UUID(), reply: reply))
        #expect(outbox.statuses.count == 1)
    }

    @Test("a failed reply marks failed")
    func aFailedReplyMarksFailed() async throws {
        let transport = FakeWatchTransport(reachable: true, result: .success(.failed("disk full")))
        let outbox = Self.outbox(transport)
        let live = try #require(await outbox.submit(Self.command))
        #expect(outbox.statuses[live] == .failed("disk full"))

        transport.isReachable = false
        let queued = try #require(await outbox.submit(Self.command))
        outbox.receive(WatchReplyEnvelope(id: queued, reply: .failed("This item is no longer there.")))
        #expect(outbox.statuses[queued] == .failed("This item is no longer there."))
    }

    @Test("the twenty-first waiting envelope is refused with a visible message")
    func theTwentyFirstWaitingIsRefusedWithAVisibleMessage() async throws {
        let transport = FakeWatchTransport(reachable: false)
        let outbox = Self.outbox(transport)
        for _ in 0..<20 { #expect(await outbox.submit(Self.command) != nil) }
        #expect(outbox.lastError == nil)

        let refused = await outbox.submit(Self.command)

        #expect(refused == nil)
        #expect(outbox.lastError == WatchOutbox.fullMessage)
        #expect(transport.queued.count == 20)
        #expect(outbox.statuses.count == 20)

        // One delivered frees a place, and the next submit clears the message.
        let first = try #require(transport.queued.first)
        outbox.receive(WatchReplyEnvelope(id: first.id, reply: .done(notice: nil, warning: nil)))
        #expect(await outbox.submit(Self.command) != nil)
        #expect(outbox.lastError == nil)
    }

    @Test("a waiting envelope older than seven days becomes Not delivered")
    func aWaitingEnvelopeOlderThanSevenDaysBecomesNotDelivered() async throws {
        let transport = FakeWatchTransport(reachable: false)
        let pending = InMemoryPendingStore()
        let clock = TestClock(Self.start)
        let outbox = Self.outbox(transport, pending: pending, clock: clock)
        let old = try #require(await outbox.submit(Self.command))
        clock.now = Self.start.addingTimeInterval(6 * 24 * 3600)
        let newer = try #require(await outbox.submit(Self.command))

        clock.now = Self.start.addingTimeInterval(7 * 24 * 3600)
        outbox.expireOld()
        #expect(outbox.statuses[old] == .waiting)

        clock.now = Self.start.addingTimeInterval(7 * 24 * 3600 + 1)
        outbox.expireOld()

        #expect(outbox.statuses[old] == .failed(WatchOutbox.notDelivered))
        #expect(outbox.statuses[newer] == .waiting)
        #expect(pending.load().keys.map(\.id) == [newer])
        // A late reply for the expired one still tells the truth.
        outbox.receive(WatchReplyEnvelope(id: old, reply: .done(notice: "Added", warning: nil)))
        #expect(outbox.statuses[old] == .done(.done(notice: "Added", warning: nil)))
    }

    @Test("waiting envelopes survive a relaunch")
    func waitingEnvelopesSurviveARelaunch() async throws {
        let transport = FakeWatchTransport(reachable: false)
        let pending = InMemoryPendingStore()
        let first = Self.outbox(transport, pending: pending)
        let id = try #require(await first.submit(Self.command))

        let relaunched = Self.outbox(transport, pending: pending)

        #expect(relaunched.statuses[id] == .waiting)
        relaunched.receive(WatchReplyEnvelope(id: id, reply: .done(notice: nil, warning: nil)))
        #expect(relaunched.statuses[id] == .done(.done(notice: nil, warning: nil)))
        #expect(pending.load().isEmpty)
    }

    @Test("the UserDefaults pending store round-trips its envelopes")
    func userDefaultsPendingStoreRoundTrips() throws {
        let suite = "WatchOutboxTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsWatchPendingStore(defaults: defaults)
        #expect(store.load().isEmpty)
        let envelope = WatchEnvelope(id: UUID(), sentAt: Self.start, command: Self.command)

        store.save([envelope: Self.start])

        #expect(UserDefaultsWatchPendingStore(defaults: defaults).load() == [envelope: Self.start])
    }
}
