import Foundation
import Testing
@testable import StarkKit

private struct StoreFailure: Error {}

private final class ThrowingReadStore: SecretStore, @unchecked Sendable {
    var writes = 0
    func read() throws -> Data? { throw StoreFailure() }
    func write(_ secret: Data) throws { writes += 1 }
    func delete() throws {}
}

@Suite struct BridgeAuthTests {
    let secret = Data((0..<32).map { UInt8($0) })
    let payload = Data("hello bridge".utf8)

    @Test func signVerifyRoundTrip() {
        let sig = BridgeAuth.sign(payload, secret: secret)
        #expect(sig.count == 32)
        #expect(BridgeAuth.verify(payload: payload, signature: sig, secret: secret))
    }

    @Test func tamperingFails() {
        let sig = BridgeAuth.sign(payload, secret: secret)
        var p = payload; p[0] ^= 1
        var s = sig; s[5] ^= 1
        #expect(!BridgeAuth.verify(payload: p, signature: sig, secret: secret))
        #expect(!BridgeAuth.verify(payload: payload, signature: s, secret: secret))
        #expect(!BridgeAuth.verify(payload: payload, signature: sig, secret: BridgeAuth.newSecret()))
    }

    @Test func wrongLengthSignaturesFailWithoutTrapping() {
        let sig = BridgeAuth.sign(payload, secret: secret)
        for bad in [Data(), sig.prefix(31), sig + [0], Data(repeating: 0, count: 64)] {
            #expect(!BridgeAuth.verify(payload: payload, signature: Data(bad), secret: secret))
        }
    }

    @Test func newSecretIs32RandomBytes() {
        let a = BridgeAuth.newSecret(), b = BridgeAuth.newSecret()
        #expect(a.count == 32)
        #expect(a != b)
    }

    @Test func displayRoundTrip() {
        let text = BridgeAuth.displayString(for: secret)
        #expect(!text.contains("="))
        #expect(BridgeAuth.secret(fromDisplay: text) == secret)
        #expect(BridgeAuth.secret(fromDisplay: "  \n" + text + " \t\n") == secret)
    }

    @Test func displayRejectsBadInput() {
        #expect(BridgeAuth.secret(fromDisplay: "") == nil)
        #expect(BridgeAuth.secret(fromDisplay: "!!!not base64!!!") == nil)
        #expect(BridgeAuth.secret(fromDisplay: BridgeCodec.base64URL(Data(repeating: 1, count: 31))) == nil)
        #expect(BridgeAuth.secret(fromDisplay: BridgeCodec.base64URL(Data(repeating: 1, count: 33))) == nil)
    }

    @Test func ensureSecretIsStable() throws {
        let store = InMemorySecretStore()
        let first = try BridgePairing.ensureSecret(in: store)
        #expect(first.count == 32)
        #expect(try BridgePairing.ensureSecret(in: store) == first)
        #expect(try store.read() == first)
    }

    @Test func resetReplaces() throws {
        let store = InMemorySecretStore()
        let first = try BridgePairing.ensureSecret(in: store)
        let second = try BridgePairing.reset(in: store)
        #expect(second != first)
        #expect(try BridgePairing.ensureSecret(in: store) == second)
    }

    @Test func readFailureIsThrownAndNothingWritten() {
        let store = ThrowingReadStore()
        #expect(throws: StoreFailure.self) { try BridgePairing.ensureSecret(in: store) }
        #expect(store.writes == 0)
    }

    @Test func inMemoryDeleteAndInitial() throws {
        let store = InMemorySecretStore(initial: secret)
        #expect(try store.read() == secret)
        try store.delete()
        #expect(try store.read() == nil)
        try store.delete()
    }

    @Test func keychainErrorDescriptionHasStatusOnly() {
        let e = KeychainError(status: -25300)
        #expect(e == KeychainError(status: -25300))
        #expect(e.description.contains("-25300"))
    }
}
