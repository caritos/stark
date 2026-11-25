import Foundation
import Observation

/// The watch's add flow: a dictated phrase becomes a draft the owner confirms, then one `add`
/// envelope goes to the iPhone, which does the write. The phase after sending is derived from the
/// outbox's status for that envelope, so a reply that arrives later (a phone that was out of reach)
/// moves `.waiting` to `.saved` or `.failed` with no extra call.
@MainActor @Observable
public final class WatchAddModel {
    public enum Phase: Equatable {
        case idle, confirming(WatchAddDraft), sending, waiting
        case saved(notice: String?, warning: String?)
        case failed(String)
    }

    private enum Stage {
        case idle
        case confirming(WatchAddDraft)
        /// `confirm` is running and has not got an envelope id yet.
        case submitting(WatchAddDraft)
        case tracking(WatchAddDraft, UUID)
        /// Refused before any envelope existed (queue full).
        case refused(WatchAddDraft, String)
    }

    private var stage: Stage = .idle

    @ObservationIgnored public let outbox: WatchOutbox
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(outbox: WatchOutbox, now: @escaping @Sendable () -> Date = Date.init,
                calendar: Calendar = .current) {
        self.outbox = outbox
        self.now = now
        self.calendar = calendar
    }

    public var phase: Phase {
        switch stage {
        case .idle: return .idle
        case .confirming(let draft): return .confirming(draft)
        case .submitting: return .sending
        case .refused(_, let message): return .failed(message)
        case .tracking(_, let id):
            switch outbox.statuses[id] {
            case .sending: return .sending
            case .waiting, nil: return .waiting
            case .done(let reply):
                if case .done(let notice, let warning) = reply { return .saved(notice: notice, warning: warning) }
                return .failed("Couldn't add")
            case .failed(let message): return .failed(message)
            }
        }
    }

    /// idle -> confirming. Stays idle for empty text; ignored while an add is in flight or waiting.
    public func dictated(_ text: String) {
        switch phase {
        case .sending, .waiting: return
        default: break
        }
        if let draft = WatchAddDraft.make(dictation: text, now: now(), calendar: calendar) {
            stage = .confirming(draft)
        } else {
            stage = .idle
        }
    }

    /// Sends the draft once. Only runs from `.confirming` or `.failed` (a retry keeps the draft);
    /// a second call while sending, waiting or saved does nothing.
    public func confirm() async {
        let draft: WatchAddDraft
        switch (stage, phase) {
        case (.confirming(let d), _): draft = d
        case (.refused(let d, _), _): draft = d
        case (.tracking(let d, _), .failed): draft = d
        default: return
        }
        stage = .submitting(draft)
        if let id = await outbox.submit(.add(draft)) {
            stage = .tracking(draft, id)
        } else {
            stage = .refused(draft, outbox.lastError ?? "Couldn't send")
        }
    }

    /// Back to idle; sends nothing. An envelope already sent stays with the outbox.
    public func cancel() {
        if case .submitting = stage { return }
        stage = .idle
    }
}
