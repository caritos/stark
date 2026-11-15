// ios/Tests/StarkKitTests/LatestReloadGateTests.swift
import Testing
import Foundation
@testable import StarkKit

/// Fetches that stay open until the test releases them.
private actor Holds {
    struct Failure: Error {}
    private var waiting: [String: CheckedContinuation<String, Error>] = [:]
    private(set) var started: [String] = []

    func fetch(_ name: String) async throws -> String {
        started.append(name)
        return try await withCheckedThrowingContinuation { waiting[name] = $0 }
    }

    func isWaiting(_ name: String) -> Bool { waiting[name] != nil }

    func release(_ name: String, failing: Bool = false) {
        let continuation = waiting.removeValue(forKey: name)
        if failing { continuation?.resume(throwing: Failure()) } else { continuation?.resume(returning: name) }
    }
}

@MainActor
private final class Log {
    var events: [String] = []
}

@MainActor
@Suite("LatestReloadGate")
struct LatestReloadGateTests {
    private func until(_ condition: () async -> Bool) async {
        for _ in 0..<10_000 {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("condition never became true")
    }

    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    private func start(_ name: String, gate: LatestReloadGate, holds: Holds, log: Log) -> Task<Void, Never> {
        Task { @MainActor in
            await gate.run(active: true,
                           fetch: { try await holds.fetch(name) },
                           apply: { log.events.append("applied \($0)") },
                           failed: { _ in log.events.append("failed") },
                           clear: { log.events.append("cleared") })
            log.events.append("\(name) returned")
        }
    }

    @Test func supersededCallerWaitsUntilTheNewestResultIsApplied() async {
        let gate = LatestReloadGate()
        let holds = Holds()
        let log = Log()
        let a = start("A", gate: gate, holds: holds, log: log)
        await until { await holds.isWaiting("A") }
        let b = start("B", gate: gate, holds: holds, log: log)
        await until { await holds.isWaiting("B") }

        await holds.release("A")
        await settle()
        // A's own fetch is done, but B (newer) has not landed: A must still be waiting, and
        // A's stale result must never be applied.
        #expect(log.events.isEmpty)

        await holds.release("B")
        await a.value
        await b.value
        #expect(log.events.first == "applied B")
        #expect(!log.events.contains("applied A"))
        #expect(Set(log.events.dropFirst()) == ["A returned", "B returned"])
    }

    @Test func failingNewestFetchLetsTheWaiterReturn() async {
        let gate = LatestReloadGate()
        let holds = Holds()
        let log = Log()
        let a = start("A", gate: gate, holds: holds, log: log)
        await until { await holds.isWaiting("A") }
        let b = start("B", gate: gate, holds: holds, log: log)
        await until { await holds.isWaiting("B") }

        await holds.release("A")
        await holds.release("B", failing: true)
        await a.value
        await b.value
        #expect(!log.events.contains("applied A"))
        #expect(log.events.contains("failed"))
        #expect(log.events.contains("A returned"))
        #expect(log.events.contains("B returned"))
    }

    /// The app keeps the previous snapshot when a fetch fails (e.g. EventKit returning no reminder
    /// list): a throwing fetch must report `failed` and neither apply nor clear.
    @Test func failingFetchNeitherAppliesNorClears() async {
        let gate = LatestReloadGate()
        let holds = Holds()
        let log = Log()
        let a = start("A", gate: gate, holds: holds, log: log)
        await until { await holds.isWaiting("A") }
        await holds.release("A", failing: true)
        await a.value
        #expect(log.events == ["failed", "A returned"])
    }

    @Test func inactiveReturnsAtOnceWithoutFetchingAndClears() async {
        let gate = LatestReloadGate()
        let holds = Holds()
        let log = Log()
        await gate.run(active: false,
                       fetch: { try await holds.fetch("X") },
                       apply: { log.events.append("applied \($0)") },
                       failed: { _ in log.events.append("failed") },
                       clear: { log.events.append("cleared") })
        #expect(log.events == ["cleared"])
        #expect(await holds.started.isEmpty)
    }

    @Test func goingInactiveDropsAnInFlightResultAndReleasesItsWaiter() async {
        let gate = LatestReloadGate()
        let holds = Holds()
        let log = Log()
        let a = start("A", gate: gate, holds: holds, log: log)
        await until { await holds.isWaiting("A") }
        await gate.run(active: false, fetch: { "never" }, apply: { _ in }, failed: { _ in },
                       clear: { log.events.append("cleared") })
        await holds.release("A")
        await a.value
        #expect(log.events == ["cleared", "A returned"])
    }

    @Test func waiterFollowsAtMostMaxFollowsNewerReloads() async {
        let gate = LatestReloadGate(maxFollows: 1)
        let holds = Holds()
        let log = Log()
        let a = start("A", gate: gate, holds: holds, log: log)
        await until { await holds.isWaiting("A") }
        let b = start("B", gate: gate, holds: holds, log: log)
        await until { await holds.isWaiting("B") }
        await holds.release("A")
        await settle()
        // A now follows B. C arrives while A waits; A has used its one follow on B.
        let c = start("C", gate: gate, holds: holds, log: log)
        await until { await holds.isWaiting("C") }
        await holds.release("B")
        await a.value
        #expect(log.events.contains("A returned"))
        #expect(!log.events.contains("C returned"))
        await holds.release("C")
        await b.value
        await c.value
        #expect(log.events.contains("applied C"))
        #expect(!log.events.contains("applied A"))
        #expect(!log.events.contains("applied B"))
    }
}
