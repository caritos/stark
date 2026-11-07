import Foundation
import Testing
@testable import StarkKit

private let ny: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private func item(
    _ id: String = "a", kind: BridgeItem.Kind = .reminder, title: String = "T", notes: String? = nil,
    start: String = "2026-11-10", end: String? = nil, location: String? = nil, url: String? = nil,
    recurrence: BridgeRecurrence? = nil, priority: BridgeItem.PriorityLevel? = nil
) -> BridgeItem {
    BridgeItem(id: id, kind: kind, title: title, notes: notes, start: start, end: end,
               location: location, url: url, recurrence: recurrence, priority: priority)
}

private func batch(_ items: [BridgeItem], v: Int = 1, label: String? = nil) -> BridgeBatch {
    BridgeBatch(v: v, batch: UUID().uuidString, issuedAt: 0, label: label, items: items)
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    ny.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Test func reminderDateOnlyIsDueAtStartOfDay() throws {
    let r = try batch([item()]).models(calendar: ny).reminders[0]
    #expect(r.dueDate == date(2026, 11, 10))
    #expect(r.title == "T")
}

@Test func timedEventKeepsStartAndEnd() throws {
    let e = try batch([item(kind: .event, start: "2026-11-10T15:00", end: "16:30")]).models(calendar: ny).events[0]
    #expect(e.start == date(2026, 11, 10, 15))
    #expect(e.end == date(2026, 11, 10, 16, 30))
    #expect(!e.isAllDay)
}

@Test func allDayEventDropsEnd() throws {
    let e = try batch([item(kind: .event, start: "2026-11-10", end: "2026-11-10T17:00")]).models(calendar: ny).events[0]
    #expect(e.isAllDay)
    #expect(e.start == date(2026, 11, 10))
    #expect(e.end == nil)
}

@Test func endAtOrBeforeStartIsDropped() throws {
    let same = try batch([item(kind: .event, start: "2026-11-10T15:00", end: "15:00")]).models(calendar: ny).events[0]
    let before = try batch([item(kind: .event, start: "2026-11-10T15:00", end: "14:00")]).models(calendar: ny).events[0]
    #expect(same.end == nil)
    #expect(before.end == nil)
}

@Test func weeklyRecurrenceMaps() throws {
    let rec = BridgeRecurrence(freq: .weekly, interval: 2, byDay: ["tue", "thu"], until: "2026-12-31", count: nil)
    let r = try batch([item(recurrence: rec)]).models(calendar: ny).reminders[0]
    #expect(r.recurrence?.frequency == .weekly)
    #expect(r.recurrence?.interval == 2)
    #expect(r.recurrence?.byDay == [.tuesday, .thursday])
    #expect(r.recurrence?.until == date(2026, 12, 31))
}

@Test func recurrenceDefaultsAndCount() throws {
    let rec = BridgeRecurrence(freq: .daily, interval: nil, byDay: nil, until: nil, count: 5)
    let r = try batch([item(recurrence: rec)]).models(calendar: ny).reminders[0]
    #expect(r.recurrence?.interval == 1)
    #expect(r.recurrence?.count == 5)
}

@Test func priorityMaps() throws {
    let out = try batch([item("a", priority: .low), item("b", priority: .medium), item("c", priority: .high), item("d")])
        .models(calendar: ny).reminders
    #expect(out.map(\.priority) == [9, 5, 1, nil])
}

@Test func eventCarriesLocationAndUrl() throws {
    let e = try batch([item(kind: .event, start: "2026-11-10T09:00", location: "Room 1", url: "https://example.com/x")])
        .models(calendar: ny).events[0]
    #expect(e.location == "Room 1")
    #expect(e.url == "https://example.com/x")
}

@Test func unsupportedVersionThrows() {
    #expect(throws: BridgeError.unsupportedVersion(2)) { try batch([item()], v: 2).models(calendar: ny) }
}

@Test func emptyItemsThrows() {
    #expect(throws: BridgeError.emptyBatch) { try batch([]).models(calendar: ny) }
}

@Test func tooManyItemsThrows() {
    let items = (0...200).map { item("i\($0)") }
    #expect(throws: BridgeError.tooManyItems(201)) { try batch(items).models(calendar: ny) }
    let ok = (0..<200).map { item("i\($0)") }
    #expect((try? batch(ok).models(calendar: ny))?.reminders.count == 200)
}

@Test func titleAndNotesLimits() {
    #expect(throws: BridgeError.titleTooLong(id: "x")) {
        try batch([item("x", title: String(repeating: "a", count: 501))]).models(calendar: ny)
    }
    #expect(throws: BridgeError.notesTooLong(id: "x")) {
        try batch([item("x", notes: String(repeating: "a", count: 5001))]).models(calendar: ny)
    }
    #expect((try? batch([item("x", title: String(repeating: "a", count: 500), notes: String(repeating: "a", count: 5000))]).models(calendar: ny)) != nil)
}

@Test func emptyTitleThrows() {
    #expect(throws: BridgeError.emptyTitle(id: "x")) { try batch([item("x", title: "  ")]).models(calendar: ny) }
}

@Test func emptyAndDuplicateIdsThrow() {
    #expect(throws: BridgeError.emptyID) { try batch([item("")]).models(calendar: ny) }
    #expect(throws: BridgeError.duplicateID("a")) { try batch([item("a"), item("a")]).models(calendar: ny) }
}

@Test func badStartThrows() {
    #expect(throws: BridgeError.badDate(id: "x", field: "start", text: "tomorrow")) {
        try batch([item("x", start: "tomorrow")]).models(calendar: ny)
    }
    #expect(throws: BridgeError.badDate(id: "x", field: "start", text: "2026-02-30")) {
        try batch([item("x", start: "2026-02-30")]).models(calendar: ny)
    }
    #expect(throws: BridgeError.badDate(id: "x", field: "start", text: "")) {
        try batch([item("x", start: "")]).models(calendar: ny)
    }
}

@Test func badEndThrows() {
    #expect(throws: BridgeError.badDate(id: "x", field: "end", text: "later")) {
        try batch([item("x", kind: .event, start: "2026-11-10T09:00", end: "later")]).models(calendar: ny)
    }
}

@Test func untilBeforeStartThrows() {
    let rec = BridgeRecurrence(freq: .daily, interval: nil, byDay: nil, until: "2026-11-01", count: nil)
    #expect(throws: BridgeError.untilBeforeStart(id: "x")) {
        try batch([item("x", recurrence: rec)]).models(calendar: ny)
    }
}

@Test func unknownByDayThrows() {
    let rec = BridgeRecurrence(freq: .weekly, interval: nil, byDay: ["funday"], until: nil, count: nil)
    #expect(throws: BridgeError.badWeekday(id: "x", text: "funday")) {
        try batch([item("x", recurrence: rec)]).models(calendar: ny)
    }
}

@Test func badIntervalAndCountThrow() {
    let rec = BridgeRecurrence(freq: .daily, interval: 0, byDay: nil, until: nil, count: nil)
    #expect(throws: BridgeError.badInterval(id: "x")) { try batch([item("x", recurrence: rec)]).models(calendar: ny) }
    let rc = BridgeRecurrence(freq: .daily, interval: nil, byDay: nil, until: nil, count: 0)
    #expect(throws: BridgeError.badCount(id: "x")) { try batch([item("x", recurrence: rc)]).models(calendar: ny) }
}

@Test func nonHttpUrlThrows() {
    for bad in ["javascript:alert(1)", "file:///etc/passwd", "stark://add", "not a url", "https://"] {
        #expect(throws: BridgeError.badURL(id: "x")) {
            try batch([item("x", kind: .event, start: "2026-11-10T09:00", url: bad)]).models(calendar: ny)
        }
    }
}

@Test func dstGapThrows() {
    #expect(throws: BridgeError.nonexistentLocalTime(id: "x", text: "2026-03-08T02:30")) {
        try batch([item("x", start: "2026-03-08T02:30")]).models(calendar: ny)
    }
}

@Test func dstOverlapTakesFirstOccurrence() throws {
    let r = try batch([item(start: "2026-11-01T01:30")]).models(calendar: ny).reminders[0]
    // First 01:30 is EDT (UTC-4) = 05:30Z; the second is EST = 06:30Z.
    #expect(r.dueDate == Date(timeIntervalSince1970: 1_793_511_000)) // 2026-11-01T05:30:00Z
}

@Test func labelSanitize() {
    #expect(BridgeLabel.sanitize("Swift Course!") == "swift-course")
    #expect(BridgeLabel.sanitize("") == nil)
    #expect(BridgeLabel.sanitize(nil) == nil)
    #expect(BridgeLabel.sanitize("!!!") == nil)
    #expect(BridgeLabel.sanitize(String(repeating: "a", count: 40))?.count == 32)
}

@Test func labelAppending() {
    #expect(BridgeLabel.appending("swift-course", to: "read ch.1") == "read ch.1\n%swift-course")
    #expect(BridgeLabel.appending("swift-course", to: nil) == "%swift-course")
    #expect(BridgeLabel.appending("swift-course", to: "see %swift-course now") == "see %swift-course now")
    #expect(BridgeLabel.appending(nil, to: "x") == "x")
    #expect(BridgeLabel.appending("swift", to: "%swift-course") == "%swift-course\n%swift")
}

@Test func batchLabelAppendedToNotes() throws {
    let out = try batch([item(notes: "n")], label: "Swift Course").models(calendar: ny).reminders[0]
    #expect(out.notes == "n\n%swift-course")
}

@Test func decodesWithUnknownKeys() throws {
    let json = """
    {"v":1,"batch":"B","issuedAt":5,"extra":1,"items":[{"id":"a","kind":"event","title":"T","start":"2026-11-10T09:00","zzz":true,
     "recurrence":{"freq":"weekly","byDay":["mon"],"other":1}}]}
    """
    let b = try JSONDecoder().decode(BridgeBatch.self, from: Data(json.utf8))
    #expect(b.items[0].kind == .event)
    #expect(b.items[0].recurrence?.byDay == ["mon"])
    #expect(b.label == nil)
}

@Test func modelsKeepSuppliedItemIds() throws {
    let out = try batch([item("rem-1"), item("evt-1", kind: .event, start: "2026-11-10T09:00")]).models(calendar: ny)
    #expect(out.reminders.map(\.id) == ["rem-1"])
    #expect(out.events.map(\.id) == ["evt-1"])
}

@Test func modelsTwiceYieldIdenticalIds() throws {
    let b = batch([item("rem-1"), item("evt-1", kind: .event, start: "2026-11-10T09:00")])
    let a = try b.models(calendar: ny)
    let c = try b.models(calendar: ny)
    #expect(a == c)
}

@Test func intervalAndCountCaps() throws {
    func rec(_ i: Int?, _ c: Int?) -> BridgeRecurrence { BridgeRecurrence(freq: .daily, interval: i, byDay: nil, until: nil, count: c) }
    #expect(throws: BridgeError.badInterval(id: "x")) { try batch([item("x", recurrence: rec(Int.max, nil))]).models(calendar: ny) }
    #expect(throws: BridgeError.badInterval(id: "x")) { try batch([item("x", recurrence: rec(1000, nil))]).models(calendar: ny) }
    #expect(throws: BridgeError.badCount(id: "x")) { try batch([item("x", recurrence: rec(nil, Int.max))]).models(calendar: ny) }
    #expect(throws: BridgeError.badCount(id: "x")) { try batch([item("x", recurrence: rec(nil, 1001))]).models(calendar: ny) }
    let r = try batch([item("x", recurrence: rec(999, 1000))]).models(calendar: ny).reminders[0]
    #expect(r.recurrence?.interval == 999)
    #expect(r.recurrence?.count == 1000)
}

@Test func byDayNormalised() throws {
    func days(_ d: [String]) throws -> [Weekday]? {
        let rec = BridgeRecurrence(freq: .weekly, interval: nil, byDay: d, until: nil, count: nil)
        return try batch([item(recurrence: rec)]).models(calendar: ny).reminders[0].recurrence?.byDay
    }
    #expect(try days([]) == nil)
    #expect(try days(["tue", "tue"]) == [.tuesday])
    #expect(try days(["thu", "tue", "thu"]) == [.thursday, .tuesday])
}

@Test func impossibleDateWithTimeIsBadDate() {
    #expect(throws: BridgeError.badDate(id: "x", field: "start", text: "2026-02-30T10:00")) {
        try batch([item("x", start: "2026-02-30T10:00")]).models(calendar: ny)
    }
    #expect(throws: BridgeError.nonexistentLocalTime(id: "x", text: "2026-03-08T02:30")) {
        try batch([item("x", start: "2026-03-08T02:30")]).models(calendar: ny)
    }
}

@Test func titleWhitespaceCollapsed() throws {
    let r = try batch([item(title: "a\nb\t\tc\r\nd  e", notes: "x\ny")]).models(calendar: ny).reminders[0]
    #expect(r.title == "a b c d e")
    #expect(r.notes == "x\ny")
}
