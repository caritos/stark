import Foundation

extension AgendaItem {
    /// "done Oct 14" for a completed reminder finished on a different calendar day than it was due.
    public var completionNote: String? {
        guard case .reminder(let r) = kind, r.isCompleted, let at = r.completedAt, let due = r.dueDate else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        guard !calendar.isDate(at, inSameDayAs: due) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return "done \(formatter.string(from: at))"
    }
}
