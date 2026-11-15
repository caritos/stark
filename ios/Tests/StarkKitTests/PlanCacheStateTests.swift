// ios/Tests/StarkKitTests/PlanCacheStateTests.swift
import Testing
@testable import StarkKit

@Suite("PlanCacheState")
struct PlanCacheStateTests {
    @Test("the planner edits and saves only after Apple plans were read once")
    func editsWaitForTheFirstLoad() {
        var state = PlanCacheState()
        #expect(!state.allowsPlanEdits)
        #expect(state.plannerNotice == nil)   // still loading: no notice
        state.loaded()
        #expect(state.allowsPlanEdits)
    }

    @Test("a failed first read locks the planner with a notice, reported once per run of failures")
    func failureBeforeLoad() {
        var state = PlanCacheState()
        let notice = "Couldn't read Stark's plan file. Close and reopen the planner to try again."
        #expect(state.failed("unreadable") == notice)
        #expect(state.failed("unreadable") == nil)
        #expect(state.failed("still unreadable") == nil)
        #expect(!state.allowsPlanEdits)
        #expect(state.plannerNotice == notice)
        #expect(state.failure == "still unreadable")
        state.loaded()
        #expect(state.allowsPlanEdits)
        #expect(state.failure == nil)
        #expect(state.plannerNotice == nil)
    }

    @Test("a failure after a good read is reported again with its reason but keeps the last good read usable")
    func failureAfterLoad() {
        var state = PlanCacheState()
        state.loaded()
        #expect(state.failed("gone") == "gone")
        #expect(state.allowsPlanEdits)
        #expect(state.plannerNotice == nil)
    }
}
