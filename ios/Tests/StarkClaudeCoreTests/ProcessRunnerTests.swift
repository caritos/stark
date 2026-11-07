import Foundation
import Testing
@testable import StarkClaudeCore

@Suite struct ProcessRunnerTests {
    #if os(macOS)
    @Test func slowChildIsKilledAndReportedAsTimeout() {
        let start = Date()
        #expect(throws: CLIError.launchFailed("timed out talking to the phone (1 s)")) {
            try FoundationProcessRunner(timeout: 1).run("/bin/sleep", ["30"])
        }
        #expect(Date().timeIntervalSince(start) < 10)
    }
    @Test func capturesOutputAndStatus() throws {
        let r = try FoundationProcessRunner().run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        #expect(r == ProcessResult(status: 3, stdout: "out\n", stderr: "err\n"))
    }
    #endif
}
