// ios/Sources/StarkKit/Planner/AgendaScrollTracking.swift

/// Resolves which row of the agenda list is at the top of the viewport, for scroll-synced
/// calendar selection (issue #101).
///
/// The agenda is a SwiftUI `List`, and `.scrollPosition(id:)` never reports a position on one (it
/// needs a `ScrollView` with a scroll-target layout), so the view instead records which rows a
/// list cell is currently displayed for (`onAppear`/`onDisappear`) and asks this for the topmost.
public enum AgendaScrollTracking {
    /// The earliest row, in list order, whose id is in `displayed`; nil when none is. Ids in
    /// `displayed` that are not in `orderedRowIDs` (a row that just left the list) are ignored.
    public static func topRowID(displayed: Set<String>, orderedRowIDs: [String]) -> String? {
        orderedRowIDs.first(where: displayed.contains)
    }
}
