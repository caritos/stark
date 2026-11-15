//
//  EventKitProvider.swift
//  Stark
//
//  The ONLY file in the app that imports EventKit. Reads Apple Calendar events and Reminders
//  and maps them to StarkKit's plain values; never writes. Mapping rules that need testing live in
//  StarkKit (`appleEventEnd`, `appleReminderDue`, `AppleAccess.combined`).
//

import CoreGraphics
import EventKit
import Foundation
import StarkKit

/// `nonisolated`: the app target defaults to `@MainActor` isolation; this type must not, so
/// EventKit reads never run on the main actor and the completion handlers (called on EventKit's
/// queue) can call the mapping helpers. `fetch` is `@concurrent`, so under approachable
/// concurrency (nonisolated async = caller's actor) it still runs on the concurrent pool.
/// `@unchecked Sendable`: the only stored state is one `EKEventStore`, created on first use under
/// a lock and never replaced; Apple documents the store as safe to use from any thread for reads.
/// EventKit objects never leave this file. `calendars()` is synchronous and must be called off the
/// main actor by the caller.
nonisolated final class EventKitProvider: AppleItemProvider, @unchecked Sendable {
    /// EventKit refuses event predicates spanning more than about four years; fetch in chunks.
    private static let maxChunkYears = 4

    private let storeLock = NSLock()
    private var createdStore: EKEventStore?

    /// Created on first real use (an access request, `calendars()` or `fetch`), so a user who
    /// never turns the overlay on never gets an `EKEventStore`. `accessState()` does not need it.
    private var store: EKEventStore {
        storeLock.withLock {
            if let createdStore { return createdStore }
            let new = EKEventStore()
            createdStore = new
            return new
        }
    }

    var storeChangedNotification: Notification.Name? { .EKEventStoreChanged }

    func accessState() -> AppleAccess {
        AppleAccess.combined(events: Self.map(EKEventStore.authorizationStatus(for: .event)),
                             reminders: Self.map(EKEventStore.authorizationStatus(for: .reminder)))
    }

    func requestAccess() async -> AppleAccess {
        do {
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                _ = try await store.requestFullAccessToEvents()
            }
            if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
                _ = try await store.requestFullAccessToReminders()
            }
        } catch {
            // A failed request leaves the status as it is; report whatever it is now.
        }
        return accessState()
    }

    func calendars() -> [AppleCalendarInfo] {
        store.calendars(for: .event).map { Self.info($0, isReminderList: false) }
            + store.calendars(for: .reminder).map { Self.info($0, isReminderList: true) }
    }

    @concurrent
    func fetch(events: ClosedRange<Date>, reminders: ClosedRange<Date>) async throws -> AppleSnapshot {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(.main))
        #endif
        let fetchedEvents = fetchEvents(in: events)
        let fetchedReminders = try await fetchReminders(in: reminders)
        return AppleSnapshot(events: fetchedEvents, reminders: fetchedReminders)
    }

    // MARK: - Events

    private func fetchEvents(in range: ClosedRange<Date>) -> [AppleCalendarEvent] {
        let calendar = Calendar.autoupdatingCurrent
        var result: [AppleCalendarEvent] = []
        var seen = Set<String>()
        var chunkStart = range.lowerBound
        while chunkStart < range.upperBound {
            let chunkEnd = min(calendar.date(byAdding: .year, value: Self.maxChunkYears, to: chunkStart)
                               ?? range.upperBound, range.upperBound)
            let predicate = store.predicateForEvents(withStart: chunkStart, end: chunkEnd, calendars: nil)
            for event in store.events(matching: predicate) {
                guard let mapped = Self.map(event, calendar: calendar) else { continue }
                // An occurrence spanning a chunk boundary is returned by both chunks.
                let key = "\(mapped.id)|\(mapped.start.timeIntervalSince1970)"
                if seen.insert(key).inserted { result.append(mapped) }
            }
            chunkStart = chunkEnd
        }
        return result
    }

    private static func map(_ event: EKEvent, calendar: Calendar) -> AppleCalendarEvent? {
        guard let start = event.startDate, let ekCalendar = event.calendar else { return nil }
        let id = event.eventIdentifier ?? event.calendarItemIdentifier
        return AppleCalendarEvent(
            id: id,
            title: event.title ?? "",
            notes: event.notes,
            location: event.location,
            url: event.url?.absoluteString,
            start: start,
            // All-day: inclusive last day (see `appleEventEnd`); timed: EventKit's end as is.
            end: appleEventEnd(start: start, end: event.endDate, isAllDay: event.isAllDay, calendar: calendar),
            isAllDay: event.isAllDay,
            calendar: info(ekCalendar, isReminderList: false))
    }

    // MARK: - Reminders

    /// EventKit hands a reminder fetch `nil` when it fails; that throws so the caller keeps the
    /// previous snapshot instead of showing "no reminders".
    struct ReminderFetchFailed: Error {}

    @concurrent
    private func fetchReminders(in range: ClosedRange<Date>) async throws -> [AppleReminder] {
        let open = store.predicateForIncompleteReminders(withDueDateStarting: range.lowerBound,
                                                         ending: range.upperBound, calendars: nil)
        let done = store.predicateForCompletedReminders(withCompletionDateStarting: range.lowerBound,
                                                        ending: range.upperBound, calendars: nil)
        let openItems = try await reminders(matching: open)
        let doneItems = try await reminders(matching: done)
        return openItems + doneItems
    }

    /// Maps inside the completion handler so no `EKReminder` crosses a concurrency boundary.
    @concurrent
    private func reminders(matching predicate: NSPredicate) async throws -> [AppleReminder] {
        try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(throwing: ReminderFetchFailed())
                    return
                }
                continuation.resume(returning: reminders.compactMap(Self.map))
            }
        }
    }

    private static func map(_ reminder: EKReminder) -> AppleReminder? {
        guard let ekCalendar = reminder.calendar else { return nil }
        // Undated reminders pass through with due == nil; `mergeAppleItems` drops them. The
        // components are Gregorian values whatever the phone's calendar (`appleReminderDue`).
        let due = reminder.dueDateComponents.map { appleReminderDue($0) }
        return AppleReminder(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            due: due?.date,
            dueHasTime: due?.hasTime ?? false,
            isCompleted: reminder.isCompleted,
            completedAt: reminder.completionDate,
            // EventKit uses 0 for "none" and 1-9 like iCal, as Stark does.
            priority: reminder.priority == 0 ? nil : reminder.priority,
            calendar: info(ekCalendar, isReminderList: true))
    }

    // MARK: - Shared mapping

    private static func info(_ calendar: EKCalendar, isReminderList: Bool) -> AppleCalendarInfo {
        AppleCalendarInfo(id: calendar.calendarIdentifier,
                          title: calendar.title,
                          accountName: calendar.source?.title ?? "",
                          colorHex: hex(calendar.cgColor),
                          isReminderList: isReminderList)
    }

    /// "#RRGGBB" in sRGB, or nil if the colour cannot be converted.
    private static func hex(_ color: CGColor?) -> String? {
        guard let color,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 3 else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c[0]), byte(c[1]), byte(c[2]))
    }

    private static func map(_ status: EKAuthorizationStatus) -> AppleAccess {
        switch status {
        case .fullAccess: return .granted
        case .writeOnly: return .writeOnly
        case .denied, .restricted: return .denied
        case .notDetermined: return .notAsked
        @unknown default: return .denied
        }
    }
}
