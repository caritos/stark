public enum Month: Int, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case january = 1, february, march, april, may, june, july, august,
         september, october, november, december

    /// The single shared source for this month's display name, e.g. "September" — used by
    /// `RecurrenceRule.summary` and every recurrence-picker screen, so the name is spelled in
    /// exactly one place instead of duplicated per call site.
    public var displayName: String {
        switch self {
        case .january: return "January"
        case .february: return "February"
        case .march: return "March"
        case .april: return "April"
        case .may: return "May"
        case .june: return "June"
        case .july: return "July"
        case .august: return "August"
        case .september: return "September"
        case .october: return "October"
        case .november: return "November"
        case .december: return "December"
        }
    }
}
