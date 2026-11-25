import Foundation
import Testing
@testable import StarkKit

/// What the watch complications show for the stored snapshot. Run under TZ=Pacific/Honolulu,
/// America/New_York and Asia/Tokyo as well.
@Suite struct WatchComplicationTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }()
    private let us = Locale(identifier: "en_US")

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: 6, day: d, hour: h, minute: m))!
    }

    private var now: Date { date(15, 10) }

    private func item(_ title: String, start: Date, end: Date? = nil, allDay: Bool = false, reminder: Bool = false,
                      overdue: Bool = false, tomorrow: Bool = false) -> WatchSnapshotRow {
        WatchSnapshotRow(item: WidgetItem(id: "apple-\(title)", title: title, isReminder: reminder, isAllDay: allDay,
                                          start: start, end: end, colorHex: nil, isOverdue: overdue,
                                          isTomorrow: tomorrow),
                         reminderIdentifier: reminder ? title : nil, externalID: nil,
                         occurrence: reminder ? start : nil)
    }

    private func snapshot(_ state: WatchSnapshot.State = .items, rows: [WatchSnapshotRow] = [],
                          at: Date? = nil) -> WatchSnapshot {
        WatchSnapshot(generatedAt: at ?? now, state: state, rows: rows)
    }

    private func content(_ s: WatchSnapshot?, at: Date? = nil) -> WatchComplicationContent {
        WatchComplication.content(snapshot: s, now: at ?? now, calendar: Self.cal, locale: us)
    }

    @Test func noSnapshotAsksToOpenStark() {
        let c = content(nil)
        #expect(c.message == "Open Stark on iPhone")
        #expect(c.lines.isEmpty)
        #expect(c.count == 0)
    }

    @Test func staleSnapshotAsksToOpenStarkEvenWithRows() {
        let s = snapshot(rows: [item("Standup", start: date(15, 12), end: date(15, 13))], at: date(15, 6))
        #expect(content(s, at: date(15, 9, 1)).message == "Open Stark on iPhone")
        #expect(content(s, at: date(15, 8, 59)).message == nil)
    }

    @Test func itemsGiveLockLinesInOrderUpToThree() {
        let rows = (1...5).map { item("E\($0)", start: date(15, 10 + $0), end: date(15, 10 + $0, 30)) }
        let c = content(snapshot(rows: rows))
        #expect(c.message == nil)
        #expect(c.lines.map(\.title) == ["E1", "E2", "E3"])
        #expect(c.lines.first?.time != nil)
        #expect(c.count == 5)
        #expect(c.inline?.title == "E1")
    }

    @Test func tomorrowIsNotCountedAndSaysTomorrow() {
        let rows = [item("Today", start: date(15, 11), end: date(15, 12)),
                    item("Later", start: date(16, 9), end: date(16, 10), tomorrow: true)]
        let c = content(snapshot(rows: rows))
        #expect(c.count == 1)
        #expect(c.lines.count == 2)
        #expect(c.lines[1].time?.contains("Tmrw") == true)
    }

    @Test func endedEventsDropOutAtTheirEntryDate() {
        let rows = [item("Done", start: date(15, 8), end: date(15, 9)),
                    item("Next", start: date(15, 11), end: date(15, 12))]
        let c = content(snapshot(rows: rows))
        #expect(c.lines.map(\.title) == ["Next"])
        #expect(c.count == 1)
    }

    @Test func inlineSkipsAnOverdueReminder() {
        let rows = [item("Old", start: date(10), allDay: true, reminder: true, overdue: true),
                    item("Standup", start: date(15, 11), end: date(15, 12))]
        let c = content(snapshot(rows: rows))
        #expect(c.inline?.title == "Standup")
        #expect(c.lines.map(\.title) == ["Old", "Standup"])
    }

    @Test func stateMessagesAreNeverBlank() {
        #expect(content(snapshot(.accessNeeded("Allow Calendar access on iPhone"))).message
                == "Allow Calendar access on iPhone")
        #expect(content(snapshot(.accessNeeded(""))).message == "Allow Calendar access on iPhone")
        #expect(content(snapshot(.noSources)).message == "No calendars are syncing")
        #expect(content(snapshot(.empty)).message == "Nothing coming up")
        #expect(content(snapshot(.failed("boom"))).message == "Couldn't read calendar. Open Stark on iPhone")
        #expect(content(snapshot(.failed(""))).message == "Couldn't read calendar. Open Stark on iPhone")
        // Items state whose rows have all ended.
        let ended = snapshot(rows: [item("Done", start: date(15, 8), end: date(15, 9))])
        #expect(content(ended).message == "Nothing coming up")
    }

    @Test func afterMidnightTomorrowBecomesToday() {
        let rows = [item("Early", start: date(16, 9), end: date(16, 10), tomorrow: true)]
        let s = snapshot(rows: rows, at: date(15, 23))
        let c = content(s, at: date(16, 0, 30))
        #expect(c.count == 1)
        #expect(c.lines.first?.time?.contains("Tmrw") == false)
    }

    @Test func yesterdaysAllDayEventLeavesAtMidnight() {
        let rows = [item("Holiday", start: date(15), end: date(15), allDay: true)]
        let s = snapshot(rows: rows, at: date(15, 23))
        #expect(content(s, at: date(16, 0, 30)).message == "Nothing coming up")
    }

    @Test func entryDatesStartNowFollowEndsAndStopAtTheStaleCutoff() {
        let rows = [item("A", start: date(15, 11), end: date(15, 12))]
        let dates = WatchComplication.entryDates(snapshot: snapshot(rows: rows), now: now, calendar: Self.cal)
        #expect(dates.first == now)
        #expect(dates.contains(date(15, 11)))
        #expect(dates.contains(date(15, 12)))
        #expect(dates.contains(date(15, 13))) // generatedAt + 3 h: the message takes over
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
        #expect(dates.last! <= date(15, 13))
    }

    @Test func entryDatesWithoutSnapshotIsJustNow() {
        #expect(WatchComplication.entryDates(snapshot: nil, now: now, calendar: Self.cal) == [now])
    }

    @Test func entryDatesAreCapped() {
        let rows = (0..<20).map { item("E\($0)", start: date(15, 10, 1 + $0), end: date(15, 10, 1 + $0)) }
        let dates = WatchComplication.entryDates(snapshot: snapshot(rows: rows), now: now, calendar: Self.cal)
        #expect(dates.count <= 12)
    }

    @Test func reloadIsAtLeastHourly() {
        let soon = [now, now.addingTimeInterval(600)]
        #expect(WatchComplication.reloadDate(after: now, entryDates: soon) == now.addingTimeInterval(600))
        let far = [now, now.addingTimeInterval(7200)]
        #expect(WatchComplication.reloadDate(after: now, entryDates: far) == now.addingTimeInterval(3600))
        #expect(WatchComplication.reloadDate(after: now, entryDates: [now]) == now.addingTimeInterval(3600))
    }

    @Test func countTextFollowsTheLockScreenHelper() {
        #expect(WatchComplication.countText(3) == "3")
        #expect(WatchComplication.countText(12) == "9+")
    }
}
