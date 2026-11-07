import Foundation
import Testing
import StarkKit
@testable import StarkClaudeCore

@Suite struct PairCommandTests {
    @Test func storesAValidSecret() throws {
        let store = InMemorySecretStore()
        let secret = BridgeAuth.newSecret()
        try PairCommand(secrets: store).run(secretText: "  " + BridgeAuth.displayString(for: secret) + "\n")
        #expect(try store.read() == secret)
    }
    @Test func rejectsGarbageWithoutWritingOrEchoing() throws {
        let store = InMemorySecretStore()
        do { try PairCommand(secrets: store).run(secretText: "hunter2-not-a-secret"); Issue.record("expected throw") }
        catch { #expect(!"\(error)".contains("hunter2")) }
        #expect(try store.read() == nil)
    }
    @Test func rejectsWrongLengthSecret() throws {
        let store = InMemorySecretStore()
        let short = BridgeAuth.displayString(for: Data(repeating: 1, count: 16))
        do { try PairCommand(secrets: store).run(secretText: short); Issue.record("expected throw") }
        catch { #expect(!"\(error)".contains(short)) }
        #expect(try store.read() == nil)
    }
}
