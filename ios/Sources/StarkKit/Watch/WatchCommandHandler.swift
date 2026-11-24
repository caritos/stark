import Foundation

/// Remembers which envelopes the phone has already applied, across launches.
public protocol AppliedIDStore: Sendable {
    func contains(_ id: UUID) -> Bool
    func insert(_ id: UUID)
}

/// The applied ids in UserDefaults, newest last, keeping at most `limit` (the oldest is forgotten).
/// Not atomic across callers on its own: `WatchCommandHandler` (an actor) is its only writer.
public struct UserDefaultsAppliedIDStore: AppliedIDStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    public init(defaults: UserDefaults = .standard, key: String = "watch.appliedIDs.v1", limit: Int = 200) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
    }

    public func contains(_ id: UUID) -> Bool { stored().contains(id.uuidString) }

    public func insert(_ id: UUID) {
        var ids = stored().filter { $0 != id.uuidString }
        ids.append(id.uuidString)
        if ids.count > limit { ids.removeFirst(ids.count - limit) }
        defaults.set(ids, forKey: key)
    }

    private func stored() -> [String] { defaults.stringArray(forKey: key) ?? [] }
}

/// The iPhone side of the watch link: applies a watch command through `ItemRepository` (the watch
/// cannot write to EventKit) and says how it went.
///
/// - An add goes to the phone's own default calendar (events) or list (reminders), from
///   `destinations`; none means `failed` with the Add screen's message.
/// - A successful envelope's id is remembered, so a redelivery (a live message whose reply was
///   lost, then its queued copy) is acknowledged and not applied again. In this launch it gets the
///   same reply; after a relaunch a plain `done` (the reply text is not stored). A failed envelope is
///   not remembered: nothing was written, so a redelivery tries again.
public actor WatchCommandHandler {
    private let repository: ItemRepository
    private let destinations: @Sendable () async -> (calendar: AppleCalendarInfo?, list: AppleCalendarInfo?)
    private let applied: AppliedIDStore
    /// Replies of envelopes applied in this launch, so a redelivery answers the same.
    private var replies: [UUID: WatchReply] = [:]
    /// Envelopes being applied: the same id arriving meanwhile waits for that work (actor
    /// reentrancy would otherwise let both pass the "already applied" check).
    private var inFlight: [UUID: Task<WatchReply, Never>] = [:]

    public init(repository: ItemRepository,
                destinations: @escaping @Sendable () async -> (calendar: AppleCalendarInfo?, list: AppleCalendarInfo?),
                applied: AppliedIDStore) {
        self.repository = repository
        self.destinations = destinations
        self.applied = applied
    }

    public func handle(_ envelope: WatchEnvelope) async -> WatchReply {
        if let reply = replies[envelope.id] { return reply }
        if let running = inFlight[envelope.id] { return await running.value }
        if applied.contains(envelope.id) { return .done(notice: nil, warning: nil) }
        let task = Task { await self.apply(envelope.command) }
        inFlight[envelope.id] = task
        let reply = await task.value
        inFlight[envelope.id] = nil
        if case .done = reply {
            applied.insert(envelope.id)
            replies[envelope.id] = reply
            if replies.count > 200 { replies.removeAll() }
        }
        return reply
    }

    private func apply(_ command: WatchCommand) async -> WatchReply {
        do {
            switch command {
            case let .complete(identifier, externalID, occurrence):
                let ref = AppleItemRef(kind: .reminder, identifier: identifier, externalID: externalID)
                try await repository.complete(ref, on: occurrence)
                return .done(notice: nil, warning: nil)
            case .add(let draft):
                return try await add(draft)
            }
        } catch {
            return .failed(Self.message(for: error))
        }
    }

    private func add(_ draft: WatchAddDraft) async throws -> WatchReply {
        let targets = await destinations()
        switch draft.kind {
        case .event:
            guard let calendar = targets.calendar else {
                throw ItemRouterError.noDefaultDestination(.event)
            }
            guard let event = Self.normalized(draft.newEvent()) else {
                throw ItemRouterError.unsupported("This event has no start date.")
            }
            _ = try await repository.addEvent(event, calendarID: calendar.id)
            return .done(notice: DestinationLabel.addedNotice(calendar: calendar),
                         warning: DestinationLabel.warning(for: calendar))
        case .reminder:
            guard let list = targets.list else {
                throw ItemRouterError.noDefaultDestination(.reminder)
            }
            guard var reminder = draft.newReminder() else {
                throw ItemRouterError.unsupported("This reminder can't be added.")
            }
            if let due = reminder.due, !reminder.dueHasTime {
                reminder.due = FormFields.normalizedStart(due, allDay: true)
            }
            _ = try await repository.addReminder(reminder, listID: list.id)
            return .done(notice: DestinationLabel.addedNotice(calendar: list),
                         warning: DestinationLabel.warning(for: list))
        }
    }

    /// Stores the event as the Add screen does: an all-day start at the start of its day and an
    /// end only when it is after the start (an all-day end only when it is a later day; the draft's
    /// start + 1 h of a one-day all-day event becomes no end).
    static func normalized(_ event: NewEvent?) -> NewEvent? {
        guard var event else { return nil }
        let start = FormFields.normalizedStart(event.start, allDay: event.isAllDay)
        event.end = event.end.flatMap { EventSchedule.storedEnd($0, start: start, allDay: event.isAllDay) }
        event.start = start
        return event
    }

    /// The sentence the watch shows, the same one the phone's own error banner would.
    static func message(for error: Error) -> String {
        switch error {
        case let e as ItemRouterError: return e.message
        case let e as ItemRepositoryError: return ItemRouterError.apple(e).message
        default: return error.localizedDescription
        }
    }
}
