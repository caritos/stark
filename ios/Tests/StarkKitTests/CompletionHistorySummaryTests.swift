import Testing
import Foundation
@testable import StarkKit

struct CompletionHistorySummaryTests {
    private func day(_ iso: String) -> Date { DateMath.date(from: iso) }

    @Test("entry line pluralizes lateness and omits it when on time or undone")
    func entryLine() {
        #expect(CompletionEntry(due: day("2026-09-14"), done: day("2026-09-15"), daysLate: 1).line == "Due Sep 14 · done Sep 15 (1 day late)")
        #expect(CompletionEntry(due: day("2026-09-14"), done: day("2026-09-16"), daysLate: 2).line == "Due Sep 14 · done Sep 16 (2 days late)")
        #expect(CompletionEntry(due: day("2026-09-14"), done: day("2026-09-14"), daysLate: 0).line == "Due Sep 14 · done Sep 14")
        #expect(CompletionEntry(due: day("2026-09-14"), done: nil, daysLate: 0).line == "Due Sep 14")
    }

    @Test("summary lines cap entries at ten")
    func summaryCaps() {
        let entries = (1...12).map { CompletionEntry(due: day("2026-09-\(String(format: "%02d", $0))"), done: nil, daysLate: 0) }
        let h = CompletionHistory(entries: entries, doneLast30: 12, doneLast90: 12, lateLast90: 2,
                                  lastDone: day("2026-09-12"), averageGapDays: 1.5, longestGapDays: 3)
        let lines = h.summaryLines()
        #expect(lines.prefix(5) == ["Last 30 days: 12", "Last 90 days: 12 (2 late)", "Last done: Sep 12",
                                    "Average gap: 1.5 days", "Longest gap: 3 days"])
        #expect(lines.count == 15)
        #expect(lines[5] == "Due Sep 1")
    }
}
