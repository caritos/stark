import Testing
@testable import StarkKit

@Suite("OverdueLabel")
struct OverdueLabelTests {
    @Test("singular, plural and capped")
    func text() {
        #expect(OverdueLabel.text(daysOverdue: 1) == "1 day overdue")
        #expect(OverdueLabel.text(daysOverdue: 7) == "7 days overdue")
        #expect(OverdueLabel.text(daysOverdue: 90) == "90+ days overdue")
        #expect(OverdueLabel.text(daysOverdue: 400) == "90+ days overdue")
    }
}
