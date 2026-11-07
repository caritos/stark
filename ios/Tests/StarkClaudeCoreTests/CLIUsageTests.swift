import Testing
@testable import StarkClaudeCore

@Suite struct CLIUsageTests {
    @Test func helpWordsAreRecognised() {
        for a in ["--help", "-h", "help"] { #expect(CLIUsage.isHelp([a])) }
        #expect(!CLIUsage.isHelp([]))
        #expect(!CLIUsage.isHelp(["bogus"]))
        #expect(!CLIUsage.isHelp(["add", "--help"]))
        #expect(CLIUsage.text.contains("stark-claude add"))
    }
}
