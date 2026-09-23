// ios/Sources/StarkKit/Models/RecurrenceRule+PickerFields.swift

extension RecurrenceRule {
    /// Builds a rule from a recurrence picker's raw field state (`CustomRepeatView`'s `interval`,
    /// `unit`, `byDay`, `byMonthDay`, `byPositionalDay`, `byMonth`), applying the gating a
    /// picker screen needs: `byDay` only applies when weekly, `byMonthDay`/`byPositionalDay`
    /// only when monthly or yearly, `byMonth` only when yearly. Centralizing this gating here
    /// (tested) rather than duplicating it in the view layer is what would have caught the
    /// double-`BYDAY` silent-data-loss bug this feature's final review found and fixed once
    /// already (issue #93) - a future picker screen gets this gating for free instead of
    /// re-deriving it untested.
    public static func fromPickerFields(
        frequency: Frequency,
        interval: Int,
        byDay: Set<Weekday>,
        byMonthDay: [Int]?,
        byPositionalDay: [PositionalDay]?,
        byMonth: Set<Month>
    ) -> RecurrenceRule {
        RecurrenceRule(
            frequency: frequency,
            interval: interval,
            byDay: frequency == .weekly && !byDay.isEmpty
                ? byDay.sorted { $0.rawValue < $1.rawValue } : nil,
            byMonthDay: (frequency == .monthly || frequency == .yearly) ? byMonthDay : nil,
            byPositionalDay: (frequency == .monthly || frequency == .yearly) ? byPositionalDay : nil,
            byMonth: frequency == .yearly && !byMonth.isEmpty
                ? byMonth.sorted { $0.rawValue < $1.rawValue } : nil
        )
    }
}
