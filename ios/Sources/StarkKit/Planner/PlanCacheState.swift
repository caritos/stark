// ios/Sources/StarkKit/Planner/PlanCacheState.swift
import Foundation

/// Whether the app's cache of Apple reminders' plan blocks (Stark's sidecar) has been read, and
/// which read failure to show.
///
/// The planner builds a day's draft from that cache, and a save replaces the day's STORED Apple
/// blocks with the draft's. A draft built before the first successful read has none, so saving it
/// would wipe that day's Apple plan blocks: the planner neither edits nor saves until then.
public struct PlanCacheState: Equatable, Sendable {
    /// At least one read succeeded.
    public private(set) var hasLoaded = false
    /// The latest read failed with this message (nil after a success).
    public private(set) var failure: String?

    public init() {}

    /// The planner's timeline, tray, day stepping and save are enabled.
    public var allowsPlanEdits: Bool { hasLoaded }

    public mutating func loaded() {
        hasLoaded = true
        failure = nil
    }

    /// Records a failed read. Returns the message to show in the error banner for the first
    /// failure of a run, nil for the repeats (each refresh would show it again otherwise).
    public mutating func failed(_ message: String) -> String? {
        defer { failure = message }
        return failure == nil ? message : nil
    }
}
