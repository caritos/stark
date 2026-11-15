// ios/Sources/StarkKit/Apple/AppleItemProvider.swift
import Foundation

/// Reads Apple Calendar events and Reminders as plain values. The app's `EventKitProvider` is the
/// only implementation that touches EventKit; tests use fakes. `fetch` and `calendars` do
/// EventKit work and must not be called on the main actor.
public protocol AppleItemProvider: Sendable {
    func accessState() -> AppleAccess
    func requestAccess() async -> AppleAccess
    func calendars() -> [AppleCalendarInfo]
    /// `@concurrent`: always runs on the concurrent pool, never on the caller's (main) actor.
    @concurrent
    func fetch(events: ClosedRange<Date>, reminders: ClosedRange<Date>) async throws -> AppleSnapshot
    /// Posted when the underlying store changes (EventKit's `EKEventStoreChanged`); nil if never.
    var storeChangedNotification: Notification.Name? { get }
}

public extension AppleItemProvider {
    var storeChangedNotification: Notification.Name? { nil }
}
