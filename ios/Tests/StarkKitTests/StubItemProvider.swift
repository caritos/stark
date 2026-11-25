import Foundation
@testable import StarkKit

/// A fake `AppleItemProvider` for tests that need a canned access state, calendar list and fetch.
final class StubItemProvider: AppleItemProvider, @unchecked Sendable {
    struct FetchFailure: Error, LocalizedError { var errorDescription: String? { "boom" } }

    var access: AppleAccess
    var calendarList: [AppleCalendarInfo]
    var snapshot: AppleSnapshot
    var fetchError: Error?

    init(access: AppleAccess = .granted,
         calendars: [AppleCalendarInfo] = [AppleCalendarInfo(id: "cal1", title: "Home", accountName: "iCloud",
                                                             colorHex: nil, isReminderList: false)],
         snapshot: AppleSnapshot = AppleSnapshot(events: [], reminders: []),
         fetchError: Error? = nil) {
        self.access = access
        self.calendarList = calendars
        self.snapshot = snapshot
        self.fetchError = fetchError
    }

    func accessState() -> AppleAccess { access }
    func requestAccess() async -> AppleAccess { access }
    func calendars() -> [AppleCalendarInfo] { calendarList }
    func fetch(events: ClosedRange<Date>, reminders: ClosedRange<Date>) async throws -> AppleSnapshot {
        if let fetchError { throw fetchError }
        return snapshot
    }
}
