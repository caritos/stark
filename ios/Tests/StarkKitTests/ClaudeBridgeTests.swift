import Testing
import Foundation
@testable import StarkKit

@Suite("ClaudeBridge")
struct ClaudeBridgeTests {
    private let secret = Data(repeating: 7, count: 32)
    private let now = DateMath.date(from: "2026-09-01")

    @MainActor
    private struct Rig {
        let bridge: ClaudeBridge
        let store: PlannerStore
        let root: URL
        let replay: BridgeReplayGuard
    }

    @MainActor
    private func rig(secret: Data? = Data(repeating: 7, count: 32), secrets: SecretStore? = nil) -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = PlannerFile(directory: root.appendingPathComponent("docs"), pendingDirectory: root.appendingPathComponent("pending"))
        let store = PlannerStore(file: file)
        let range = AgendaWindow.loadRange(around: now)
        store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
        let clock = now
        let replay = BridgeReplayGuard(store: InMemoryReplayStore(), now: { clock })
        let bridge = ClaudeBridge(store: store, secrets: secrets ?? InMemorySecretStore(initial: secret), replay: replay)
        return Rig(bridge: bridge, store: store, root: root, replay: replay)
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

    @Test("a valid batch is added with the label token once per item")
    @MainActor func valid() throws {
        let r = rig()
        let out = r.bridge.handle(try url(batch()))
        #expect(out == .added(count: 2, label: "swift-course"))
        #expect(r.store.reminders.count == 2)
        for rem in r.store.reminders {
            let words = (rem.notes ?? "").split(whereSeparator: { $0.isWhitespace })
            #expect(words.filter { $0 == "%swift-course" }.count == 1)
        }
    }

    @Test("the same URL again is already added")
    @MainActor func duplicate() throws {
        let r = rig()
        let u = try url(batch())
        _ = r.bridge.handle(u)
        #expect(r.bridge.handle(u) == .alreadyAdded)
        #expect(r.store.reminders.count == 2)
    }

    @Test("a new batch id whose items are all stored is already added and recorded")
    @MainActor func allPresent() throws {
        let r = rig()
        _ = r.bridge.handle(try url(batch(id: "b1")))
        let again = batch(id: "b2")
        #expect(r.bridge.handle(try url(again)) == .alreadyAdded)
        #expect(r.replay.check(again) == .duplicate)
        #expect(r.store.reminders.count == 2)
    }

    @Test("unsigned, mis-signed, unpaired, tampered, wrong host, garbage and truncated input is ignored")
    @MainActor func ignored() throws {
        let good = try url(batch())
        let r = rig()
        #expect(r.bridge.handle(try url(batch(), secret: Data(repeating: 9, count: 32))) == .ignored)

        let unpaired = rig(secret: nil)
        #expect(unpaired.bridge.handle(good) == .ignored)

        let payload = try BridgeCodec.encode(batch())
        var bad = payload
        bad[bad.count / 2] ^= 0x01
        let sig = BridgeAuth.sign(payload, secret: secret)
        #expect(r.bridge.handle(BridgeCodec.url(payload: bad, signature: sig)) == .ignored)

        let wrongHost = URL(string: good.absoluteString.replacingOccurrences(of: "stark://add", with: "stark://evil"))!
        #expect(r.bridge.handle(wrongHost) == .ignored)
        #expect(r.bridge.handle(URL(string: "stark://add?batch=!!!&sig=@@@")!) == .ignored)
        #expect(r.bridge.handle(URL(string: String(good.absoluteString.dropLast(10)))!) == .ignored)
        #expect(r.store.reminders.isEmpty)
    }

    @Test("a throwing secret store is ignored, not a crash")
    @MainActor func throwingSecret() throws {
        struct Boom: SecretStore {
            func read() throws -> Data? { throw KeychainError(status: -25308) }
            func write(_ secret: Data) throws {}
            func delete() throws {}
        }
        let r = rig(secrets: Boom())
        #expect(r.bridge.handle(try url(batch())) == .ignored)
        #expect(r.store.reminders.isEmpty)
    }

    @Test("an oversized payload is ignored even when correctly signed")
    @MainActor func oversized() throws {
        let r = rig()
        let payload = Data(repeating: 1, count: BridgeCodec.maxEncodedBytes * 3 / 4 + 1)
        let u = BridgeCodec.url(payload: payload, signature: BridgeAuth.sign(payload, secret: secret))
        #expect(r.bridge.handle(u) == .ignored)
    }

    @Test("a signed payload that is not a batch is rejected as unreadable")
    @MainActor func signedGarbage() throws {
        let r = rig()
        let payload = Data("not zlib".utf8)
        let u = BridgeCodec.url(payload: payload, signature: BridgeAuth.sign(payload, secret: secret))
        #expect(r.bridge.handle(u) == .rejected("Couldn't read the request"))
    }

    @Test("expired and future batches are rejected with a clock message")
    @MainActor func clocks() throws {
        let r = rig()
        for offset in [-3600.0, 300.0] {
            let out = r.bridge.handle(try url(batch(id: "c\(Int(offset))", issuedAt: now.addingTimeInterval(offset))))
            guard case .rejected(let text) = out else { Issue.record("expected rejected, got \(out)"); continue }
            #expect(text.contains("Mac") && text.contains("phone") && text.contains("clock"))
        }
        #expect(r.store.reminders.isEmpty)
    }

    @Test("a batch with one invalid item is rejected and adds nothing")
    @MainActor func invalidItem() throws {
        let r = rig()
        var list = items()
        list[1].title = "   "
        let out = r.bridge.handle(try url(batch(items: list)))
        #expect(out == .rejected(BridgeError.emptyTitle(id: "i1").description))
        #expect(r.store.reminders.isEmpty)
    }

    @Test("an unreadable month rejects, adds nothing, is not recorded; a resend after the fix succeeds")
    @MainActor func unreadableMonth() throws {
        let r = rig()
        let docs = r.root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let monthFile = docs.appendingPathComponent("2028-01.ics")
        try Data([0xFF, 0xFE, 0xC0, 0x80]).write(to: monthFile)
        let b = batch(items: items() + [BridgeItem(id: "far", kind: .reminder, title: "Far", start: "2028-01-10T09:00")])
        let out = r.bridge.handle(try url(b))
        guard case .rejected(let text) = out else { Issue.record("expected rejected"); return }
        #expect(text.contains("2028-01.ics"))
        #expect(r.store.reminders.isEmpty)
        #expect(r.replay.check(b) == .accept)

        try FileManager.default.removeItem(at: monthFile)
        #expect(r.bridge.handle(try url(b)) == .added(count: 3, label: "swift-course"))
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
