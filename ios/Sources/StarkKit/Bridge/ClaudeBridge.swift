import Foundation
import os

/// The single entry point for a `stark://add` URL from the Claude Code bridge.
///
/// Order matters: nothing is decoded, validated or written before the signature over the
/// transmitted (compressed) payload bytes has been verified with the paired secret.
///
/// Accepted items are created in Apple Calendar (events, default calendar) and Reminders
/// (reminders, default list). Idempotency per item: the sidecar's bridge ledger maps each bridge
/// item id (derived from the item's content by the CLI) to the Apple item it created; ids already
/// in the ledger are skipped, so re-sending a file adds only what is missing and an item the owner
/// deleted in Apple stays deleted. The replay guard still catches the same batch id at once.
///
/// A batch is all or nothing: it is validated whole, the items not yet in the ledger are saved with
/// one `addBatch` (one commit, rolled back on failure), and only after that succeeds are the ledger
/// entries written (one sidecar write) and the batch id recorded. A failed save records nothing, so
/// the same URL can simply be sent again. Calls are handled one at a time, in arrival order.
@MainActor
public final class ClaudeBridge {
    public enum Outcome: Equatable, Sendable {
        case ignored
        case added(count: Int, label: String?)
        case alreadyAdded
        case rejected(String)

        public var notice: String? {
            switch self {
            case .ignored: return nil
            case .added(let count, let label):
                var text = "Added \(count) \(count == 1 ? "item" : "items")"
                if let label, !label.isEmpty { text += " (\(label))" }
                return text
            case .alreadyAdded: return "Already added"
            case .rejected(let text): return text
            }
        }
    }

    /// Shown when Calendar or Reminders access is missing.
    public static let needsAccess =
        "Stark needs Calendar and Reminders access, so nothing was added. Open Stark, allow access, then send again."

    private static let log = Logger(subsystem: "com.caritos.todo-txt", category: "ClaudeBridge")

    private let repository: any ItemRepository
    private let sidecar: ItemSidecar
    private let destinations: any DefaultDestinations
    private let hasAccess: @MainActor () -> Bool
    private let secrets: SecretStore
    private let replay: BridgeReplayGuard
    private let calendar: Calendar
    /// The previous call; each call waits for it so two sends of one file cannot both pass the
    /// ledger check before either has written to it.
    private var tail: Task<Void, Never>?

    /// `hasAccess` is true when Stark has full Calendar and Reminders access.
    public init(repository: any ItemRepository, sidecar: ItemSidecar, destinations: any DefaultDestinations,
                hasAccess: @escaping @MainActor () -> Bool, secrets: SecretStore, replay: BridgeReplayGuard,
                calendar: Calendar = .current) {
        self.repository = repository
        self.sidecar = sidecar
        self.destinations = destinations
        self.hasAccess = hasAccess
        self.secrets = secrets
        self.replay = replay
        self.calendar = calendar
    }

    public func handle(_ url: URL) async -> Outcome {
        let previous = tail
        let work = Task { @MainActor in
            await previous?.value
            return await self.process(url)
        }
        tail = Task { @MainActor in _ = await work.value }
        let outcome = await work.value
        switch outcome {
        case .ignored: break
        case .added(let count, _): Self.log.info("bridge: added \(count, privacy: .public) items")
        case .alreadyAdded: Self.log.info("bridge: already added")
        case .rejected: Self.log.info("bridge: rejected")
        }
        return outcome
    }

    private func process(_ url: URL) async -> Outcome {
        guard let (payload, signature) = BridgeCodec.parse(url) else {
            Self.log.info("bridge: ignored (not a bridge URL)")
            return .ignored
        }
        // Cheap guard so decode is never reached with an oversized blob.
        guard payload.count <= BridgeCodec.maxEncodedBytes * 3 / 4 else {
            Self.log.info("bridge: ignored (oversized)")
            return .ignored
        }
        let secret: Data
        do {
            guard let s = try secrets.read(), !s.isEmpty else {
                Self.log.info("bridge: ignored (not paired)")
                return .ignored
            }
            secret = s
        } catch {
            Self.log.error("bridge: ignored (secret store read failed)")
            return .ignored
        }
        guard BridgeAuth.verify(payload: payload, signature: signature, secret: secret) else {
            Self.log.info("bridge: ignored (bad signature)")
            return .ignored
        }

        let batch: BridgeBatch
        do { batch = try BridgeCodec.decode(payload) } catch {
            return .rejected("Couldn't read the request")
        }
        let id = batch.batch.prefix(64)

        switch replay.check(batch) {
        case .accept: break
        case .duplicate:
            Self.log.info("bridge: duplicate batch \(String(id), privacy: .private)")
            return .alreadyAdded
        case .expired, .fromFuture:
            return .rejected("Request is too old or from the future. Check the Mac and phone clocks.")
        }

        // All-or-nothing validation; `models(calendar:)` also appends the sanitised label to notes.
        let models: BridgeImport
        do { models = try batch.models(calendar: calendar) } catch let error as BridgeError {
            return .rejected(error.description)
        } catch {
            return .rejected("Couldn't read the request")
        }

        guard hasAccess() else { return .rejected(Self.needsAccess) }

        let ledger: [String: String]
        do { ledger = try await sidecar.load().bridgeLedger } catch {
            Self.log.error("bridge: sidecar unreadable")
            return .rejected("Stark couldn't read its record of added items, so nothing was added.")
        }
        let events = models.events.filter { ledger[$0.id] == nil }
        let reminders = models.reminders.filter { ledger[$0.id] == nil }
        guard !events.isEmpty || !reminders.isEmpty else {
            replay.record(batch)
            return .alreadyAdded
        }

        let calendarID = destinations.calendarID
        let listID = destinations.listID
        if (!events.isEmpty && calendarID == nil) || (!reminders.isEmpty && listID == nil),
           let problem = DefaultDestination.problem(calendarID: events.isEmpty ? "" : calendarID,
                                                    listID: reminders.isEmpty ? "" : listID) {
            return .rejected(problem)
        }

        let refs: [AppleItemRef]
        do {
            refs = try await repository.addBatch(
                events: events.map { (ItemRouter.newEvent($0), calendarID ?? "") },
                reminders: reminders.map { (ItemRouter.newReminder($0, url: nil), listID ?? "") })
        } catch {
            Self.log.error("bridge: save failed: \(String(describing: error), privacy: .public)")
            return .rejected(Self.saveFailed(error))
        }

        // Ledger right after the commit, in one write. `addBatch` returns refs in input order,
        // events first. If this write fails the items are in Apple but not ledgered: the replay
        // record below still catches the same URL; a re-send under a new batch id would add them
        // again (logged, and the window is this one failed write).
        let ids = events.map(\.id) + reminders.map(\.id)
        let entries = zip(ids, refs).map {
            BridgeLedgerEntry(itemID: $0.0, identifier: $0.1.identifier, externalID: $0.1.externalID)
        }
        do { try await sidecar.recordBridge(entries) } catch {
            Self.log.error("bridge: added \(refs.count, privacy: .public) items but the ledger write failed")
        }
        replay.record(batch)
        return .added(count: refs.count, label: BridgeLabel.sanitize(batch.label))
    }

    private static func saveFailed(_ error: Error) -> String {
        switch error as? ItemRepositoryError {
        case .notWritable:
            return "The default calendar or list can't be changed, so nothing was added. Choose another in Settings."
        case .unrepresentable(let text):
            return "Couldn't add to Apple Calendar or Reminders (\(text)), so nothing was added."
        case .saveFailed(let text):
            return "Couldn't save to Apple Calendar or Reminders (\(text)), so nothing was added."
        case .notFound, nil:
            return "Couldn't save to Apple Calendar or Reminders, so nothing was added."
        }
    }
}
