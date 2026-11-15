// ios/Sources/StarkKit/Items/ItemRouter.swift
import Foundation

/// Who owns an item: Apple (Calendar / Reminders, through `ItemRepository`) or Stark's local store.
public enum ItemOrigin: Equatable, Sendable {
    case apple(AppleItemRef)
    case local

    /// Model ids of Apple items (`Event.id` / `Reminder.id` of an overlay row, a plan block's
    /// `reminderID`) are `apple-<EventKit identifier>` (`mergeAppleItems`).
    public static let applePrefix = "apple-"

    /// From a MODEL id (what the views pass today: `event.id`, `reminder.id`, `block.reminderID`),
    /// not an agenda ROW id (which adds `-<occurrence>`; use `init(item:)` for rows). The id cannot
    /// say event or reminder, so the caller passes the kind. Anything else (Stark's UUIDs) is local.
    public init(id: String, kind: AppleItemRef.Kind) {
        guard id.hasPrefix(Self.applePrefix), id.count > Self.applePrefix.count else {
            self = .local
            return
        }
        self = .apple(AppleItemRef(kind: kind, identifier: String(id.dropFirst(Self.applePrefix.count))))
    }

    /// From an agenda row (`AppleItemRef.ref(for:)`).
    public init(item: AgendaItem) {
        self = AppleItemRef.ref(for: item).map(ItemOrigin.apple) ?? .local
    }

    /// The model id an Apple item carries in Stark (`apple-<identifier>`).
    public static func modelID(for ref: AppleItemRef) -> String { applePrefix + ref.identifier }
}

/// A failed router operation, with a sentence the views show in the existing error banner.
public enum ItemRouterError: Error, Equatable, Sendable {
    /// No default calendar (for events) or list (for reminders) to create the item in.
    case noDefaultDestination(AppleItemRef.Kind)
    /// The operation does not exist for Apple items (e.g. skipping one reminder occurrence).
    case unsupported(String)
    /// EventKit refused the write; nothing changed.
    case apple(ItemRepositoryError)
    /// Stark's sidecar file (plans, outcomes) could not be read or written; nothing changed.
    case sidecar(String)
    /// The local store refused (e.g. a month file it cannot read); nothing changed.
    case local(String)
    /// A convert created the new item but could not finish (remap or delete of the original);
    /// both items are kept so nothing is lost.
    case convertedButOriginalKept(String)

    public var message: String {
        switch self {
        case .noDefaultDestination(.event):
            return "Choose a default calendar in Settings before adding events."
        case .noDefaultDestination(.reminder):
            return "Choose a default Reminders list in Settings before adding reminders."
        case .unsupported(let text):
            return text
        case .apple(.notFound):
            return "This item is no longer in Apple Calendar or Reminders."
        case .apple(.notWritable):
            return "This calendar or list can't be changed."
        case .apple(.unrepresentable(let text)):
            return text
        case .apple(.saveFailed(let text)):
            return "Couldn't save to Apple Calendar or Reminders: \(text)"
        case .sidecar(let text):
            return "Couldn't save Stark's plans and marks: \(text)"
        case .local(let text):
            return text
        case .convertedButOriginalKept(let reason):
            return "The new item was created, but the original couldn't be removed (\(reason)). Both are kept; delete the old one by hand."
        }
    }
}

/// The write facade the views call. Apple items (`apple-` ids) go to `ItemRepository` and, for
/// Stark-only data (plan blocks, event outcomes), to `ItemSidecar`; Stark's own items (UUID ids)
/// go to the local store unchanged. New items always go to Apple's default calendar or list.
///
/// Apple failures throw `ItemRouterError` and change nothing (the repository is all-or-nothing per
/// call). Local operations keep `PlannerStore`'s behaviour: the silent ones stay silent (the store
/// sets its own `error`), the ones that return false throw `.local`.
///
/// `onDidWrite` runs after every successful Apple or sidecar write (never after a failure or a
/// local-only write), because `EKEventStoreChanged` is not reliable after a save (spike f): the
/// owner reloads the overlay there.
@MainActor
public final class ItemRouter {
    private let repository: any ItemRepository
    private let local: any LocalItemStore
    private let sidecar: ItemSidecar
    private let destinations: any DefaultDestinations
    private let calendar: Calendar
    private let now: () -> Date

    public var onDidWrite: (() async -> Void)?

    /// `calendar` decides which day a plan block belongs to when a day's Apple blocks are replaced.
    public init(repository: any ItemRepository, local: any LocalItemStore, sidecar: ItemSidecar,
                destinations: any DefaultDestinations, calendar: Calendar = Calendar(identifier: .gregorian),
                now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.local = local
        self.sidecar = sidecar
        self.destinations = destinations
        self.calendar = calendar
        self.now = now
    }

    // MARK: Read

    /// The real stored item for the edit sheet, with its ids rewritten to Stark's model id
    /// (`apple-<identifier>`) so the edited copy routes back here. Start an edit from this, never
    /// from the overlay's stand-in values (no recurrence, no write permission).
    public func details(id: String, kind: AppleItemRef.Kind) async throws -> ItemDetails {
        guard case .apple(let ref) = ItemOrigin(id: id, kind: kind) else {
            throw ItemRouterError.unsupported("Only Apple items have stored details.")
        }
        var details = try await apple { try await repository.details(ref) }
        details.event?.id = ItemOrigin.modelID(for: ref)
        details.reminder?.id = ItemOrigin.modelID(for: ref)
        return details
    }

    // MARK: Add (always Apple)

    /// `calendarID` overrides the default calendar (the add sheet's picker); nil uses the default.
    @discardableResult
    public func add(event: Event, calendarID: String? = nil) async throws -> AppleItemRef {
        guard let calendarID = calendarID ?? destinations.calendarID else {
            throw ItemRouterError.noDefaultDestination(.event)
        }
        let ref = try await apple { try await repository.addEvent(Self.newEvent(event), calendarID: calendarID) }
        await didWrite()
        return ref
    }

    /// `listID` overrides the default list; nil uses the default. Date-only vs timed follows
    /// `FormFields.dueHasTime` (local midnight = date-only), the same rule `update` uses.
    @discardableResult
    public func add(reminder: Reminder, listID: String? = nil, url: String? = nil) async throws -> AppleItemRef {
        guard let listID = listID ?? destinations.listID else { throw ItemRouterError.noDefaultDestination(.reminder) }
        let new = Self.newReminder(reminder, url: url)
        let ref = try await apple { try await repository.addReminder(new, listID: listID) }
        await didWrite()
        return ref
    }

    // MARK: Update

    /// Local: the whole edited value, as before (`original` is not needed). Apple: `original` is the
    /// stored item from `details(id:kind:)` and is required; only the fields that differ from it are
    /// written, and nothing changed means no write and no `onDidWrite`. Refused when the item can't
    /// be written, and a repeat change is refused when the stored repeat can't be represented.
    public func update(event: Event, original: ItemDetails? = nil) async throws {
        switch ItemOrigin(id: event.id, kind: .event) {
        case .local:
            local.updateEvent(event)
        case .apple(let ref):
            let original = try Self.requireDetails(original)
            let patch = EventPatch(from: original, to: event)
            guard patch != EventPatch() else { return }
            try Self.checkWritable(original, changesRepeat: patch.recurrence != .keep)
            try await appleWrite { try await repository.update(ref, event: patch) }
        }
    }

    /// As `update(event:original:)`. `url` is the edited URL (`Reminder` has none), diffed against
    /// `original.reminderURL`; the local store ignores it.
    public func update(reminder: Reminder, url: String?, original: ItemDetails? = nil) async throws {
        switch ItemOrigin(id: reminder.id, kind: .reminder) {
        case .local:
            local.updateReminder(reminder)
        case .apple(let ref):
            let original = try Self.requireDetails(original)
            let patch = ReminderPatch(from: original, to: reminder, url: url)
            guard patch != ReminderPatch() else { return }
            try Self.checkWritable(original, changesRepeat: patch.recurrence != .keep)
            try await appleWrite { try await repository.update(ref, reminder: patch) }
        }
    }

    private static func requireDetails(_ details: ItemDetails?) throws -> ItemDetails {
        guard let details else {
            throw ItemRouterError.unsupported("This item couldn't be loaded for editing. Close it and try again.")
        }
        return details
    }

    private static func checkWritable(_ details: ItemDetails, changesRepeat: Bool) throws {
        guard details.isWritable else { throw ItemRouterError.apple(.notWritable) }
        if changesRepeat && details.hasUnrepresentableRepeat {
            throw ItemRouterError.unsupported(
                "This item repeats in a way Stark can't edit. Change its repeat in Apple Calendar or Reminders.")
        }
    }

    // MARK: Delete

    /// Apple: the whole item (a whole series). Sidecar records are kept (orphans are never dropped
    /// automatically).
    public func deleteEvent(id: String) async throws {
        switch ItemOrigin(id: id, kind: .event) {
        case .local: local.deleteEvent(id: id)
        case .apple(let ref): try await appleWrite { try await repository.delete(ref) }
        }
    }

    public func deleteReminder(id: String) async throws {
        switch ItemOrigin(id: id, kind: .reminder) {
        case .local: local.deleteReminder(id: id)
        case .apple(let ref): try await appleWrite { try await repository.delete(ref) }
        }
    }

    // MARK: Complete / skip / outcome

    /// `today` nil means now. Apple: a recurring reminder moves to its next date (Apple's rule).
    public func complete(id: String, on date: Date, today: Date? = nil) async throws {
        switch ItemOrigin(id: id, kind: .reminder) {
        case .local: local.completeReminder(id: id, on: date, today: today ?? now(), now: now())
        case .apple(let ref): try await appleWrite { try await repository.complete(ref, on: date) }
        }
    }

    public func uncomplete(id: String) async throws {
        switch ItemOrigin(id: id, kind: .reminder) {
        case .local: local.uncompleteReminder(id: id)
        case .apple(let ref): try await appleWrite { try await repository.uncomplete(ref) }
        }
    }

    /// Apple: deletes only the occurrence on `date`'s day (a one-off event is deleted).
    public func skipEvent(id: String, on date: Date) async throws {
        switch ItemOrigin(id: id, kind: .event) {
        case .local: local.skipEvent(id: id, on: date)
        case .apple(let ref): try await appleWrite { try await repository.deleteOccurrence(ref, on: date) }
        }
    }

    /// Local only. Apple Reminders has no "skip this occurrence": throws `.unsupported`.
    public func skipReminder(id: String, on date: Date, today: Date? = nil) async throws {
        switch ItemOrigin(id: id, kind: .reminder) {
        case .local:
            local.skipReminder(id: id, on: date, today: today ?? now())
        case .apple:
            throw ItemRouterError.unsupported(
                "Apple Reminders can't skip one occurrence. Mark it done, or change its due date.")
        }
    }

    /// Apple: kept in the sidecar, dated by the occurrence (`date`); nil clears that day's mark.
    /// The item's external id is read through the repository; use `setEventOutcome(ref:on:outcome:)`
    /// when the caller already holds a ref carrying it.
    public func setEventOutcome(id: String, on date: Date, outcome: EventOutcome?) async throws {
        switch ItemOrigin(id: id, kind: .event) {
        case .local:
            local.setEventOutcome(id: id, on: date, outcome: outcome, now: now())
        case .apple(let ref):
            try await setEventOutcome(ref: await withExternalID(ref), on: date, outcome: outcome)
        }
    }

    /// Apple only: the outcome for `ref`, stored with `ref.externalID` as given.
    public func setEventOutcome(ref: AppleItemRef, on date: Date, outcome: EventOutcome?) async throws {
        let stamp = now()
        try await sidecarWrite {
            if let outcome {
                try await sidecar.setOutcome(EventOutcomeRecord(date: date, outcome: outcome, recordedAt: stamp),
                                             for: ref.identifier, externalID: ref.externalID)
            } else {
                try await sidecar.clearOutcome(for: ref.identifier, externalID: ref.externalID, on: date)
            }
        }
        await didWrite()
    }

    /// `ref` with its external id: as given, else read once from the repository (nothing cached).
    /// An item the repository can't read keeps nil; sidecar records never need the item to exist.
    private func withExternalID(_ ref: AppleItemRef) async -> AppleItemRef {
        guard ref.externalID == nil else { return ref }
        guard let external = try? await repository.details(ref).externalID else { return ref }
        return AppleItemRef(kind: ref.kind, identifier: ref.identifier, externalID: external)
    }

    // MARK: Convert

    /// Local: `PlannerStore.convertEvent` (returns nil). Apple: creates the reminder in the default
    /// list, moves the sidecar records to it, then deletes the event; returns the new ref. A failed
    /// create changes nothing; a failure after it keeps both (`.convertedButOriginalKept`).
    @discardableResult
    public func convertEvent(id: String, to reminder: Reminder, url: String? = nil) async throws -> AppleItemRef? {
        switch ItemOrigin(id: id, kind: .event) {
        case .local:
            guard local.convertEvent(id: id, to: reminder) else {
                throw ItemRouterError.local("Couldn't convert the event: it was not found or its month can't be read.")
            }
            return nil
        case .apple(let ref):
            guard let listID = destinations.listID else { throw ItemRouterError.noDefaultDestination(.reminder) }
            let new = Self.newReminder(reminder, url: url)
            return try await replace(ref) { try await self.repository.addReminder(new, listID: listID) }
        }
    }

    /// Reminder -> event counterpart of `convertEvent`, created in the default calendar.
    @discardableResult
    public func convertReminder(id: String, to event: Event) async throws -> AppleItemRef? {
        switch ItemOrigin(id: id, kind: .reminder) {
        case .local:
            guard local.convertReminder(id: id, to: event) else {
                throw ItemRouterError.local("Couldn't convert the reminder: it was not found, is completed, or its month can't be read.")
            }
            return nil
        case .apple(let ref):
            guard let calendarID = destinations.calendarID else { throw ItemRouterError.noDefaultDestination(.event) }
            let new = Self.newEvent(event)
            return try await replace(ref) { try await self.repository.addEvent(new, calendarID: calendarID) }
        }
    }

    private func replace(_ old: AppleItemRef, create: () async throws -> AppleItemRef) async throws -> AppleItemRef {
        let newRef = await withExternalID(try await apple(create))
        do {
            try await sidecar.remap(oldID: old.identifier, newID: newRef.identifier)
            if let external = newRef.externalID {
                try await sidecar.update { $0.externalIDs[newRef.identifier] = external }
            }
        } catch {
            await didWrite()
            throw ItemRouterError.convertedButOriginalKept("its plans couldn't be moved: \(Self.describe(error))")
        }
        do {
            try await repository.delete(old)
        } catch {
            await didWrite()
            throw ItemRouterError.convertedButOriginalKept(Self.describe(error))
        }
        await didWrite()
        return newRef
    }

    // MARK: Plans

    /// The day's blocks from both stores. Apple blocks come back with `apple-` reminder ids.
    public func plans(on day: Date) async throws -> [PlanBlock] {
        let applePlans = try await sidecarRead { try await sidecar.plans(on: day) }
        return local.plans(on: day) + applePlans.map { block in
            var copy = block
            copy.reminderID = ItemOrigin.applePrefix + block.reminderID
            return copy
        }
    }

    /// Replaces the day's blocks: blocks for Apple reminders go to the sidecar (stored under the bare
    /// identifier), the rest to the local store. Blocks not on `day` are ignored, as in the store.
    /// The sidecar is written first; if the local store then refuses, the Apple half is saved and
    /// `.local` is thrown (retrying rewrites the same blocks, since this is a replace). Each planned
    /// Apple reminder's external id is read through the repository and recorded with the blocks.
    public func replacePlans(on day: Date, with blocks: [PlanBlock]) async throws {
        var appleBlocks: [PlanBlock] = []
        var appleRefs: [String: AppleItemRef] = [:]
        var localBlocks: [PlanBlock] = []
        for block in blocks {
            if case .apple(let ref) = ItemOrigin(id: block.reminderID, kind: .reminder) {
                guard calendar.isDate(block.start, inSameDayAs: day) else { continue }
                var copy = block
                copy.reminderID = ref.identifier
                appleBlocks.append(copy)
                appleRefs[ref.identifier] = ref
            } else {
                localBlocks.append(block)
            }
        }
        let storedApple = try await sidecarRead { try await sidecar.plans(on: day) }
        if !(appleBlocks.isEmpty && storedApple.isEmpty) && appleBlocks != storedApple {
            var externalIDs: [String: String] = [:]
            for ref in appleRefs.values {
                if let external = await withExternalID(ref).externalID { externalIDs[ref.identifier] = external }
            }
            try await sidecarWrite {
                try await sidecar.replacePlans(on: day, with: appleBlocks, externalIDs: externalIDs)
            }
            await didWrite()
        }
        guard local.replacePlans(on: day, with: localBlocks) else {
            throw ItemRouterError.local("Couldn't save the plan: that month's file can't be read.")
        }
    }

    // MARK: Helpers

    private func didWrite() async {
        await onDidWrite?()
    }

    private func appleWrite(_ body: () async throws -> Void) async throws {
        try await apple(body)
        await didWrite()
    }

    private func apple<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as ItemRepositoryError {
            throw ItemRouterError.apple(error)
        } catch let error as ItemRouterError {
            throw error
        } catch {
            throw ItemRouterError.apple(.saveFailed(error.localizedDescription))
        }
    }

    private func sidecarWrite(_ body: () async throws -> Void) async throws {
        do { try await body() } catch { throw ItemRouterError.sidecar(Self.describe(error)) }
    }

    private func sidecarRead<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw ItemRouterError.sidecar(Self.describe(error)) }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case let e as ItemRouterError: return e.message
        case let e as ItemRepositoryError: return ItemRouterError.apple(e).message
        case ItemSidecarError.unsupportedVersion(let v): return "the file was written by a newer Stark (version \(v))"
        case ItemSidecarError.unreadable(let text): return "the file can't be read (\(text))"
        default: return error.localizedDescription
        }
    }

    static func newEvent(_ event: Event) -> NewEvent {
        NewEvent(title: event.title, notes: event.notes, start: event.start, end: event.end, isAllDay: event.isAllDay,
                 location: event.location, url: event.url, recurrence: event.recurrence)
    }

    static func newReminder(_ reminder: Reminder, url: String?) -> NewReminder {
        NewReminder(title: reminder.title, notes: reminder.notes, due: reminder.dueDate,
                    dueHasTime: FormFields.dueHasTime(reminder), priority: reminder.priority,
                    recurrence: reminder.recurrence, url: url)
    }
}
