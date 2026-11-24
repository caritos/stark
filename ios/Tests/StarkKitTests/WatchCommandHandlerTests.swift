import Foundation
import Testing
@testable import StarkKit

/// An `AppliedIDStore` in memory (the handler test's twin of the UserDefaults one).
final class InMemoryAppliedIDStore: AppliedIDStore, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<UUID> = []

    func contains(_ id: UUID) -> Bool { lock.withLock { ids.contains(id) } }
    func insert(_ id: UUID) { _ = lock.withLock { ids.insert(id) } }
}

@Suite("WatchCommandHandler")
struct WatchCommandHandlerTests {
    static let home = AppleCalendarInfo(id: "C1", title: "Home", accountName: "iCloud", colorHex: nil,
                                        isReminderList: false)
    static let inbox = AppleCalendarInfo(id: "L1", title: "Inbox", accountName: "iCloud", colorHex: nil,
                                         isReminderList: true)
    static let phoneOnly = AppleCalendarInfo(id: "C2", title: "Calendar", accountName: "On My iPhone",
                                             colorHex: nil, isReminderList: false, isLocalOnly: true)

    static var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        gregorian.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func repository() -> FakeItemRepository {
        let now = date(2026, 11, 24, 7)
        return FakeItemRepository(calendars: [home, inbox, phoneOnly], now: { now })
    }

    static func handler(_ repository: FakeItemRepository,
                        calendar: AppleCalendarInfo? = home, list: AppleCalendarInfo? = inbox,
                        applied: AppliedIDStore = InMemoryAppliedIDStore()) -> WatchCommandHandler {
        WatchCommandHandler(repository: repository, destinations: { (calendar, list) }, applied: applied)
    }

    static func envelope(_ command: WatchCommand) -> WatchEnvelope {
        WatchEnvelope(id: UUID(), sentAt: date(2026, 11, 24, 9), command: command)
    }

    static func eventDraft(start: Date, end: Date?, allDay: Bool = false) -> WatchAddDraft {
        WatchAddDraft(kind: .event, title: "Lunch", start: start, end: end, isAllDay: allDay,
                      recurrence: nil, summary: "")
    }

    @Test("complete calls the repository on the occurrence")
    func completeCallsTheRepositoryOnTheOccurrence() async throws {
        let repository = Self.repository()
        let due = Self.date(2026, 11, 24, 8)
        let ref = try await repository.addReminder(
            NewReminder(title: "Pills", due: due, recurrence: RecurrenceRule(frequency: .daily)), listID: "L1")
        let handler = Self.handler(repository)

        let reply = await handler.handle(Self.envelope(.complete(identifier: ref.identifier, externalID: nil,
                                                                  occurrence: due)))

        #expect(reply == .done(notice: nil, warning: nil))
        let details = try await repository.details(ref)
        #expect(details.reminder?.dueDate == Self.date(2026, 11, 25, 8))
        // A completed copy for the occurrence was left behind.
        #expect(await repository.allReminders.contains { $0.isCompleted && $0.dueDate == due })
    }

    @Test("add event uses the phone's default calendar and names it")
    func addEventUsesThePhonesDefaultCalendarAndNamesIt() async throws {
        let repository = Self.repository()
        let handler = Self.handler(repository)
        let start = Self.date(2026, 11, 25, 13)

        let reply = await handler.handle(Self.envelope(.add(Self.eventDraft(start: start,
                                                                            end: start.addingTimeInterval(3600)))))

        #expect(reply == .done(notice: "Added to Home · iCloud", warning: nil))
        let ref = AppleItemRef(kind: .event, identifier: "fake-1")
        let details = try await repository.details(ref)
        #expect(details.calendarID == "C1")
        #expect(details.event?.title == "Lunch")
        #expect(details.event?.start == start)
        #expect(details.event?.end == start.addingTimeInterval(3600))
        #expect(details.event?.isAllDay == false)
    }

    @Test("an all-day event from the watch is stored as one day, as the Add screen stores it")
    func anAllDayDraftIsNormalizedAsTheAddScreenDoes() async throws {
        let repository = Self.repository()
        let handler = Self.handler(repository)
        let start = Self.date(2026, 11, 25)
        // The draft carries start + 1 h as its end (WatchAddDraft.make).
        let reply = await handler.handle(Self.envelope(.add(Self.eventDraft(start: start,
                                                                            end: start.addingTimeInterval(3600),
                                                                            allDay: true))))

        #expect(reply == .done(notice: "Added to Home · iCloud", warning: nil))
        let details = try await repository.details(AppleItemRef(kind: .event, identifier: "fake-1"))
        #expect(details.event?.isAllDay == true)
        #expect(details.event?.start == start)
        #expect(details.event?.end == nil)
    }

    @Test("add reminder uses the default list")
    func addReminderUsesTheDefaultList() async throws {
        let repository = Self.repository()
        let handler = Self.handler(repository)
        let due = Self.date(2026, 11, 26)
        let draft = WatchAddDraft(kind: .reminder, title: "Pay rent", start: due, end: nil, isAllDay: true,
                                  recurrence: RecurrenceRule(frequency: .monthly), summary: "")

        let reply = await handler.handle(Self.envelope(.add(draft)))

        #expect(reply == .done(notice: "Added to Inbox · iCloud", warning: nil))
        let details = try await repository.details(AppleItemRef(kind: .reminder, identifier: "fake-1"))
        #expect(details.calendarID == "L1")
        #expect(details.reminder?.title == "Pay rent")
        #expect(details.reminder?.dueDate == due)
        #expect(details.dueHasTime == false)
        #expect(details.reminder?.recurrence == RecurrenceRule(frequency: .monthly))
    }

    @Test("a local-only destination replies done with the warning")
    func aLocalOnlyDestinationRepliesDoneWithTheWarning() async throws {
        let repository = Self.repository()
        let handler = Self.handler(repository, calendar: Self.phoneOnly)
        let start = Self.date(2026, 11, 25, 13)

        let reply = await handler.handle(Self.envelope(.add(Self.eventDraft(start: start, end: nil))))

        #expect(reply == .done(notice: "Added to Calendar · On My iPhone",
                               warning: DestinationLabel.localOnlyWarning))
        #expect(await repository.itemCount == 1)
    }

    @Test("no default destination replies failed")
    func noDefaultDestinationRepliesFailed() async throws {
        let repository = Self.repository()
        let handler = Self.handler(repository, calendar: nil, list: nil)
        let start = Self.date(2026, 11, 25, 13)

        let event = await handler.handle(Self.envelope(.add(Self.eventDraft(start: start, end: nil))))
        let reminder = await handler.handle(Self.envelope(.add(WatchAddDraft(
            kind: .reminder, title: "Milk", start: nil, end: nil, isAllDay: false, recurrence: nil, summary: ""))))

        #expect(event == .failed(ItemRouterError.noDefaultDestination(.event).message))
        #expect(reminder == .failed(ItemRouterError.noDefaultDestination(.reminder).message))
        #expect(await repository.itemCount == 0)
    }

    @Test("a repository error replies failed with its message")
    func aRepositoryErrorRepliesFailedWithItsMessage() async throws {
        let repository = Self.repository()
        await repository.failNext("disk full")
        let handler = Self.handler(repository)

        let reply = await handler.handle(Self.envelope(.add(Self.eventDraft(start: Self.date(2026, 11, 25, 13),
                                                                            end: nil))))
        let missing = await handler.handle(Self.envelope(.complete(identifier: "gone", externalID: nil,
                                                                    occurrence: Self.date(2026, 11, 24))))

        #expect(reply == .failed("Couldn't save to Apple Calendar or Reminders: disk full"))
        #expect(missing == .failed(ItemRouterError.apple(.notFound).message))
        #expect(await repository.itemCount == 0)
    }

    @Test("the same envelope twice is applied once and replies the same")
    func theSameEnvelopeTwiceIsAppliedOnceAndRepliesTheSame() async throws {
        let repository = Self.repository()
        let applied = InMemoryAppliedIDStore()
        let handler = Self.handler(repository, applied: applied)
        let envelope = Self.envelope(.add(Self.eventDraft(start: Self.date(2026, 11, 25, 13), end: nil)))

        let first = await handler.handle(envelope)
        let second = await handler.handle(envelope)
        // Both at once (a live message and its queued fallback racing).
        let other = Self.envelope(.add(Self.eventDraft(start: Self.date(2026, 11, 26, 13), end: nil)))
        async let a = handler.handle(other)
        async let b = handler.handle(other)
        let (ra, rb) = await (a, b)

        #expect(first == .done(notice: "Added to Home · iCloud", warning: nil))
        #expect(second == first)
        #expect(ra == rb)
        #expect(await repository.itemCount == 2)
        #expect(applied.contains(envelope.id))

        // After a relaunch (a new handler over the same store) it is still not applied again.
        let relaunched = Self.handler(repository, applied: applied)
        #expect(await relaunched.handle(envelope) == .done(notice: nil, warning: nil))
        #expect(await repository.itemCount == 2)
    }

    @Test("a failed envelope is not remembered, so a redelivery tries again")
    func aFailedEnvelopeIsNotRemembered() async throws {
        let repository = Self.repository()
        await repository.failNext("busy")
        let applied = InMemoryAppliedIDStore()
        let handler = Self.handler(repository, applied: applied)
        let envelope = Self.envelope(.add(Self.eventDraft(start: Self.date(2026, 11, 25, 13), end: nil)))

        #expect(await handler.handle(envelope) == .failed("Couldn't save to Apple Calendar or Reminders: busy"))
        #expect(!applied.contains(envelope.id))
        #expect(await handler.handle(envelope) == .done(notice: "Added to Home · iCloud", warning: nil))
        #expect(await repository.itemCount == 1)
    }

    @Test("applied ids are bounded at 200: the oldest is forgotten after 200 more")
    func appliedIDsAreBoundedAt200() throws {
        let suite = "WatchCommandHandlerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppliedIDStore(defaults: defaults)
        let oldest = UUID()
        store.insert(oldest)
        let later = (0..<199).map { _ in UUID() }
        for id in later { store.insert(id) }
        #expect(store.contains(oldest))

        let newest = UUID()
        store.insert(newest)

        #expect(!store.contains(oldest))
        #expect(store.contains(newest))
        #expect(later.allSatisfy(store.contains))
        // A second store over the same defaults (a relaunch) sees the same ids.
        #expect(UserDefaultsAppliedIDStore(defaults: defaults).contains(newest))
    }
}
