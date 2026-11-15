// ios/Tests/StarkKitTests/ItemRouterTests.swift
import Testing
import Foundation
@testable import StarkKit

/// Records every call the router makes on the local store; nothing is persisted.
@MainActor
private final class FakeLocalStore: LocalItemStore {
    var calls: [String] = []
    var storedPlans: [PlanBlock] = []
    var convertResult = true
    var replacePlansResult = true

    func addEvent(_ event: Event) { calls.append("addEvent \(event.id)") }
    func addReminder(_ reminder: Reminder) { calls.append("addReminder \(reminder.id)") }
    func updateEvent(_ event: Event) { calls.append("updateEvent \(event.id) \(event.title)") }
    func updateReminder(_ reminder: Reminder) { calls.append("updateReminder \(reminder.id) \(reminder.title)") }
    func deleteEvent(id: String) { calls.append("deleteEvent \(id)") }
    func deleteReminder(id: String) { calls.append("deleteReminder \(id)") }
    func completeReminder(id: String, on date: Date, today: Date, now: Date) { calls.append("complete \(id)") }
    func uncompleteReminder(id: String) { calls.append("uncomplete \(id)") }
    func skipEvent(id: String, on date: Date) { calls.append("skipEvent \(id)") }
    func skipReminder(id: String, on date: Date, today: Date) { calls.append("skipReminder \(id)") }
    func setEventOutcome(id: String, on date: Date, outcome: EventOutcome?, now: Date) {
        calls.append("outcome \(id) \(outcome?.rawValue ?? "nil")")
    }
    func convertEvent(id: String, to reminder: Reminder) -> Bool {
        calls.append("convertEvent \(id)")
        return convertResult
    }
    func convertReminder(id: String, to event: Event) -> Bool {
        calls.append("convertReminder \(id)")
        return convertResult
    }
    func plans(on day: Date) -> [PlanBlock] { storedPlans }
    func replacePlans(on day: Date, with blocks: [PlanBlock]) -> Bool {
        calls.append("replacePlans \(blocks.map(\.id))")
        if replacePlansResult { storedPlans = blocks }
        return replacePlansResult
    }
}

private struct StubDestinations: DefaultDestinations {
    var calendarID: String?
    var listID: String?
}

/// Wraps the fake repository and fails `delete` on demand (the fake's `failNext` can only fail the
/// next call, and a convert makes two).
private actor DeleteFailingRepository: ItemRepository {
    let inner: FakeItemRepository
    var failDeletes = false
    init(inner: FakeItemRepository) { self.inner = inner }
    func setFailDeletes(_ value: Bool) { failDeletes = value }

    func addEvent(_ event: NewEvent, calendarID: String) async throws -> AppleItemRef {
        try await inner.addEvent(event, calendarID: calendarID)
    }
    func addReminder(_ reminder: NewReminder, listID: String) async throws -> AppleItemRef {
        try await inner.addReminder(reminder, listID: listID)
    }
    func details(_ ref: AppleItemRef) async throws -> ItemDetails { try await inner.details(ref) }
    func update(_ ref: AppleItemRef, event patch: EventPatch) async throws { try await inner.update(ref, event: patch) }
    func update(_ ref: AppleItemRef, reminder patch: ReminderPatch) async throws {
        try await inner.update(ref, reminder: patch)
    }
    func delete(_ ref: AppleItemRef) async throws {
        if failDeletes { throw ItemRepositoryError.saveFailed("delete refused") }
        try await inner.delete(ref)
    }
    func deleteOccurrence(_ ref: AppleItemRef, on date: Date) async throws {
        try await inner.deleteOccurrence(ref, on: date)
    }
    func complete(_ ref: AppleItemRef, on date: Date) async throws { try await inner.complete(ref, on: date) }
    func uncomplete(_ ref: AppleItemRef) async throws { try await inner.uncomplete(ref) }
    func writableCalendars() async throws -> [AppleCalendarInfo] { try await inner.writableCalendars() }
    func addBatch(events: [(event: NewEvent, calendarID: String)],
                  reminders: [(reminder: NewReminder, listID: String)]) async throws -> [AppleItemRef] {
        try await inner.addBatch(events: events, reminders: reminders)
    }
}

@MainActor
@Suite("ItemRouter")
struct ItemRouterTests {
    static let calendars = [
        AppleCalendarInfo(id: "cal", title: "Home", accountName: "iCloud", colorHex: nil, isReminderList: false),
        AppleCalendarInfo(id: "list", title: "Tasks", accountName: "iCloud", colorHex: nil, isReminderList: true),
    ]

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ day: Int, _ hour: Int = 9) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private final class Counter { var writes = 0 }

    private struct Harness {
        let router: ItemRouter
        let repo: FakeItemRepository
        let local: FakeLocalStore
        let sidecar: ItemSidecar
        let counter: Counter
    }

    private func harness(repo: (any ItemRepository)? = nil, fake: FakeItemRepository? = nil,
                         destinations: StubDestinations = StubDestinations(calendarID: "cal", listID: "list")) -> Harness {
        let fake = fake ?? FakeItemRepository(calendars: Self.calendars, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let local = FakeLocalStore()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("sidecar.json")
        let sidecar = ItemSidecar(fileURL: url, calendar: utc)
        let counter = Counter()
        let router = ItemRouter(repository: repo ?? fake, local: local, sidecar: sidecar,
                                destinations: destinations, calendar: utc,
                                now: { Date(timeIntervalSince1970: 1_800_000_000) })
        router.onDidWrite = { counter.writes += 1 }
        return Harness(router: router, repo: fake, local: local, sidecar: sidecar, counter: counter)
    }

    // MARK: Origin

    @Test("an apple- model id routes to Apple, a Stark UUID to the local store")
    func originFromID() {
        #expect(ItemOrigin(id: "apple-AB-12:x", kind: .event) == .apple(AppleItemRef(kind: .event, identifier: "AB-12:x")))
        #expect(ItemOrigin(id: "apple-R1", kind: .reminder) == .apple(AppleItemRef(kind: .reminder, identifier: "R1")))
        #expect(ItemOrigin(id: UUID().uuidString, kind: .event) == .local)
        #expect(ItemOrigin(id: "apple-", kind: .event) == .local)
    }

    @Test("an agenda row routes by its own ref")
    func originFromAgendaItem() {
        let source = AppleSource(calendarID: "c", calendarTitle: "C", colorHex: nil, isReminder: true)
        let apple = AgendaItem(kind: .reminder(Reminder(id: "apple-9F-8E", title: "t", dueDate: at(1))),
                               occurrence: at(1), displayDate: at(1), isOverdue: false, appleSource: source)
        #expect(ItemOrigin(item: apple) == .apple(AppleItemRef(kind: .reminder, identifier: "9F-8E")))
        let own = AgendaItem(kind: .event(Event(title: "t", start: at(1))), occurrence: at(1),
                             displayDate: at(1), isOverdue: false)
        #expect(ItemOrigin(item: own) == .local)
    }

    // MARK: Add

    @Test("add goes to Apple's default calendar and list, never to the local store")
    func addGoesToApple() async throws {
        let h = harness()
        let eventRef = try await h.router.add(event: Event(title: "Dentist", start: at(3, 10), end: at(3, 11)))
        let reminderRef = try await h.router.add(reminder: Reminder(title: "Call", dueDate: at(3)), dueHasTime: false)
        #expect(h.local.calls.isEmpty)
        let e = try await h.repo.details(eventRef)
        #expect(e.event?.title == "Dentist" && e.calendarID == "cal" && e.event?.end == at(3, 11))
        let r = try await h.repo.details(reminderRef)
        #expect(r.reminder?.title == "Call" && r.calendarID == "list" && r.dueHasTime == false)
        #expect(h.counter.writes == 2)
    }

    @Test("add without a default destination throws a readable error and writes nothing")
    func addWithoutDestination() async {
        let h = harness(destinations: StubDestinations(calendarID: nil, listID: nil))
        await #expect(throws: ItemRouterError.noDefaultDestination(.event)) {
            try await h.router.add(event: Event(title: "x", start: at(3)))
        }
        await #expect(throws: ItemRouterError.noDefaultDestination(.reminder)) {
            try await h.router.add(reminder: Reminder(title: "x", dueDate: at(3)))
        }
        #expect(await h.repo.itemCount == 0)
        #expect(h.local.calls.isEmpty)
        #expect(h.counter.writes == 0)
        #expect(!ItemRouterError.noDefaultDestination(.event).message.isEmpty)
    }

    @Test("a failing Apple write surfaces as ItemRouterError, leaves state untouched and does not fire onDidWrite")
    func appleFailureSurfaces() async throws {
        let h = harness()
        let ref = try await h.router.add(reminder: Reminder(title: "Call", dueDate: at(3)))
        h.counter.writes = 0
        await h.repo.failNext("disk full")
        do {
            try await h.router.complete(id: "apple-\(ref.identifier)", on: at(3))
            Issue.record("expected a throw")
        } catch let error as ItemRouterError {
            #expect(error == .apple(.saveFailed("disk full")))
            #expect(error.message.contains("disk full"))
        }
        #expect(try await h.repo.details(ref).reminder?.isCompleted == false)
        #expect(h.counter.writes == 0)
    }

    // MARK: Local routing

    @Test("Stark ids go to the local store and do not fire onDidWrite")
    func localRouting() async throws {
        let h = harness()
        let id = UUID().uuidString
        try await h.router.complete(id: id, on: at(3))
        try await h.router.uncomplete(id: id)
        try await h.router.skipEvent(id: id, on: at(3))
        try await h.router.skipReminder(id: id, on: at(3))
        try await h.router.setEventOutcome(id: id, on: at(3), outcome: .attended)
        try await h.router.deleteEvent(id: id)
        try await h.router.deleteReminder(id: id)
        let original = Event(id: id, title: "old", start: at(3))
        var edited = original
        edited.title = "new"
        try await h.router.update(event: edited, original: original)
        #expect(h.local.calls == [
            "complete \(id)", "uncomplete \(id)", "skipEvent \(id)", "skipReminder \(id)",
            "outcome \(id) attended", "deleteEvent \(id)", "deleteReminder \(id)", "updateEvent \(id) new",
        ])
        #expect(await h.repo.itemCount == 0)
        #expect(h.counter.writes == 0)
    }

    @Test("a local convert the store refuses throws a readable error")
    func localConvertRefused() async {
        let h = harness()
        h.local.convertResult = false
        await #expect(throws: ItemRouterError.self) {
            try await h.router.convertEvent(id: UUID().uuidString, to: Reminder(title: "x"))
        }
    }

    // MARK: Apple operations

    @Test("complete and uncomplete an Apple reminder go to the repository")
    func appleCompleteUncomplete() async throws {
        let h = harness()
        let ref = try await h.router.add(reminder: Reminder(title: "Call", dueDate: at(3)))
        let id = "apple-\(ref.identifier)"
        try await h.router.complete(id: id, on: at(3))
        #expect(try await h.repo.details(ref).reminder?.isCompleted == true)
        try await h.router.uncomplete(id: id)
        #expect(try await h.repo.details(ref).reminder?.isCompleted == false)
        #expect(h.local.calls.isEmpty)
        #expect(h.counter.writes == 3)
    }

    @Test("skipReminder on an Apple reminder is unsupported and changes nothing")
    func skipAppleReminderUnsupported() async throws {
        let h = harness()
        let ref = try await h.router.add(reminder: Reminder(title: "Gym", dueDate: at(3),
                                                            recurrence: RecurrenceRule(frequency: .daily)))
        h.counter.writes = 0
        do {
            try await h.router.skipReminder(id: "apple-\(ref.identifier)", on: at(3))
            Issue.record("expected a throw")
        } catch let error as ItemRouterError {
            guard case .unsupported = error else { Issue.record("wrong error \(error)"); return }
            #expect(!error.message.isEmpty)
        }
        let r = try await h.repo.details(ref).reminder
        #expect(r?.dueDate == at(3) && r?.exceptionDates.isEmpty == true)
        #expect(h.local.calls.isEmpty && h.counter.writes == 0)
    }

    @Test("skipEvent on an Apple series deletes only that occurrence")
    func skipAppleEventDeletesOccurrence() async throws {
        let h = harness()
        let ref = try await h.router.add(event: Event(title: "Standup", start: at(2), recurrence: RecurrenceRule(frequency: .daily)))
        try await h.router.skipEvent(id: "apple-\(ref.identifier)", on: at(4))
        let e = try await h.repo.details(ref).event
        #expect(e?.exceptionDates == [at(4)])
        #expect(e?.recurrence == RecurrenceRule(frequency: .daily))
        #expect(h.local.calls.isEmpty)
    }

    @Test("delete an Apple event removes it")
    func deleteApple() async throws {
        let h = harness()
        let ref = try await h.router.add(event: Event(title: "x", start: at(3)))
        try await h.router.deleteEvent(id: "apple-\(ref.identifier)")
        await #expect(throws: ItemRepositoryError.notFound) { try await h.repo.details(ref) }
        #expect(h.local.calls.isEmpty)
    }

    @Test("update of an Apple event writes back only the changed fields")
    func updateAppleWritesOnlyChanges() async throws {
        let h = harness()
        let ref = try await h.router.add(event: Event(title: "Lunch", notes: "n", start: at(3, 12), end: at(3, 13),
                                                      location: "Cafe", recurrence: RecurrenceRule(frequency: .weekly)))
        // The edit sheet starts from the real item, as loaded through the router.
        let details = try await h.router.details(id: "apple-\(ref.identifier)", kind: .event)
        let original = try #require(details.event)
        #expect(original.id == "apple-\(ref.identifier)")
        var edited = original
        edited.title = "Long lunch"
        edited.location = nil
        try await h.router.update(event: edited, original: original)
        let e = try await h.repo.details(ref).event
        #expect(e?.title == "Long lunch" && e?.location == nil)
        #expect(e?.notes == "n" && e?.start == at(3, 12) && e?.recurrence == RecurrenceRule(frequency: .weekly))
        #expect(h.local.calls.isEmpty)
    }

    @Test("an event patch diff holds only what changed")
    func eventPatchDiff() {
        let a = Event(id: "x", title: "A", notes: "n", start: at(3, 9), end: at(3, 10), location: "L",
                      recurrence: RecurrenceRule(frequency: .daily), url: "u")
        #expect(EventPatch(from: a, to: a) == EventPatch())
        var b = a
        b.title = "B"
        b.notes = nil
        b.end = at(3, 11)
        b.recurrence = nil
        #expect(EventPatch(from: a, to: b) == EventPatch(title: "B", notes: .clear, end: .set(at(3, 11)), recurrence: .clear))
    }

    @Test("a reminder patch diff holds only what changed, plus the caller's date-only and URL changes")
    func reminderPatchDiff() {
        let a = Reminder(id: "x", title: "A", dueDate: at(3), priority: 1)
        #expect(ReminderPatch(from: a, to: a) == ReminderPatch())
        var b = a
        b.dueDate = at(4)
        b.priority = nil
        #expect(ReminderPatch(from: a, to: b, dueHasTime: false, url: .set("u"))
                == ReminderPatch(due: .set(at(4)), dueHasTime: false, priority: .clear, url: .set("u")))
    }

    @Test("update of an Apple reminder applies the diff")
    func updateAppleReminder() async throws {
        let h = harness()
        let ref = try await h.router.add(reminder: Reminder(title: "Call", dueDate: at(3), priority: 5))
        let original = try #require(try await h.router.details(id: "apple-\(ref.identifier)", kind: .reminder).reminder)
        var edited = original
        edited.title = "Call mom"
        try await h.router.update(reminder: edited, original: original)
        let r = try await h.repo.details(ref).reminder
        #expect(r?.title == "Call mom" && r?.priority == 5 && r?.dueDate == at(3))
    }

    // MARK: Outcomes

    @Test("an outcome on an Apple event goes to the sidecar, dated by the occurrence")
    func appleOutcomeInSidecar() async throws {
        let h = harness()
        try await h.router.setEventOutcome(id: "apple-EV1", on: at(5, 8), outcome: .skipped)
        let record = try await h.sidecar.outcome(for: "EV1", externalID: nil, on: at(5, 20))
        #expect(record?.outcome == .skipped && record?.date == at(5, 8))
        #expect(h.local.calls.isEmpty)
        #expect(h.counter.writes == 1)
        try await h.router.setEventOutcome(id: "apple-EV1", on: at(5, 8), outcome: nil)
        #expect(try await h.sidecar.outcome(for: "EV1", externalID: nil, on: at(5)) == nil)
    }

    // MARK: Plans

    @Test("plans for an Apple reminder go to the sidecar, local ones to the store, and plans(on:) merges both")
    func plansSplitAndMerge() async throws {
        let h = harness()
        let apple = PlanBlock(id: "pa", reminderID: "apple-R1", occurrence: at(6), start: at(6, 9), minutes: 30)
        let localID = UUID().uuidString
        let own = PlanBlock(id: "pl", reminderID: localID, occurrence: at(6), start: at(6, 10), minutes: 30)
        try await h.router.replacePlans(on: at(6), with: [apple, own])
        #expect(h.local.calls == ["replacePlans [\"pl\"]"])
        let stored = try await h.sidecar.plans(on: at(6))
        #expect(stored.map(\.reminderID) == ["R1"])
        let merged = try await h.router.plans(on: at(6))
        #expect(Set(merged.map(\.id)) == ["pa", "pl"])
        #expect(merged.first { $0.id == "pa" }?.reminderID == "apple-R1")
    }

    @Test("a refused local plan save throws")
    func localPlansRefused() async {
        let h = harness()
        h.local.replacePlansResult = false
        let own = PlanBlock(id: "pl", reminderID: UUID().uuidString, occurrence: at(6), start: at(6, 10), minutes: 30)
        await #expect(throws: ItemRouterError.self) { try await h.router.replacePlans(on: at(6), with: [own]) }
    }

    // MARK: Convert

    @Test("convert an Apple event to a reminder creates the reminder, deletes the event and remaps plans")
    func convertAppleEvent() async throws {
        let h = harness()
        let ref = try await h.router.add(event: Event(title: "Pay rent", start: at(7)))
        try await h.sidecar.replacePlans(on: at(7), with: [
            PlanBlock(id: "b", reminderID: ref.identifier, occurrence: at(7), start: at(7, 9), minutes: 15),
        ])
        h.counter.writes = 0
        let converted = try await h.router.convertEvent(id: "apple-\(ref.identifier)",
                                                        to: Reminder(title: "Pay rent", dueDate: at(7)), dueHasTime: false)
        let newRef = try #require(converted)
        #expect(newRef.kind == .reminder)
        await #expect(throws: ItemRepositoryError.notFound) { try await h.repo.details(ref) }
        let r = try await h.repo.details(newRef)
        #expect(r.reminder?.title == "Pay rent" && r.calendarID == "list")
        #expect(try await h.sidecar.plans(on: at(7)).map(\.reminderID) == [newRef.identifier])
        #expect(h.local.calls.isEmpty)
        #expect(h.counter.writes == 1)
    }

    @Test("convert an Apple reminder to an event creates the event in the default calendar and deletes the reminder")
    func convertAppleReminder() async throws {
        let h = harness()
        let ref = try await h.router.add(reminder: Reminder(title: "Gym", dueDate: at(8)))
        let converted = try await h.router.convertReminder(id: "apple-\(ref.identifier)",
                                                           to: Event(title: "Gym", start: at(8, 18), end: at(8, 19)))
        let newRef = try #require(converted)
        #expect(newRef.kind == .event)
        let e = try await h.repo.details(newRef)
        #expect(e.event?.title == "Gym" && e.calendarID == "cal")
        await #expect(throws: ItemRepositoryError.notFound) { try await h.repo.details(ref) }
    }

    @Test("a failing create leaves the original untouched")
    func convertCreateFails() async throws {
        let h = harness()
        let ref = try await h.router.add(event: Event(title: "Pay rent", start: at(7)))
        h.counter.writes = 0
        await h.repo.failNext("nope")
        await #expect(throws: ItemRouterError.apple(.saveFailed("nope"))) {
            try await h.router.convertEvent(id: "apple-\(ref.identifier)", to: Reminder(title: "Pay rent", dueDate: at(7)))
        }
        #expect(try await h.repo.details(ref).event?.title == "Pay rent")
        #expect(await h.repo.itemCount == 1)
        #expect(h.counter.writes == 0)
    }

    @Test("a failing delete after the create keeps both and reports it")
    func convertDeleteFails() async throws {
        let fake = FakeItemRepository(calendars: Self.calendars)
        let wrapper = DeleteFailingRepository(inner: fake)
        let h = harness(repo: wrapper, fake: fake)
        let ref = try await h.router.add(event: Event(title: "Pay rent", start: at(7)))
        await wrapper.setFailDeletes(true)
        do {
            _ = try await h.router.convertEvent(id: "apple-\(ref.identifier)", to: Reminder(title: "Pay rent", dueDate: at(7)))
            Issue.record("expected a throw")
        } catch let error as ItemRouterError {
            guard case .convertedButOriginalKept = error else { Issue.record("wrong error \(error)"); return }
            #expect(error.message.contains("delete refused"))
        }
        #expect(await fake.itemCount == 2)
        #expect(try await fake.details(ref).event?.title == "Pay rent")
    }

    @Test("convert of an Apple item without a default destination throws and changes nothing")
    func convertWithoutDestination() async throws {
        let fake = FakeItemRepository(calendars: Self.calendars)
        let ref = try await fake.addEvent(NewEvent(title: "x", start: at(7)), calendarID: "cal")
        let h = harness(fake: fake, destinations: StubDestinations(calendarID: "cal", listID: nil))
        await #expect(throws: ItemRouterError.noDefaultDestination(.reminder)) {
            try await h.router.convertEvent(id: "apple-\(ref.identifier)", to: Reminder(title: "x"))
        }
        #expect(await fake.itemCount == 1)
    }
}
