import Testing
import Foundation
@testable import StarkKit

@Suite("ClaudeBridge")
struct ClaudeBridgeTests {
    private let secret = Data(repeating: 7, count: 32)
    private let now = DateMath.date(from: "2026-09-01")

    static let calendars = [
        AppleCalendarInfo(id: "cal", title: "Home", accountName: "iCloud", colorHex: nil, isReminderList: false),
        AppleCalendarInfo(id: "list", title: "Tasks", accountName: "iCloud", colorHex: nil, isReminderList: true),
    ]

    @MainActor
    private final class Destinations: DefaultDestinations {
        var calendarID: String?
        var listID: String?
        init(calendarID: String?, listID: String?) { self.calendarID = calendarID; self.listID = listID }
    }

    @MainActor
    private final class Access { var granted = true }

    private struct WriteFailed: Error {}

    /// Sidecar writer that can be told to fail (the ledger write after a successful commit).
    private final class Writer: @unchecked Sendable {
        let lock = NSLock()
        var fail = false
        func write(_ data: Data, _ url: URL) throws {
            lock.lock(); let fail = self.fail; lock.unlock()
            if fail { throw WriteFailed() }
            try ItemSidecar.atomicWriter(data, url)
        }
    }

    @MainActor
    private final class Rig {
        let bridge: ClaudeBridge
        let repository: FakeItemRepository
        let sidecar: ItemSidecar
        let sidecarURL: URL
        let root: URL
        let replay: BridgeReplayGuard
        let destinations: Destinations
        let writer: Writer
        let access: Access
        init(bridge: ClaudeBridge, repository: FakeItemRepository, sidecar: ItemSidecar, sidecarURL: URL, root: URL,
             replay: BridgeReplayGuard, destinations: Destinations, writer: Writer, access: Access) {
            self.bridge = bridge; self.repository = repository; self.sidecar = sidecar; self.sidecarURL = sidecarURL
            self.root = root; self.replay = replay; self.destinations = destinations; self.writer = writer
            self.access = access
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        var ledger: [String: String] { get async throws { try await sidecar.load().bridgeLedger } }
        var reminders: [Reminder] { get async { await repository.allReminders } }
        var count: Int { get async { await repository.itemCount } }
    }

    @MainActor
    private func rig(secret: Data? = Data(repeating: 7, count: 32), secrets: SecretStore? = nil,
                     calendarID: String? = "cal", listID: String? = "list") -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sidecarURL = root.appendingPathComponent("sidecar.json")
        let writer = Writer()
        let sidecar = ItemSidecar(fileURL: sidecarURL, writer: { try writer.write($0, $1) })
        let repository = FakeItemRepository(calendars: Self.calendars, assignsExternalIDs: true)
        let clock = now
        let replay = BridgeReplayGuard(store: InMemoryReplayStore(), now: { clock })
        let destinations = Destinations(calendarID: calendarID, listID: listID)
        let access = Access()
        let bridge = ClaudeBridge(repository: repository, sidecar: sidecar, destinations: destinations,
                                  hasAccess: { access.granted },
                                  secrets: secrets ?? InMemorySecretStore(initial: secret), replay: replay)
        return Rig(bridge: bridge, repository: repository, sidecar: sidecar, sidecarURL: sidecarURL, root: root,
                   replay: replay, destinations: destinations, writer: writer, access: access)
    }

    private func items(_ n: Int = 2, start: String = "2026-09-17T09:00") -> [BridgeItem] {
        (0..<n).map { BridgeItem(id: "i\($0)", kind: .reminder, title: "Lesson \($0)", start: start) }
    }

    private func batch(id: String = "b1", issuedAt: Date? = nil, label: String? = "swift-course", items: [BridgeItem]? = nil) -> BridgeBatch {
        BridgeBatch(batch: id, issuedAt: (issuedAt ?? now).timeIntervalSince1970, label: label, items: items ?? self.items())
    }

    private func url(_ b: BridgeBatch, secret s: Data? = nil) throws -> URL {
        let payload = try BridgeCodec.encode(b)
        return BridgeCodec.url(payload: payload, signature: BridgeAuth.sign(payload, secret: s ?? secret))
    }

    // MARK: Adding to Apple

    @Test("a valid batch is added to Apple with the label token once per item, and ledgered")
    @MainActor func valid() async throws {
        let r = rig()
        let out = await r.bridge.handle(try url(batch()))
        #expect(out == .added(count: 2, label: "swift-course"))
        let reminders = await r.reminders
        #expect(reminders.count == 2)
        for rem in reminders {
            let words = (rem.notes ?? "").split(whereSeparator: { $0.isWhitespace })
            #expect(words.filter { $0 == "%swift-course" }.count == 1)
        }
        let ledger = try await r.ledger
        #expect(Set(ledger.keys) == ["i0", "i1"])
        #expect(Set(ledger.values) == Set(reminders.map(\.id)))
        // External ids go along so the ledger survives an identifier change.
        let data = try await r.sidecar.load()
        for id in ledger.values { #expect(data.externalIDs[id] == "ext-\(id)") }
    }

    @Test("events go to the default calendar, reminders to the default list, each ledgered to its own item")
    @MainActor func mixed() async throws {
        let r = rig()
        let list = [BridgeItem(id: "ev", kind: .event, title: "Class", start: "2026-09-17T19:00", end: "20:00"),
                    BridgeItem(id: "rem", kind: .reminder, title: "Read", start: "2026-09-18")]
        #expect(await r.bridge.handle(try url(batch(items: list))) == .added(count: 2, label: "swift-course"))
        let ledger = try await r.ledger
        let event = try #require(try await r.repository.details(AppleItemRef(kind: .event, identifier: try #require(ledger["ev"]))))
        #expect(event.event?.title == "Class")
        #expect(event.calendarID == "cal")
        let reminder = try #require(try await r.repository.details(AppleItemRef(kind: .reminder, identifier: try #require(ledger["rem"]))))
        #expect(reminder.reminder?.title == "Read")
        #expect(reminder.calendarID == "list")
        // A date-only `start` is a date-only reminder.
        #expect(reminder.dueHasTime == false)
    }

    @Test("the same URL again is already added and adds nothing")
    @MainActor func duplicate() async throws {
        let r = rig()
        let u = try url(batch())
        _ = await r.bridge.handle(u)
        #expect(await r.bridge.handle(u) == .alreadyAdded)
        #expect(await r.count == 2)
    }

    @Test("the same file re-sent as a new batch is already added (ledger) and the batch is recorded")
    @MainActor func allPresent() async throws {
        let r = rig()
        _ = await r.bridge.handle(try url(batch(id: "b1")))
        let again = batch(id: "b2")
        #expect(await r.bridge.handle(try url(again)) == .alreadyAdded)
        #expect(r.replay.check(again) == .duplicate)
        #expect(await r.count == 2)
    }

    @Test("a partial earlier send then the full file adds only the missing items")
    @MainActor func partialResend() async throws {
        let r = rig()
        let all = items(5)
        #expect(await r.bridge.handle(try url(batch(id: "first", items: Array(all.prefix(2))))) == .added(count: 2, label: "swift-course"))
        #expect(await r.bridge.handle(try url(batch(id: "full", items: all))) == .added(count: 3, label: "swift-course"))
        #expect(await r.count == 5)
        #expect(Set(try await r.ledger.keys) == ["i0", "i1", "i2", "i3", "i4"])
        #expect(Set(await r.reminders.map(\.title)).count == 5)
    }

    @Test("an item deleted in Apple stays deleted when the file is sent again")
    @MainActor func deletedInAppleStaysDeleted() async throws {
        let r = rig()
        _ = await r.bridge.handle(try url(batch(id: "b1")))
        let gone = try #require(try await r.ledger["i0"])
        try await r.repository.delete(AppleItemRef(kind: .reminder, identifier: gone))
        #expect(await r.count == 1)
        #expect(await r.bridge.handle(try url(batch(id: "b2"))) == .alreadyAdded)
        #expect(await r.count == 1)
    }

    @Test("a failed save adds nothing, records nothing, and the same URL works on retry")
    @MainActor func saveFailureThenRetry() async throws {
        let r = rig()
        let u = try url(batch())
        await r.repository.failNext("disk full")
        let out = await r.bridge.handle(u)
        guard case .rejected(let text) = out else { Issue.record("expected rejected, got \(out)"); return }
        #expect(text.contains("nothing was added"))
        #expect(await r.count == 0)
        #expect(try await r.ledger.isEmpty)
        #expect(r.replay.check(batch()) == .accept)

        #expect(await r.bridge.handle(u) == .added(count: 2, label: "swift-course"))
        #expect(await r.count == 2)
        #expect(try await r.ledger.count == 2)
    }

    @Test("a ledger write that fails after the commit still reports the items and records the batch")
    @MainActor func ledgerWriteFailsAfterCommit() async throws {
        let r = rig()
        r.writer.fail = true
        let b = batch()
        #expect(await r.bridge.handle(try url(b)) == .added(count: 2, label: "swift-course"))
        #expect(await r.count == 2)
        // The exact same URL is still caught by the replay guard.
        #expect(r.replay.check(b) == .duplicate)
        #expect(await r.bridge.handle(try url(b)) == .alreadyAdded)
        #expect(await r.count == 2)
    }

    @Test("an unreadable sidecar rejects and adds nothing")
    @MainActor func unreadableSidecar() async throws {
        let r = rig()
        try FileManager.default.createDirectory(at: r.root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: r.sidecarURL)
        let b = batch()
        let out = await r.bridge.handle(try url(b))
        guard case .rejected(let text) = out else { Issue.record("expected rejected, got \(out)"); return }
        #expect(text.contains("nothing was added"))
        #expect(await r.count == 0)
        #expect(r.replay.check(b) == .accept)
    }

    @Test("two sends of the same URL at once add the items once")
    @MainActor func concurrentSends() async throws {
        let r = rig()
        let u = try url(batch())
        async let first = r.bridge.handle(u)
        async let second = r.bridge.handle(u)
        let outcomes = await [first, second]
        #expect(outcomes.filter { $0 == .alreadyAdded }.count == 1)
        #expect(outcomes.contains(.added(count: 2, label: "swift-course")))
        #expect(await r.count == 2)
    }

    // MARK: Destination and access

    @Test("no writable default list rejects a reminder batch with the reason and writes nothing")
    @MainActor func noList() async throws {
        let r = rig(listID: nil)
        let b = batch()
        #expect(await r.bridge.handle(try url(b))
                == .rejected(DefaultDestination.problem(calendarID: "cal", listID: nil)!))
        #expect(await r.count == 0)
        #expect(try await r.ledger.isEmpty)
        #expect(r.replay.check(b) == .accept)
    }

    @Test("no writable default calendar rejects an event batch; a reminder-only batch still works")
    @MainActor func noCalendar() async throws {
        let r = rig(calendarID: nil)
        let events = [BridgeItem(id: "ev", kind: .event, title: "Class", start: "2026-09-17T19:00")]
        #expect(await r.bridge.handle(try url(batch(id: "e", items: events)))
                == .rejected(DefaultDestination.problem(calendarID: nil, listID: "list")!))
        #expect(await r.count == 0)
        #expect(await r.bridge.handle(try url(batch(id: "r"))) == .added(count: 2, label: "swift-course"))
    }

    @Test("without Calendar and Reminders access the batch is rejected with the reason and not recorded")
    @MainActor func noAccess() async throws {
        let r = rig()
        r.access.granted = false
        let b = batch()
        let out = await r.bridge.handle(try url(b))
        guard case .rejected(let text) = out else { Issue.record("expected rejected, got \(out)"); return }
        #expect(text.hasPrefix("Stark needs Calendar and Reminders access"))
        #expect(await r.count == 0)
        #expect(r.replay.check(b) == .accept)
        r.access.granted = true
        #expect(await r.bridge.handle(try url(b)) == .added(count: 2, label: "swift-course"))
    }

    // MARK: Signature, size, replay, validation (unchanged behaviour)

    @Test("unsigned, mis-signed, unpaired, tampered, wrong host, garbage and truncated input is ignored")
    @MainActor func ignored() async throws {
        let good = try url(batch())
        let r = rig()
        #expect(await r.bridge.handle(try url(batch(), secret: Data(repeating: 9, count: 32))) == .ignored)

        let unpaired = rig(secret: nil)
        #expect(await unpaired.bridge.handle(good) == .ignored)

        let payload = try BridgeCodec.encode(batch())
        var bad = payload
        bad[bad.count / 2] ^= 0x01
        let sig = BridgeAuth.sign(payload, secret: secret)
        #expect(await r.bridge.handle(BridgeCodec.url(payload: bad, signature: sig)) == .ignored)

        let wrongHost = URL(string: good.absoluteString.replacingOccurrences(of: "stark://add", with: "stark://evil"))!
        #expect(await r.bridge.handle(wrongHost) == .ignored)
        #expect(await r.bridge.handle(URL(string: "stark://add?batch=!!!&sig=@@@")!) == .ignored)
        #expect(await r.bridge.handle(URL(string: String(good.absoluteString.dropLast(10)))!) == .ignored)
        #expect(await r.count == 0)
        #expect(await unpaired.count == 0)
    }

    @Test("a throwing secret store is ignored, not a crash")
    @MainActor func throwingSecret() async throws {
        struct Boom: SecretStore {
            func read() throws -> Data? { throw KeychainError(status: -25308) }
            func write(_ secret: Data) throws {}
            func delete() throws {}
        }
        let r = rig(secrets: Boom())
        #expect(await r.bridge.handle(try url(batch())) == .ignored)
        #expect(await r.count == 0)
    }

    @Test("an oversized payload is ignored even when correctly signed")
    @MainActor func oversized() async throws {
        let r = rig()
        let payload = Data(repeating: 1, count: BridgeCodec.maxEncodedBytes * 3 / 4 + 1)
        let u = BridgeCodec.url(payload: payload, signature: BridgeAuth.sign(payload, secret: secret))
        #expect(await r.bridge.handle(u) == .ignored)
    }

    @Test("verify runs before decode: non-zlib payload with the wrong secret is ignored")
    @MainActor func verifyBeforeDecode() async throws {
        let r = rig()
        let payload = Data("not zlib".utf8)
        let u = BridgeCodec.url(payload: payload, signature: BridgeAuth.sign(payload, secret: Data(repeating: 9, count: 32)))
        #expect(await r.bridge.handle(u) == .ignored)
    }

    @Test("the size guard runs before the secret store is read")
    @MainActor func sizeGuardBeforeKeychain() async throws {
        final class Counting: SecretStore, @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            var reads: Int { lock.lock(); defer { lock.unlock() }; return n }
            func read() throws -> Data? { lock.lock(); n += 1; lock.unlock(); throw KeychainError(status: -1) }
            func write(_ secret: Data) throws {}
            func delete() throws {}
        }
        let counting = Counting()
        let r = rig(secrets: counting)
        let payload = Data(repeating: 1, count: BridgeCodec.maxEncodedBytes * 3 / 4 + 1)
        let u = BridgeCodec.url(payload: payload, signature: BridgeAuth.sign(payload, secret: secret))
        #expect(await r.bridge.handle(u) == .ignored)
        #expect(counting.reads == 0)
    }

    @Test("a signed payload that is not a batch is rejected as unreadable")
    @MainActor func signedGarbage() async throws {
        let r = rig()
        let payload = Data("not zlib".utf8)
        let u = BridgeCodec.url(payload: payload, signature: BridgeAuth.sign(payload, secret: secret))
        #expect(await r.bridge.handle(u) == .rejected("Couldn't read the request"))
    }

    @Test("expired and future batches are rejected with a clock message")
    @MainActor func clocks() async throws {
        let r = rig()
        for offset in [-3600.0, 300.0] {
            let out = await r.bridge.handle(try url(batch(id: "c\(Int(offset))", issuedAt: now.addingTimeInterval(offset))))
            guard case .rejected(let text) = out else { Issue.record("expected rejected, got \(out)"); continue }
            #expect(text.contains("Mac") && text.contains("phone") && text.contains("clock"))
        }
        #expect(await r.count == 0)
    }

    @Test("a batch with one invalid item is rejected and adds nothing")
    @MainActor func invalidItem() async throws {
        let r = rig()
        var list = items()
        list[1].title = "   "
        let out = await r.bridge.handle(try url(batch(items: list)))
        #expect(out == .rejected(BridgeError.emptyTitle(id: "i1").description))
        #expect(await r.count == 0)
        #expect(try await r.ledger.isEmpty)
    }

    @Test("notice text")
    func notices() {
        #expect(ClaudeBridge.Outcome.ignored.notice == nil)
        #expect(ClaudeBridge.Outcome.added(count: 6, label: "swift-course").notice == "Added 6 items (swift-course)")
        #expect(ClaudeBridge.Outcome.added(count: 1, label: "x").notice == "Added 1 item (x)")
        #expect(ClaudeBridge.Outcome.added(count: 1, label: nil).notice == "Added 1 item")
        #expect(ClaudeBridge.Outcome.added(count: 3, label: nil).notice == "Added 3 items")
        #expect(ClaudeBridge.Outcome.alreadyAdded.notice == "Already added")
        #expect(ClaudeBridge.Outcome.rejected("Nope").notice == "Nope")
    }
}
