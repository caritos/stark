import Foundation
import Testing
@testable import StarkKit

@Suite struct WatchSnapshotTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }()

    private func date(_ d: Int, _ h: Int = 0, month: Int = 6) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: h))!
    }

    private var now: Date { date(15, 10) }

    private func list(_ id: String) -> AppleCalendarInfo {
        AppleCalendarInfo(id: id, title: id, accountName: "iCloud", colorHex: "#00FF00", isReminderList: true)
    }

    private func reminder(_ id: String, due: Date?, hasTime: Bool = true, listID: String = "list1") -> AppleReminder {
        AppleReminder(id: id, title: id, notes: nil, due: due, dueHasTime: hasTime, isCompleted: false,
                      completedAt: nil, priority: nil, calendar: list(listID))
    }

    private func event(_ id: String, calID: String = "cal1") -> AppleCalendarEvent {
        AppleCalendarEvent(id: id, title: id, notes: nil, location: nil, url: nil, start: date(15, 14),
                           end: date(15, 15), isAllDay: false,
                           calendar: AppleCalendarInfo(id: calID, title: calID, accountName: "iCloud",
                                                       colorHex: nil, isReminderList: false))
    }

    private func build(_ provider: StubItemProvider, excluded: Set<String> = [], limit: Int = 20) async -> WatchSnapshot {
        await WatchSnapshotBuilder.build(provider: provider, now: now, limit: limit, excluded: excluded, calendar: Self.cal)
    }

    @Test(arguments: [AppleAccess.denied, .notAsked, .writeOnly])
    func notGrantedGivesAccessNeededWithAReadableReason(access: AppleAccess) async {
        let snap = await build(StubItemProvider(access: access))
        guard case .accessNeeded(let reason) = snap.state else { Issue.record("state \(snap.state)"); return }
        #expect(reason.contains("Calendar"))
        #expect(snap.rows.isEmpty)
        #expect(snap.generatedAt == now)
    }

    @Test func noCalendarsGivesNoSources() async {
        let snap = await build(StubItemProvider(calendars: []))
        #expect(snap.state == .noSources)
        #expect(snap.rows.isEmpty)
    }

    @Test func noItemsGivesEmpty() async {
        let snap = await build(StubItemProvider())
        #expect(snap.state == .empty)
        #expect(snap.rows.isEmpty)
    }

    @Test func itemsAreTheWidgetRowsCappedAtTheLimit() async {
        let reminders = (1...30).map { reminder("r\($0)", due: date($0 % 14 + 1)) }
        let provider = StubItemProvider(snapshot: AppleSnapshot(events: [], reminders: reminders))
        let snap = await build(provider)
        #expect(snap.state == .items)
        #expect(snap.rows.count == 20)
        let starts = snap.rows.map(\.item.start)
        #expect(starts == starts.sorted())
    }

    @Test func aReminderRowCarriesItsIdentifierExternalIDAndOccurrence() async {
        let due = date(15, 9)
        let provider = StubItemProvider(snapshot: AppleSnapshot(events: [], reminders: [reminder("abc", due: due)]))
        let row = await build(provider).rows.first
        #expect(row?.item.id == "apple-abc")
        #expect(row?.reminderIdentifier == "abc")
        #expect(row?.externalID == nil)
        #expect(row?.occurrence == due)
    }

    @Test func anEventRowCarriesNone() async {
        let provider = StubItemProvider(snapshot: AppleSnapshot(events: [event("e1")], reminders: []))
        let row = await build(provider).rows.first
        #expect(row?.item.id == "apple-e1")
        #expect(row?.reminderIdentifier == nil)
        #expect(row?.externalID == nil)
        #expect(row?.occurrence == nil)
    }

    @Test func hiddenCalendarsAreExcluded() async {
        let provider = StubItemProvider(snapshot: AppleSnapshot(
            events: [event("e1", calID: "hidden"), event("e2")],
            reminders: [reminder("r1", due: date(15, 9), listID: "hiddenList"), reminder("r2", due: date(15, 9))]))
        let snap = await build(provider, excluded: ["hidden", "hiddenList"])
        #expect(Set(snap.rows.map(\.item.id)) == ["apple-e2", "apple-r2"])
    }

    @Test func fetchErrorGivesFailed() async {
        let snap = await build(StubItemProvider(fetchError: StubItemProvider.FetchFailure()))
        guard case .failed(let message) = snap.state else { Issue.record("state \(snap.state)"); return }
        #expect(!message.isEmpty)
        #expect(snap.rows.isEmpty)
    }

    @Test func snapshotRoundTripsThroughJSON() throws {
        let item = WidgetItem(id: "apple-x", title: "X", isReminder: true, isAllDay: false, start: date(1), end: nil,
                              colorHex: "#FF0000", isOverdue: true, isTomorrow: false)
        let row = WatchSnapshotRow(item: item, reminderIdentifier: "x", externalID: "ext", occurrence: date(1))
        let states: [WatchSnapshot.State] = [.accessNeeded("a"), .noSources, .empty, .items, .failed("f")]
        for state in states {
            let snap = WatchSnapshot(generatedAt: now, state: state, rows: state == .items ? [row] : [])
            let back = try WatchLinkCoding.decode(WatchSnapshot.self, from: try WatchLinkCoding.encode(snap))
            #expect(back == snap)
        }
    }

    @Test func snapshotInDictionaryDecodesAndMissingKeyGivesNil() throws {
        let snap = WatchSnapshot(generatedAt: now, state: .empty, rows: [])
        let message: [String: Any] = [WatchLinkCoding.snapshotKey: try WatchLinkCoding.encode(snap)]
        #expect(WatchLinkCoding.snapshot(in: message) == snap)
        #expect(WatchLinkCoding.snapshot(in: [:]) == nil)
        #expect(WatchLinkCoding.snapshot(in: [WatchLinkCoding.snapshotKey: Data([1, 2])]) == nil)
    }
}
