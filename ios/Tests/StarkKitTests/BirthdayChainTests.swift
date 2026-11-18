import Foundation
import Testing
@testable import StarkKit

/// The whole path a Birthdays-calendar event takes: snapshot with birth years -> the owner's
/// calendar selection -> the agenda merge / Search, and the lookup cache the overlay model uses.
@Suite struct BirthdayChainTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ d: Int, month: Int = 6) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: month, day: d))!
    }

    private let birthdays = AppleCalendarInfo(id: "bday", title: "Birthdays", accountName: "Other",
                                              colorHex: nil, isReminderList: false, isWritable: false,
                                              isBirthdayCalendar: true)

    private func annSnapshot(years: [String: Int]) -> AppleSnapshot {
        let event = AppleCalendarEvent(id: "e1", title: "Ann's Birthday", notes: nil, location: nil, url: nil,
                                       start: date(10), end: nil, isAllDay: true, calendar: birthdays,
                                       birthdayContactID: "c1")
        return AppleSnapshot(events: [event], reminders: [], birthYears: years)
    }

    @Test func filteredKeepsBirthYears() {
        let filtered = AppleSelection().filtered(annSnapshot(years: ["c1": 1990]))
        #expect(filtered.birthYears == ["c1": 1990])
    }

    @Test func chainFromSnapshotThroughSelectionToAgendaNote() {
        let filtered = AppleSelection(excludedIDs: ["other"]).filtered(annSnapshot(years: ["c1": 1990]))
        let rows = mergeAppleItems([], snapshot: filtered, in: date(1)...date(30), today: date(15), calendar: Self.cal)
        #expect(rows.count == 1)
        #expect(rows[0].milestone?.kind == .birthday)
        #expect(rows[0].milestone?.note == "Turns 36")
    }

    @Test func hiddenBirthdaysCalendarNeedsNoContactIDs() {
        let filtered = AppleSelection(excludedIDs: ["bday"]).filtered(annSnapshot(years: [:]))
        #expect(filtered.events.isEmpty)
        #expect(BirthYear.contactIDsNeeded(in: filtered.events).isEmpty)
    }

    @Test func searchResultForBirthdayEventHasAge() {
        let results = SearchResults.find(events: [], reminders: [], apple: annSnapshot(years: ["c1": 1990]),
                                         query: "ann", today: date(15))
        #expect(results.count == 1)
        #expect(results[0].milestone?.kind == .birthday)
        #expect(results[0].milestone?.years == 36)
        #expect(results[0].milestone?.note == "Turns 36")
    }

    @Test func searchResultWithoutYearIsCakeOnly() {
        let results = SearchResults.find(events: [], reminders: [], apple: annSnapshot(years: [:]),
                                         query: "ann", today: date(15))
        #expect(results[0].milestone?.kind == .birthday)
        #expect(results[0].milestone?.years == nil)
    }
}

/// Counts calls and the most lookups ever running at once.
private actor CountingLookupState {
    var calls: [Set<String>] = []
    var running = 0
    var maxRunning = 0
    func begin(_ ids: Set<String>) { calls.append(ids); running += 1; maxRunning = max(maxRunning, running) }
    func end() { running -= 1 }
}

private struct CountingLookup: BirthYearLookup {
    let state = CountingLookupState()
    let years: [String: Int]
    func birthYears(forContactIDs ids: Set<String>) async -> [String: Int] {
        await state.begin(ids)
        try? await Task.sleep(nanoseconds: 20_000_000)
        await state.end()
        return years.filter { ids.contains($0.key) }
    }
}

@Suite struct MilestoneChipTitleTests {
    @Test func chipTitleAppendsTheNote() {
        #expect(MilestoneInfo(kind: .birthday, years: 36).chipTitle("Ann's Birthday") == "Ann's Birthday · Turns 36")
        #expect(MilestoneInfo(kind: .anniversary, years: 1).chipTitle("Wedding") == "Wedding · 1 year")
    }

    @Test func chipTitleWithoutYearsIsTheTitle() {
        #expect(MilestoneInfo(kind: .birthday, years: nil).chipTitle("Ann's Birthday") == "Ann's Birthday")
    }
}

@MainActor @Suite struct BirthYearCacheTests {
    @Test func emptyIDsNeverCallTheLookup() async {
        let lookup = CountingLookup(years: [:])
        let cache = BirthYearCache(lookup: lookup)
        #expect(await cache.load([]) == false)
        #expect(await lookup.state.calls.isEmpty)
    }

    @Test func loadsOnceAndAnswersFromTheCache() async {
        let lookup = CountingLookup(years: ["c1": 1990])
        let cache = BirthYearCache(lookup: lookup)
        #expect(cache.years(for: ["c1", "c2"]).isEmpty)
        #expect(await cache.load(["c1", "c2"]) == true)
        #expect(cache.years(for: ["c1", "c2"]) == ["c1": 1990])
        // A year-less contact is remembered too: a reload asks Contacts nothing.
        #expect(cache.missing(from: ["c1", "c2"]).isEmpty)
        #expect(await cache.load(["c1", "c2"]) == false)
        #expect(await lookup.state.calls == [["c1", "c2"]])
    }

    @Test func onlyNewIDsAreLookedUp() async {
        let lookup = CountingLookup(years: ["c1": 1990, "c3": 1985])
        let cache = BirthYearCache(lookup: lookup)
        _ = await cache.load(["c1"])
        _ = await cache.load(["c1", "c3"])
        #expect(await lookup.state.calls == [["c1"], ["c3"]])
        #expect(cache.years(for: ["c1", "c3"]) == ["c1": 1990, "c3": 1985])
    }

    @Test func overlappingLoadsNeverRunTwoLookupsAtOnce() async {
        let lookup = CountingLookup(years: ["c1": 1990])
        let cache = BirthYearCache(lookup: lookup)
        async let a = cache.load(["c1"])
        async let b = cache.load(["c1"])
        _ = await (a, b)
        #expect(await lookup.state.maxRunning == 1)
        // The second waited for the first and found nothing left to ask.
        #expect(await lookup.state.calls == [["c1"]])
    }

    @Test func forgettingMissesAsksAgainForThemOnly() async {
        let lookup = CountingLookup(years: ["c1": 1990])
        let cache = BirthYearCache(lookup: lookup)
        _ = await cache.load(["c1", "c2"])
        cache.forgetMissing()
        #expect(cache.missing(from: ["c1", "c2"]) == ["c2"])
        #expect(cache.years(for: ["c1"]) == ["c1": 1990])
    }
}
