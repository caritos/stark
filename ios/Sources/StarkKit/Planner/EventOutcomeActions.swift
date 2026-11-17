// ios/Sources/StarkKit/Planner/EventOutcomeActions.swift

/// Which occurrence actions the event edit sheet shows. Kept out of the view so it is testable.
/// (No screen sets attended/skipped marks any more; existing sidecar marks are still read
/// through `ItemRouter`.)
public struct EventOutcomeActions: Equatable {
    /// Drops this one occurrence from a recurring series (an exception date).
    public let showsRemoveOccurrence: Bool

    public init(isRecurring: Bool) {
        showsRemoveOccurrence = isRecurring
    }
}
