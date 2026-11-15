// ios/Tests/StarkKitTests/PlanCacheStateTests.swift
import Testing
@testable import StarkKit

@Suite("PlanCacheState")
struct PlanCacheStateTests {
    @Test("the planner edits and saves only after Apple plans were read once")
    func editsWaitForTheFirstLoad() {
        var state = PlanCacheState()
        #expect(!state.allowsPlanEdits)
        state.loaded()
        #expect(state.allowsPlanEdits)
    }

    @Test("a failed first read keeps the planner locked and is reported once per run of failures")
    func failureBeforeLoad() {
        var state = PlanCacheState()
        #expect(state.failed("unreadable") == "unreadable")
        #expect(state.failed("unreadable") == nil)
        #expect(state.failed("still unreadable") == nil)
        #expect(!state.allowsPlanEdits)
        #expect(state.failure == "still unreadable")
        state.loaded()
        #expect(state.allowsPlanEdits)
        #expect(state.failure == nil)
    }

    @Test("a failure after a good read is reported again but keeps the last good read usable")
    func failureAfterLoad() {
        var state = PlanCacheState()
        state.loaded()
        #expect(state.failed("gone") == "gone")
        #expect(state.allowsPlanEdits)
    }
}
