import Foundation
import Testing
@testable import StarkKit

private actor Log {
    var events: [String] = []
    func add(_ e: String) { events.append(e) }
}

private let ok = WatchReply.done(notice: nil, warning: nil)

@Suite struct WatchReplyFirstTests {
    @Test func theReplyIsDeliveredBeforeTheAfterWriteWorkStarts() async {
        let log = Log()
        await WatchReplyFirst.run(
            produce: { await log.add("produce"); return ok },
            deliver: { _ in Task { await log.add("deliver") } },
            afterWrite: { try? await Task.sleep(for: .milliseconds(30)); await log.add("afterWrite") })
        let events = await log.events
        #expect(events == ["produce", "deliver", "afterWrite"])
    }

    @Test func deliverRunsSynchronouslyBeforeAfterWrite() async {
        nonisolated(unsafe) var delivered = false
        nonisolated(unsafe) var deliveredWhenReloadStarted = false
        await WatchReplyFirst.run(
            produce: { ok },
            deliver: { _ in delivered = true },
            afterWrite: { deliveredWhenReloadStarted = delivered })
        #expect(deliveredWhenReloadStarted)
    }

    @Test func aFailedReplyIsDeliveredButDoesNotReload() async {
        nonisolated(unsafe) var reloaded = false
        nonisolated(unsafe) var delivered = false
        await WatchReplyFirst.run(
            produce: { .failed("no") },
            deliver: { _ in delivered = true },
            afterWrite: { reloaded = true })
        #expect(delivered)
        #expect(!reloaded)
    }
}
