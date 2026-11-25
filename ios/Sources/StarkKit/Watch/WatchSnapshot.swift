import Foundation

/// One Up Next row for the watch: the widget's row plus what `WatchCommand.complete` needs.
public struct WatchSnapshotRow: Codable, Equatable, Sendable {
    public let item: WidgetItem
    /// EventKit's `calendarItemIdentifier` (no `apple-` prefix); nil for events.
    public let reminderIdentifier: String?
    public let externalID: String?
    /// The reminder's due date, for `WatchCommand.complete`; nil for events.
    public let occurrence: Date?

    public init(item: WidgetItem, reminderIdentifier: String?, externalID: String?, occurrence: Date?) {
        self.item = item
        self.reminderIdentifier = reminderIdentifier
        self.externalID = externalID
        self.occurrence = occurrence
    }
}

/// What the iPhone pushes to the watch (latest wins). The watch reads nothing from EventKit.
public struct WatchSnapshot: Codable, Equatable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        case accessNeeded(String), noSources, empty, items, failed(String)
    }

    public let generatedAt: Date
    public let state: State
    /// Empty unless `state == .items`; at most the builder's `limit`.
    public let rows: [WatchSnapshotRow]

    public init(generatedAt: Date, state: State, rows: [WatchSnapshotRow]) {
        self.generatedAt = generatedAt
        self.state = state
        self.rows = rows
    }
}

/// Implemented by app-target glue over `WCSession.updateApplicationContext`.
public protocol WatchSnapshotPublisher: Sendable {
    func publish(_ snapshot: WatchSnapshot)
}
