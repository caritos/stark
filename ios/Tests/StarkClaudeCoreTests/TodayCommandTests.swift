import Foundation
import Testing
@testable import StarkClaudeCore

/// `today` read a pulled copy of the app's `.ics` files. Stark now keeps new items in Apple
/// Calendar and Reminders, so that copy would silently miss them: until the Mac tool exists the
/// command only says it is unavailable (spec decision 4) and touches neither the phone nor disk.
@Suite struct TodayCommandTests {
    let cal = Calendar(identifier: .gregorian)

    @Test func saysUnavailableUntilTheMacTool() {
        let out = TodayCommand().run(day: nil)
        #expect(out.contains("unavailable until the Mac tool"))
        #expect(out == TodayCommand.unavailable)
    }

    @Test func sameAnswerForAnyDate() throws {
        let day = try TodayCommand.parseDay("2026-11-08")
        #expect(TodayCommand().run(day: day) == TodayCommand.unavailable)
    }

    @Test func usageSaysUnavailable() {
        #expect(CLIUsage.text.contains("today"))
        #expect(CLIUsage.text.contains("unavailable until the Mac tool"))
        #expect(!CLIUsage.text.contains("pulls the app's data"))
    }

    @Test func invalidDatesAreBadRequest() throws {
        for bad in ["2026-13-01", "2026-02-30", "26-11-07", "2026/11/07", "", "yesterday", "2026-1-7"] {
            #expect(throws: (any Error).self) { try TodayCommand.parseDay(bad) }
            do { _ = try TodayCommand.parseDay(bad) } catch let e as CLIError {
                guard case .badRequest = e else { Issue.record("wrong error"); continue }
            }
        }
        #expect(try TodayCommand.parseDay("2026-11-08") == cal.date(from: DateComponents(year: 2026, month: 11, day: 8)))
    }
}
