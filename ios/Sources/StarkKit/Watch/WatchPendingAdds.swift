import Foundation
import Observation

/// Adds that were submitted to the iPhone and are not confirmed done: shown on the watch's list
/// until they succeed (the entry disappears) or the owner dismisses them, so a late failure from
/// the phone, or "Not delivered" after 7 days, is never lost silently. State is read from the
/// outbox, so a reply arriving later updates it with no extra call.
@MainActor @Observable
public final class WatchPendingAdds {
    public enum State: Equatable { case waiting, failed(String) }

    public struct Entry: Equatable, Identifiable {
        /// The envelope id of the latest send.
        public let id: UUID
        public let draft: WatchAddDraft
        public let state: State
    }

    private var tracked: [(id: UUID, draft: WatchAddDraft)] = []
    @ObservationIgnored public let outbox: WatchOutbox

    /// Seeds from the outbox's still-waiting `add` envelopes, so a relaunch shows them.
    public init(outbox: WatchOutbox) {
        self.outbox = outbox
        for envelope in outbox.waitingEnvelopes {
            if case .add(let draft) = envelope.command { tracked.append((envelope.id, draft)) }
        }
    }

    /// Everything submitted and not done, oldest first.
    public var entries: [Entry] {
        tracked.compactMap { item in
            switch outbox.statuses[item.id] {
            case .done(.done): return nil
            case .done(.failed(let message)), .failed(let message):
                return Entry(id: item.id, draft: item.draft, state: .failed(message))
            default: return Entry(id: item.id, draft: item.draft, state: .waiting)
            }
        }
    }

    /// Starts showing a submitted add (a no-op for an id already shown).
    public func track(_ id: UUID, draft: WatchAddDraft) {
        guard !tracked.contains(where: { $0.id == id }) else { return }
        tracked.append((id, draft))
    }

    public func dismiss(_ id: UUID) { tracked.removeAll { $0.id == id } }

    /// Sends the same draft again as a NEW envelope and replaces the failed entry. If the failure
    /// was "Not delivered" (7 days) the phone may still add the old one later, so a duplicate is
    /// possible. When the outbox refuses (queue full) the failed entry stays.
    public func retry(_ id: UUID) async {
        guard let index = tracked.firstIndex(where: { $0.id == id }),
              case .failed = entries.first(where: { $0.id == id })?.state else { return }
        let draft = tracked[index].draft
        guard let newID = await outbox.submit(.add(draft)) else { return }
        if let i = tracked.firstIndex(where: { $0.id == id }) { tracked[i] = (newID, draft) }
    }
}
