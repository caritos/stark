// ios/Tests/StarkKitTests/PlannerStoreImportHidingTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("PlannerStore import hiding")
struct PlannerStoreImportHidingTests {
    private let today = DateMath.date(from: "2026-09-01")
    private let eventDay = DateMath.date(from: "2026-09-02")

    @MainActor
    private func makeStore() -> (PlannerStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = PlannerFile(directory: root.appendingPathComponent("docs"), pendingDirectory: root.appendingPathComponent("pending"))
        let store = PlannerStore(file: file)
        let range = AgendaWindow.loadRange(around: today)
        store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
        return (store, root)
    }

    /// An event "Dentist" (e1), a reminder "Call" (r1) with a plan block, and a kept reminder (r2).
    @MainActor
    private func seed(_ store: PlannerStore) {
        store.addEvent(Event(id: "e1", title: "Dentist", start: eventDay))
        store.addReminder(Reminder(id: "r1", title: "Call", dueDate: eventDay))
        store.addReminder(Reminder(id: "r2", title: "Keep", dueDate: eventDay))
        _ = store.replacePlans(on: eventDay, with: [
            PlanBlock(id: "p1", reminderID: "r1", occurrence: eventDay, start: eventDay.addingTimeInterval(9 * 3600), minutes: 30),
        ])
    }

    @Test("an imported event and reminder disappear from agenda, search, density, tray and review")
    @MainActor
    func importedEventAndReminderDisappearFromAgendaSearchDensityTrayAndReview() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        seed(store)
        let range = AgendaWindow.range(around: today)

        // Before hiding, every reader sees the items.
        let before = buildAgendaItems(events: store.events, reminders: store.reminders, in: range, today: today)
        #expect(Set(before.map(\.title)) == ["Dentist", "Call", "Keep"])
        #expect(SearchResults.find(events: store.events, reminders: store.reminders, query: "Dentist", today: today).count == 1)

        store.setImportedIDs(["e1", "r1"])

        let agenda = buildAgendaItems(events: store.events, reminders: store.reminders, in: range, today: today)
        #expect(Set(agenda.map(\.title)) == ["Keep"])

        #expect(SearchResults.find(events: store.events, reminders: store.reminders, query: "Dentist", today: today).isEmpty)
        #expect(SearchResults.find(events: store.events, reminders: store.reminders, query: "Call", today: today).isEmpty)
        #expect(SearchResults.find(events: store.events, reminders: store.reminders, query: "Keep", today: today).count == 1)

        let month = gridDensity(events: store.events, reminders: store.reminders, month: YearMonth(year: 2026, month0: 8),
                                today: today, plans: store.plans)
        #expect(month["2026-09-02"] == DayDensity(tasks: 1, events: 0))
        let year = yearDensity(events: store.events, reminders: store.reminders, year: 2026, today: today, plans: store.plans)
        #expect(year["2026-09-02"] == DayDensity(tasks: 1, events: 0))

        let model = DayPlanModel.make(day: eventDay, events: store.events, reminders: store.reminders,
                                      plans: store.plans, today: today)
        #expect(Set((model.tray + model.timed + model.events + model.allDayEvents).map(\.title)).isDisjoint(with: ["Dentist", "Call"]))
        #expect(model.blocks.isEmpty)

        let review = WeeklyReview.summary(events: store.events, reminders: store.reminders,
                                          weekStarting: DateMath.date(from: "2026-08-30"), today: today)
        #expect(Set((review.open + review.completed).map(\.title)) == ["Keep"])
    }

    @Test("plans of imported reminders are hidden")
    @MainActor
    func importedReminderPlansAreHidden() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        seed(store)
        #expect(store.plans.map(\.id) == ["p1"])
        store.setImportedIDs(["r1"])
        #expect(store.plans.isEmpty)
        #expect(store.plans(on: eventDay).isEmpty)
    }

    @Test("a not-imported item stays editable and deletable")
    @MainActor
    func unimportedItemStaysEditableAndDeletable() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        seed(store)
        store.setImportedIDs(["e1", "r1"])
        var keep = store.reminders.first { $0.id == "r2" }!
        keep.title = "Kept, renamed"
        store.updateReminder(keep)
        #expect(store.reminders.map(\.title) == ["Kept, renamed"])
        store.deleteReminder(id: "r2")
        #expect(store.reminders.isEmpty)
        #expect(store.allReminders.map(\.id) == ["r1"])
    }

    @Test("allEvents, allReminders and allPlans still contain hidden items")
    @MainActor
    func allEventsStillContainHiddenItems() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        seed(store)
        store.setImportedIDs(["e1", "r1"])
        #expect(store.events.isEmpty)
        #expect(store.allEvents.map(\.id) == ["e1"])
        #expect(Set(store.allReminders.map(\.id)) == ["r1", "r2"])
        #expect(store.allPlans.map(\.id) == ["p1"])
    }

    @Test("a row carries the not-imported flag from its local id")
    @MainActor
    func rowCarriesNotImportedFlag() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        seed(store)
        let range = AgendaWindow.range(around: today)
        let plain = buildAgendaItems(events: store.events, reminders: store.reminders, in: range, today: today)
        #expect(plain.allSatisfy { !$0.isNotImported })
        let marked = buildAgendaItems(events: store.events, reminders: store.reminders, in: range, today: today)
            .marked(notImported: ["e1", "r2"])
        #expect(Set(marked.filter(\.isNotImported).map(\.title)) == ["Dentist", "Keep"])
        #expect(marked.first { $0.title == "Call" }?.isNotImported == false)
        // Not part of the id.
        #expect(plain.map(\.id) == marked.map(\.id))
    }

    @Test("setting the ids back to empty shows them again")
    @MainActor
    func settingIdsBackToEmptyShowsThemAgain() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        seed(store)
        store.setImportedIDs(["e1", "r1"])
        store.setImportedIDs([])
        #expect(store.events.map(\.id) == ["e1"])
        #expect(Set(store.reminders.map(\.id)) == ["r1", "r2"])
        #expect(store.plans.map(\.id) == ["p1"])
    }

    @Test("saving the planner for a day keeps hidden plan blocks, in memory and on disk")
    @MainActor
    func replacePlansKeepsHiddenPlans() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func makeFile() -> PlannerFile {
            PlannerFile(directory: root.appendingPathComponent("docs"), pendingDirectory: root.appendingPathComponent("pending"))
        }
        let store = PlannerStore(file: makeFile())
        let range = AgendaWindow.loadRange(around: today)
        store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
        seed(store)
        store.setImportedIDs(["r1"])
        let visible = PlanBlock(id: "p2", reminderID: "r2", occurrence: eventDay,
                                start: eventDay.addingTimeInterval(11 * 3600), minutes: 30)
        #expect(store.replacePlans(on: eventDay, with: [visible]))
        #expect(Set(store.allPlans.map(\.id)) == ["p1", "p2"])
        #expect(store.plans.map(\.id) == ["p2"])

        let fresh = PlannerStore(file: makeFile())
        fresh.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
        #expect(Set(fresh.allPlans.map(\.id)) == ["p1", "p2"])
        store.setImportedIDs([])
        #expect(Set(store.plans.map(\.id)) == ["p1", "p2"])
    }

    @Test("the not-imported flag survives applyPlans and the Apple merge, and marked() sets it on synthesised rows")
    @MainActor
    func notImportedFlagSurvivesPipeline() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        seed(store)
        let range = AgendaWindow.range(around: today)
        let items = buildAgendaItems(events: store.events, reminders: store.reminders, in: range, today: today)
            .marked(notImported: ["r1"])
        let planned = applyPlans(items, plans: store.plans, today: today)
        let call = planned.filter { $0.title == "Call" }
        #expect(!call.isEmpty && call.allSatisfy { $0.plan != nil || $0.isNotImported })
        #expect(planned.first { $0.title == "Call" && $0.plan != nil }?.isNotImported == true)
        #expect(planned.first { $0.title == "Keep" }?.isNotImported == false)

        let merged = mergeAppleItems(planned, snapshot: .empty, in: range, today: today)
        #expect(merged.first { $0.title == "Call" && $0.plan != nil }?.isNotImported == true)

        // Synthesised planned row (the reminder is outside the agenda items) is marked by the helper.
        let synthesised = applyPlans([], plans: store.plans, today: today, reminders: store.reminders)
            .marked(notImported: ["r1"])
        #expect(synthesised.first { $0.title == "Call" }?.isNotImported == true)
        let search = SearchResults.find(events: store.events, reminders: store.reminders, query: "Keep", today: today)
            .marked(notImported: ["r2"])
        #expect(search.first?.isNotImported == true)
    }

    @Test("loadAllMonths surfaces a directory listing failure instead of treating it as no months")
    @MainActor
    func loadAllMonthsSurfacesListingFailure() async throws {
        let (store, root) = makeStore()
        let docs = root.appendingPathComponent("docs")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: docs.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o311], ofItemAtPath: docs.path)
        store.error = nil
        await store.loadAllMonths()
        #expect(store.error != nil)
    }
}
