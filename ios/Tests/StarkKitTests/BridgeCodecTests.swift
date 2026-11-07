import Foundation
import Testing
@testable import StarkKit

private func item(_ id: String, notes: String? = nil, location: String? = nil) -> BridgeItem {
    BridgeItem(id: id, kind: .reminder, title: "Task \(id)", notes: notes, start: "2026-11-10", location: location)
}

private func sampleBatch(_ items: [BridgeItem] = [item("a")]) -> BridgeBatch {
    BridgeBatch(batch: "b1", issuedAt: 1_700_000_000, label: "proj", items: items)
}

/// Deterministic incompressible-ish text.
private func noise(_ count: Int, seed: UInt64) -> String {
    var s = seed
    let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    var out = ""
    for _ in 0..<count {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        out.append(alphabet[Int((s >> 33) % UInt64(alphabet.count))])
    }
    return out
}

@Test func encodeDecodeRoundTrip() throws {
    let b = sampleBatch([item("a", notes: "hello"), item("b")])
    #expect(try BridgeCodec.decode(BridgeCodec.encode(b)) == b)
}

@Test func base64URLHasNoUnsafeCharactersAndRoundTrips() {
    let data = Data([0xfb, 0xff, 0xfe, 0x00, 0x3e, 0x3f, 0x01])
    let s = BridgeCodec.base64URL(data)
    #expect(!s.contains("+") && !s.contains("/") && !s.contains("="))
    #expect(BridgeCodec.data(fromBase64URL: s) == data)
    #expect(BridgeCodec.data(fromBase64URL: "***") == nil)
    #expect(BridgeCodec.data(fromBase64URL: "a") == nil)
}

@Test func urlRoundTrips() throws {
    let payload = try BridgeCodec.encode(sampleBatch())
    let sig = Data((0..<32).map { UInt8($0 &* 7) })
    let url = BridgeCodec.url(payload: payload, signature: sig)
    #expect(url.scheme == "stark" && url.host == "add")
    let parsed = try #require(BridgeCodec.parse(url))
    #expect(parsed.payload == payload)
    #expect(parsed.signature == sig)
}

@Test func parseRejectsBadURLs() {
    #expect(BridgeCodec.parse(URL(string: "http://add?batch=AA&sig=AA")!) == nil)
    #expect(BridgeCodec.parse(URL(string: "stark://other?batch=AA&sig=AA")!) == nil)
    #expect(BridgeCodec.parse(URL(string: "stark://add?batch=AAAA")!) == nil)
    #expect(BridgeCodec.parse(URL(string: "stark://add?sig=AAAA")!) == nil)
    #expect(BridgeCodec.parse(URL(string: "stark://add?batch=***&sig=AAAA")!) == nil)
    #expect(BridgeCodec.parse(URL(string: "stark://add?batch=AAAA&batch=AAAA&sig=AAAA")!) == nil)
    #expect(BridgeCodec.parse(URL(string: "stark://add?batch=AAAA&sig=AAAA&sig=AAAA")!) == nil)
    #expect(BridgeCodec.parse(URL(string: "stark://add")!) == nil)
}

@Test func decodeGarbageThrowsMalformed() {
    let junk = Data((0..<200).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 5) })
    for data in [junk, Data(), Data([0x78])] {
        #expect(throws: BridgeError.malformed) { try BridgeCodec.decode(data) }
    }
}

@Test func decodeTruncatedPayloadThrowsMalformed() throws {
    let full = try BridgeCodec.encode(sampleBatch([item("a", notes: noise(2000, seed: 1))]))
    let cut = full.prefix(full.count / 2)
    #expect(throws: BridgeError.malformed) { try BridgeCodec.decode(Data(cut)) }
}

@Test func decodeRejectsDecompressionBomb() throws {
    let zeros = Data(count: 2 * 1_048_576)
    let bomb = try (zeros as NSData).compressed(using: .zlib) as Data
    #expect(bomb.count < 10_000)
    #expect(throws: BridgeError.malformed) { try BridgeCodec.decode(bomb) }
}

@Test func splitSmallItemsRespectsItemCap() throws {
    let items = (0..<300).map { item("i\($0)") }
    var n = 0
    let batches = try BridgeCodec.split(items: items, label: "proj", issuedAt: 42) { n += 1; return "id\(n)" }
    #expect(batches.allSatisfy { $0.items.count <= BridgeBatch.maxItems && !$0.items.isEmpty })
    #expect(batches.flatMap(\.items).map(\.id) == items.map(\.id))
    #expect(Set(batches.map(\.batch)).count == batches.count)
    #expect(batches.count == 2)
    #expect(batches.allSatisfy { $0.label == "proj" && $0.issuedAt == 42 })
    for b in batches {
        #expect(BridgeCodec.base64URL(try BridgeCodec.encode(b)).count <= BridgeCodec.maxEncodedBytes)
    }
}

@Test func splitByEncodedSizeKeepsEveryBatchUnderLimit() throws {
    let items = (0..<60).map { item("n\($0)", notes: noise(5000, seed: UInt64($0 + 1))) }
    var n = 0
    let batches = try BridgeCodec.split(items: items, label: nil, issuedAt: 1) { n += 1; return "b\(n)" }
    #expect(batches.count > 3)
    #expect(batches.flatMap(\.items).map(\.id) == items.map(\.id))
    for b in batches {
        #expect(BridgeCodec.base64URL(try BridgeCodec.encode(b)).count <= BridgeCodec.maxEncodedBytes)
    }
}

@Test func splitThrowsForSingleOversizedItem() {
    let big = item("huge", location: noise(80_000, seed: 9))
    #expect(throws: BridgeError.itemTooLarge(id: "huge")) {
        try BridgeCodec.split(items: [item("a"), big], label: nil, issuedAt: 0) { "x\(UUID().uuidString)" }
    }
}

@Test func splitEmptyYieldsNoBatches() throws {
    #expect(try BridgeCodec.split(items: [], label: nil, issuedAt: 0) { "x" }.isEmpty)
}

@Test func parseRejectsOversizeQueryValuesBeforeDecoding() {
    let tooBig = String(repeating: "A", count: BridgeCodec.maxEncodedBytes + 4)
    #expect(BridgeCodec.parse(URL(string: "stark://add?batch=\(tooBig)&sig=AAAA")!) == nil)
    let longSig = String(repeating: "A", count: 49)
    #expect(BridgeCodec.parse(URL(string: "stark://add?batch=AAAA&sig=\(longSig)")!) == nil)
}

@Test func parseAcceptsMaxLengthBatchAndSigOf43() throws {
    let maxBatch = String(repeating: "A", count: BridgeCodec.maxEncodedBytes)
    let sig = String(repeating: "A", count: 43)
    let parsed = try #require(BridgeCodec.parse(URL(string: "stark://add?batch=\(maxBatch)&sig=\(sig)")!))
    #expect(parsed.payload.count == BridgeCodec.maxEncodedBytes * 3 / 4)
}
