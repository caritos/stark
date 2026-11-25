import Foundation

public enum WatchSnapshotBuilder {
    public static let accessMessage = "Open Stark on your iPhone and allow Calendar and Reminders access."

    /// The Up Next rows for the watch, from the phone's own store. `excluded` is the phone's hidden
    /// calendar ids, so hidden calendars and calendar sets carry over.
    public static func build(provider: AppleItemProvider, now: Date, limit: Int = 20,
                             excluded: Set<String> = [], calendar: Calendar = .current) async -> WatchSnapshot {
        func snapshot(_ state: WatchSnapshot.State, _ rows: [WatchSnapshotRow] = []) -> WatchSnapshot {
            WatchSnapshot(generatedAt: now, state: state, rows: rows)
        }
        guard provider.accessState() == .granted else { return snapshot(.accessNeeded(accessMessage)) }
        guard !provider.calendars().isEmpty else { return snapshot(.noSources) }

        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 2, to: start) else {
            return snapshot(.failed("Couldn't work out the date range."))
        }
        let fetched: AppleSnapshot
        do {
            // Completed reminders are not listed, so the completed window is empty.
            fetched = try await provider.fetch(events: now...end, reminders: now...now)
        } catch {
            let text = error.localizedDescription
            return snapshot(.failed(text.isEmpty ? "Couldn't read the calendar." : text))
        }
        let items = WidgetAgenda.items(events: fetched.events, reminders: fetched.reminders, excluded: excluded,
                                       now: now, limit: limit, calendar: calendar)
        guard !items.isEmpty else { return snapshot(.empty) }
        var remindersByID: [String: AppleReminder] = [:]
        for reminder in fetched.reminders { remindersByID[ItemOrigin.applePrefix + reminder.id] = reminder }
        let rows = items.map { item -> WatchSnapshotRow in
            guard item.isReminder, let reminder = remindersByID[item.id] else {
                return WatchSnapshotRow(item: item, reminderIdentifier: nil, externalID: nil, occurrence: nil)
            }
            return WatchSnapshotRow(item: item, reminderIdentifier: reminder.id, externalID: nil,
                                    occurrence: reminder.due)
        }
        return snapshot(.items, rows)
    }
}
