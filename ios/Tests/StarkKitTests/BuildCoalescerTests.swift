import Foundation
import Testing
@testable import StarkKit

private actor Probe {
    var started = 0, finished = 0, running = 0, maxRunning = 0
    var gates: [CheckedContinuation<Void, Never>] = []
    func run(gated: Bool) async {
        started += 1; running += 1; maxRunning = max(maxRunning, running)
        if gated { await withCheckedContinuation { gates.append($0) } }
        running -= 1; finished += 1
    }
    func release() { let g = gates; gates = []; g.forEach { $0.resume() } }
}

@Suite struct BuildCoalescerTests {
    private func wait(_ cond: @escaping () async -> Bool) async {
        for _ in 0..<500 { if await cond() { return }; try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func requestsDuringABuildCauseExactlyOneFollowUpAndNeverOverlap() async {
        let probe = Probe()
        let c = BuildCoalescer(delay: .zero) { await probe.run(gated: true) }
        c.request()
        await wait { await probe.started == 1 }
        c.request(); c.request(); c.request()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await probe.started == 1)
        await probe.release()
        await wait { await probe.started == 2 }
        await probe.release()
        await wait { await probe.finished == 2 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await probe.started == 2)
        #expect(await probe.maxRunning == 1)
    }

    @Test func requestsBeforeTheBuildStartsAreOneBuild() async {
        let probe = Probe()
        let c = BuildCoalescer(delay: .milliseconds(100)) { await probe.run(gated: false) }
        c.request(); c.request(); c.request()
        await wait { await probe.finished == 1 }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await probe.started == 1)
    }

    @Test func idleThenRequestRunsAgain() async {
        let probe = Probe()
        let c = BuildCoalescer(delay: .zero) { await probe.run(gated: false) }
        c.request()
        await wait { await probe.finished == 1 }
        c.request()
        await wait { await probe.finished == 2 }
        #expect(await probe.started == 2)
    }
}
