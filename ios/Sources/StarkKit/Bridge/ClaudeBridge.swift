import Foundation
import os

/// The single entry point for a `stark://add` URL from the Claude Code bridge.
///
/// Order matters: nothing is decoded, validated or imported before the signature over the
/// transmitted (compressed) payload bytes has been verified with the paired secret.
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

    private static let log = Logger(subsystem: "com.caritos.todo-txt", category: "ClaudeBridge")

    private let store: PlannerStore
    private let secrets: SecretStore
    private let replay: BridgeReplayGuard
    private let calendar: Calendar

    public init(store: PlannerStore, secrets: SecretStore, replay: BridgeReplayGuard, calendar: Calendar = .current) {
        self.store = store
        self.secrets = secrets
        self.replay = replay
        self.calendar = calendar
    }

    public func handle(_ url: URL) -> Outcome {
        let outcome = process(url)
        switch outcome {
        case .ignored: break
        case .added(let count, _): Self.log.info("bridge: added \(count, privacy: .public) items")
        case .alreadyAdded: Self.log.info("bridge: already added")
        case .rejected: Self.log.info("bridge: rejected")
        }
        return outcome
    }

    private func process(_ url: URL) -> Outcome {
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

        let models: BridgeImport
        do { models = try batch.models(calendar: calendar) } catch let error as BridgeError {
            return .rejected(error.description)
        } catch {
            return .rejected("Couldn't read the request")
        }

        // `models(calendar:)` already appends the sanitised label to each item's notes.
        let result: ImportOutcome
        do { result = try store.importItems(events: models.events, reminders: models.reminders) } catch let failure as ImportFailure {
            switch failure {
            case .unreadableMonth(let file):
                return .rejected("Couldn't read \(file), so nothing was added.")
            }
        } catch {
            return .rejected("Couldn't save the items, so nothing was added.")
        }

        // A write failure after importItems' pre-check does not throw: the store sets `error`
        // and PlannerFile queues the content for retry, so the items are in memory. Record the
        // batch and report success; the existing error banner reports the save problem.
        replay.record(batch)
        if result.added == 0 && result.alreadyPresent > 0 { return .alreadyAdded }
        return .added(count: result.added, label: BridgeLabel.sanitize(batch.label))
    }
}
