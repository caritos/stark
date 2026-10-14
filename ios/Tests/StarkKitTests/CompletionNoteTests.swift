import Testing
import Foundation
@testable import StarkKit

@Suite("CompletionNote")
struct CompletionNoteTests {
    private func d(_ iso: String) -> Date { DateMath.date(from: iso) }
    private func item(due: String, at: String?) -> AgendaItem {
        let r = Reminder(id: "r", title: "T", dueDate: d(due), isCompleted: true, completedDate: d(due), completedAt: at.map(d))
        return AgendaItem(kind: .reminder(r), occurrence: d(due), displayDate: d(due), isOverdue: false)
    }
    @Test("shown only when done on a different day than due")
    func note() {
        #expect(item(due: "2026-10-13", at: "2026-10-14").completionNote == "done Oct 14")
        #expect(item(due: "2026-10-14", at: "2026-10-14").completionNote == nil)
        #expect(item(due: "2026-10-14", at: nil).completionNote == nil)
    }
}
