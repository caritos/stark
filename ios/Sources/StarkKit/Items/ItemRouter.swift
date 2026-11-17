// ios/Sources/StarkKit/Items/ItemRouter.swift
import Foundation

/// Where an item lives. Stark keeps no items of its own (phase 3): the only origin is Apple
/// Calendar / Reminders, through `ItemRepository`. The initialisers return nil for any id that is
/// not an Apple model id; the router refuses those (`ItemRouterError.notApple`).
public enum ItemOrigin: Equatable, Sendable {
    case apple(AppleItemRef)

    /// Model ids of Apple items (`Event.id` / `Reminder.id` of an overlay row, a plan block's
    /// `reminderID`) are `apple-<EventKit identifier>` (`mergeAppleItems`).
    public static let applePrefix = "apple-"

    /// From a MODEL id (what the views pass today: `event.id`, `reminder.id`, `block.reminderID`),
    /// not an agenda ROW id (which adds `-<occurrence>`; use `init(item:)` for rows). The id cannot
    /// say event or reminder, so the caller passes the kind. Anything else is nil.
    public init?(id: String, kind: AppleItemRef.Kind) {
        guard id.hasPrefix(Self.applePrefix), id.count > Self.applePrefix.count else { return nil }
        self = .apple(AppleItemRef(kind: kind, identifier: String(id.dropFirst(Self.applePrefix.count))))
    }

    /// From an agenda row (`AppleItemRef.ref(for:)`); nil for a row without an Apple source.
    public init?(item: AgendaItem) {
        guard let ref = AppleItemRef.ref(for: item) else { return nil }
        self = .apple(ref)
    }

    /// The model id an Apple item carries in Stark (`apple-<identifier>`).
    public static func modelID(for ref: AppleItemRef) -> String { applePrefix + ref.identifier }
}

/// A failed router operation, with a sentence the views show in the existing error banner.
public enum ItemRouterError: Error, Equatable, Sendable {
    /// No default calendar (for events) or list (for reminders) to create the item in.
    case noDefaultDestination(AppleItemRef.Kind)
    /// The id is not an Apple item's (`apple-<identifier>`). Stark keeps no items of its own any
    /// more, so there is nothing to write to; nothing changed.
    case notApple
    /// The operation can't be done on this Apple item (e.g. an edit without its stored details,
    /// or a repeat Stark can't represent).
    case unsupported(String)
    /// EventKit refused the write; nothing changed.
    case apple(ItemRepositoryError)
    /// Stark's sidecar file (plans, outcomes) could not be read or written; nothing changed.
    case sidecar(String)
    /// A convert created the new item but could not finish (remap or delete of the original);
    /// both items are kept so nothing is lost.
    case convertedButOriginalKept(String)

    public var message: String {
        switch self {
        case .noDefaultDestination(.event):
            return "Choose a default calendar in Settings before adding events."
        case .noDefaultDestination(.reminder):
            return "Choose a default Reminders list in Settings before adding reminders."
        case .notApple:
            return "This item isn't in Apple Calendar or Reminders, so Stark can't change it."
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
        case .apple(.ruleChangeLosesEditedOccurrences):
            return "Some occurrences of this series were changed one by one in Calendar. Changing the repeat rule removes those changes."
        case .sidecar(let text):
            return "Couldn't save Stark's plans and marks: \(text)"
        case .convertedButOriginalKept(let reason):
            return "The new item was created, but the original couldn't be removed (\(reason)). Both are kept; delete the old one by hand."
        }
    }

    /// The refusal the edit sheet turns into a confirmation (`ruleChangeConfirmation`) and, only
    /// when the owner confirms, resends with `confirmRuleChange: true`.
    public var asksToConfirmRuleChange: Bool { self == .apple(.ruleChangeLosesEditedOccurrences) }

    /// The question asked before a repeat-rule change that would lose occurrences edited in Calendar.
    public static let ruleChangeConfirmation =
        "Changing the repeat rule will reset occurrences you edited one by one in Calendar. Change anyway?"
}

/// The write facade the views call. Apple items (`apple-` ids) go to `ItemRepository` and, for
/// Stark-only data (plan blocks, event outcomes), to `ItemSidecar`. Any other id is refused with
/// `.notApple` before anything is read or written: Stark keeps no items of its own. New items
/// always go to Apple's default calendar or list.
///
/// Failures throw `ItemRouterError` and change nothing (the repository is all-or-nothing per
/// call).
///
/// `onDidWrite` runs after every successful Apple or sidecar write (never after a failure or a
/// no-op), because `EKEventStoreChanged` is not reliable after a save (spike f): the owner reloads
/// the overlay there.
@MainActor
public final class ItemRouter {
    private let repository: any ItemRepository
    private let sidecar: ItemSidecar
    private let destinations: any DefaultDestinations
    private let calendar: Calendar
    private let now: () -> Date

    public var onDidWrite: (() async -> Void)?

    /// `calendar` decides which day a plan block belongs to when a day's blocks are replaced.
    public init(repository: any ItemRepository, sidecar: ItemSidecar,
                destinations: any DefaultDestinations, calendar: Calendar = Calendar(identifier: .gregorian),
                now: @escaping () -> Date = Date.init) {
        self.repository = repository
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
        let ref = try Self.appleRef(id, kind)
        var details = try await apple { try await repository.details(ref) }
        details.event?.id = ItemOrigin.modelID(for: ref)
        details.reminder?.id = ItemOrigin.modelID(for: ref)
        return details
    }

    // MARK: Add

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

    /// `original` is the stored item from `details(id:kind:)` and is required; only the fields that
    /// differ from it are written, and nothing changed means no write and no `onDidWrite`. Refused
    /// when the item can't be written, and a repeat change is refused when the stored repeat can't
    /// be represented.
    ///
    /// `confirmRuleChange`: the owner confirmed that a repeat change may lose occurrences edited one
    /// by one in Calendar; without it such a change throws `.apple(.ruleChangeLosesEditedOccurrences)`
    /// (`asksToConfirmRuleChange`), and the edit sheet asks before resending.
    public func update(event: Event, original: ItemDetails? = nil, confirmRuleChange: Bool = false) async throws {
        let ref = try Self.appleRef(event.id, .event)
        let original = try Self.requireDetails(original)
        var patch = EventPatch(from: original, to: event)
        guard patch != EventPatch() else { return }
        try Self.checkWritable(original, changesRepeat: patch.recurrence != .keep)
        patch.confirmRuleChange = confirmRuleChange
        try await appleWrite { try await repository.update(ref, event: patch) }
    }

    /// As `update(event:original:)`. `url` is the edited URL (`Reminder` has none), diffed against
    /// `original.reminderURL`.
    public func update(reminder: Reminder, url: String?, original: ItemDetails? = nil) async throws {
        let ref = try Self.appleRef(reminder.id, .reminder)
        let original = try Self.requireDetails(original)
        let patch = ReminderPatch(from: original, to: reminder, url: url)
        guard patch != ReminderPatch() else { return }
        try Self.checkWritable(original, changesRepeat: patch.recurrence != .keep)
        try await appleWrite { try await repository.update(ref, reminder: patch) }
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

    /// The whole item (a whole series). Sidecar records are kept (orphans are never dropped
    /// automatically).
    public func deleteEvent(id: String) async throws {
        let ref = try Self.appleRef(id, .event)
        try await appleWrite { try await repository.delete(ref) }
    }

    public func deleteReminder(id: String) async throws {
        let ref = try Self.appleRef(id, .reminder)
        try await appleWrite { try await repository.delete(ref) }
    }

    // MARK: Complete / skip / outcome

    /// A recurring reminder moves to its next date (Apple's rule). There is no reminder skip:
    /// Apple Reminders can't skip one occurrence.
    public func complete(id: String, on date: Date) async throws {
        let ref = try Self.appleRef(id, .reminder)
        try await appleWrite { try await repository.complete(ref, on: date) }
    }

    public func uncomplete(id: String) async throws {
        let ref = try Self.appleRef(id, .reminder)
        try await appleWrite { try await repository.uncomplete(ref) }
    }

    /// Deletes only the occurrence on `date`'s day (a one-off event is deleted).
    public func skipEvent(id: String, on date: Date) async throws {
        let ref = try Self.appleRef(id, .event)
        try await appleWrite { try await repository.deleteOccurrence(ref, on: date) }
    }

    /// Kept in the sidecar, dated by the occurrence (`date`); nil clears that day's mark. The
    /// item's external id is read through the repository; use `setEventOutcome(ref:on:outcome:)`
    /// when the caller already holds a ref carrying it.
    public func setEventOutcome(id: String, on date: Date, outcome: EventOutcome?) async throws {
        let ref = try Self.appleRef(id, .event)
        try await setEventOutcome(ref: await withExternalID(ref), on: date, outcome: outcome)
    }

    /// The outcome for `ref`, stored with `ref.externalID` as given.
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

    /// An Apple event's attended/skipped mark on `date`'s day, from the sidecar; nil when none is
    /// recorded and for an id that is not an Apple event's (a read, so nothing to refuse).
    public func eventOutcome(id: String, on date: Date) async throws -> EventOutcome? {
        guard case .apple(let ref) = ItemOrigin(id: id, kind: .event) else { return nil }
        return try await sidecarRead { try await sidecar.outcome(for: ref.identifier, externalID: nil, on: date) }?.outcome
    }

    /// `ref` with its external id: as given, else read once from the repository (nothing cached).
    /// An item the repository can't read keeps nil; sidecar records never need the item to exist.
    private func withExternalID(_ ref: AppleItemRef) async -> AppleItemRef {
        guard ref.externalID == nil else { return ref }
        guard let external = try? await repository.details(ref).externalID else { return ref }
        return AppleItemRef(kind: ref.kind, identifier: ref.identifier, externalID: external)
    }

    // MARK: Convert

    /// Creates the reminder in the default list, moves the sidecar records to it, then deletes the
    /// event; returns the new ref. A failed create changes nothing; a failure after it keeps both
    /// (`.convertedButOriginalKept`).
    @discardableResult
    public func convertEvent(id: String, to reminder: Reminder, url: String? = nil) async throws -> AppleItemRef {
        let ref = try Self.appleRef(id, .event)
        guard let listID = destinations.listID else { throw ItemRouterError.noDefaultDestination(.reminder) }
        try await refuseUnrepresentableConvert(ref)
        let new = Self.newReminder(reminder, url: url)
        return try await replace(ref) { try await self.repository.addReminder(new, listID: listID) }
    }

    /// Reminder -> event counterpart of `convertEvent`, created in the default calendar.
    @discardableResult
    public func convertReminder(id: String, to event: Event) async throws -> AppleItemRef {
        let ref = try Self.appleRef(id, .reminder)
        guard let calendarID = destinations.calendarID else { throw ItemRouterError.noDefaultDestination(.event) }
        try await refuseUnrepresentableConvert(ref)
        let new = Self.newEvent(event)
        return try await replace(ref) { try await self.repository.addEvent(new, calendarID: calendarID) }
    }

    /// A convert deletes the original; one whose repeat Stark can't represent would come back
    /// without it, so it is refused before anything is written.
    private func refuseUnrepresentableConvert(_ ref: AppleItemRef) async throws {
        let source = try await apple { try await repository.details(ref) }
        guard !source.hasUnrepresentableRepeat else {
            throw ItemRouterError.unsupported(ItemDetails.unconvertibleReason)
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

    /// The day's blocks, from the sidecar, with `apple-` reminder ids.
    public func plans(on day: Date) async throws -> [PlanBlock] {
        let stored = try await sidecarRead { try await sidecar.plans(on: day) }
        return stored.map(Self.withModelID)
    }

    /// Every plan block whose start is in `range` (one sidecar read), with `apple-` reminder ids.
    public func applePlans(in range: ClosedRange<Date>) async throws -> [PlanBlock] {
        let data = try await sidecarRead { try await sidecar.load() }
        return data.plans.filter { range.contains($0.start) }.map(Self.withModelID)
    }

    /// Replaces the day's blocks in the sidecar (stored under the bare Apple identifier). Blocks
    /// not on `day` and blocks whose reminder is not an Apple one are ignored, so a save of only
    /// such blocks clears the day. Each planned reminder's external id is read through the
    /// repository and recorded with the blocks. Unchanged blocks mean no write and no
    /// `onDidWrite`; an unreadable sidecar throws `.sidecar` and writes nothing.
    public func replacePlans(on day: Date, with blocks: [PlanBlock]) async throws {
        var appleBlocks: [PlanBlock] = []
        var appleRefs: [String: AppleItemRef] = [:]
        for block in blocks {
            guard case .apple(let ref) = ItemOrigin(id: block.reminderID, kind: .reminder),
                  calendar.isDate(block.start, inSameDayAs: day) else { continue }
            var copy = block
            copy.reminderID = ref.identifier
            appleBlocks.append(copy)
            appleRefs[ref.identifier] = ref
        }
        let stored = try await sidecarRead { try await sidecar.plans(on: day) }
        guard appleBlocks != stored else { return }
        var externalIDs: [String: String] = [:]
        for ref in appleRefs.values {
            if let external = await withExternalID(ref).externalID { externalIDs[ref.identifier] = external }
        }
        try await sidecarWrite {
            try await sidecar.replacePlans(on: day, with: appleBlocks, externalIDs: externalIDs)
        }
        await didWrite()
    }

    // MARK: Helpers

    /// The Apple ref behind a model id; `.notApple` (before anything is read or written) otherwise.
    private static func appleRef(_ id: String, _ kind: AppleItemRef.Kind) throws -> AppleItemRef {
        guard case .apple(let ref) = ItemOrigin(id: id, kind: kind) else { throw ItemRouterError.notApple }
        return ref
    }

    /// A stored block with its reminder id turned into the model id (`apple-<identifier>`).
    private static func withModelID(_ block: PlanBlock) -> PlanBlock {
        var copy = block
        copy.reminderID = ItemOrigin.applePrefix + block.reminderID
        return copy
    }

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

    nonisolated static func newEvent(_ event: Event) -> NewEvent {
        NewEvent(title: event.title, notes: event.notes, start: event.start, end: event.end, isAllDay: event.isAllDay,
                 location: event.location, url: event.url, recurrence: event.recurrence)
    }

    nonisolated static func newReminder(_ reminder: Reminder, url: String?) -> NewReminder {
        NewReminder(title: reminder.title, notes: reminder.notes, due: reminder.dueDate,
                    dueHasTime: FormFields.dueHasTime(reminder), priority: reminder.priority,
                    recurrence: reminder.recurrence, url: url)
    }
}
