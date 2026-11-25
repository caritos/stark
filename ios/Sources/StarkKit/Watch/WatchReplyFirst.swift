import Foundation

/// Orders the phone's work for one watch command: apply it, hand the answer to the watch, and only
/// then run the slow reloads (agenda fetch, plan cache, widgets). Reloading first kept the watch on
/// "Sending" for seconds and let its reply time out, so the outbox queued a duplicate of an item
/// that was already saved.
public enum WatchReplyFirst {
    /// - Parameters:
    ///   - produce: applies the command and returns the answer.
    ///   - deliver: hands the answer to the watch; called synchronously, before `afterWrite`.
    ///   - afterWrite: the reloads; run only after a `.done` answer, after `deliver` returned.
    public static func run(produce: () async -> WatchReply,
                           deliver: (WatchReply) -> Void,
                           afterWrite: () async -> Void) async {
        let reply = await produce()
        deliver(reply)
        if case .done = reply { await afterWrite() }
    }
}
