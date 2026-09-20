// ios/Sources/StarkKit/Planner/EventOutcomeActions.swift

/// Which action buttons the event detail sheet shows, given the occurrence's current outcome.
/// Kept out of the view so it is testable.
public struct EventOutcomeActions: Equatable {
    public let showsAttended: Bool
    public let showsDidntAttend: Bool
    public let showsClear: Bool
    /// Drops this one occurrence from a recurring series (an exception date). A different action
    /// from "Didn't Attend", which keeps the occurrence visible.
    public let showsRemoveOccurrence: Bool

    public init(outcome: EventOutcome?, isRecurring: Bool) {
        showsAttended = outcome != .attended
        showsDidntAttend = outcome != .skipped
        showsClear = outcome != nil
        showsRemoveOccurrence = isRecurring
    }
}
