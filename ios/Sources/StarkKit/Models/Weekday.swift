public enum Weekday: Int, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case sunday = 0, monday, tuesday, wednesday, thursday, friday, saturday

    /// The single shared source for this weekday's display name, e.g. "Wednesday" — used by
    /// `RecurrenceRule.summary` and every recurrence-picker screen, so the name is spelled in
    /// exactly one place instead of duplicated per call site.
    public var displayName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}
