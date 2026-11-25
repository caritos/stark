//
//  WCSessionTransport.swift
//  StarkWatch
//
//  The watch end of the link: `WatchTransport` over `WCSession.default`, plus the delegate that
//  hands the iPhone's snapshots (application context) and reply envelopes to the model and the
//  outbox. When the session activates (and when the app becomes active) it asks the phone for a
//  fresh snapshot. Nothing here reads EventKit.
//

import Foundation
import StarkKit
import WatchConnectivity

nonisolated final class WCSessionTransport: NSObject, WatchTransport, WCSessionDelegate, @unchecked Sendable {
    struct NotDelivered: Error {}

    private let lock = NSLock()
    private var snapshotHandler: (@Sendable (WatchSnapshot) -> Void)?
    private var replyHandler: (@Sendable (WatchReplyEnvelope) -> Void)?

    private var session: WCSession { WCSession.default }

    var isReachable: Bool {
        WCSession.isSupported() && session.activationState == .activated && session.isReachable
    }

    /// Wire the handlers, then activate. Handlers are called on a background queue. A snapshot
    /// already waiting in the session's `receivedApplicationContext` is delivered once on activation.
    func start(onSnapshot: @escaping @Sendable (WatchSnapshot) -> Void,
               onReply: @escaping @Sendable (WatchReplyEnvelope) -> Void) {
        lock.withLock {
            snapshotHandler = onSnapshot
            replyHandler = onReply
        }
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    /// Asks the phone for a fresh snapshot: live when reachable (waking the phone app), else one
    /// queued request (never more than one waiting).
    func requestSnapshot() {
        guard WCSession.isSupported(), session.activationState == .activated else { return }
        let payload: [String: Any] = [WatchLinkCoding.requestSnapshotKey: true]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in }, errorHandler: { [session] _ in
                Self.queueRequest(payload, on: session)
            })
        } else {
            Self.queueRequest(payload, on: session)
        }
    }

    private static func queueRequest(_ payload: [String: Any], on session: WCSession) {
        let waiting = session.outstandingUserInfoTransfers.contains {
            $0.userInfo[WatchLinkCoding.requestSnapshotKey] != nil
        }
        if !waiting { session.transferUserInfo(payload) }
    }

    // MARK: WatchTransport

    func send(_ envelope: WatchEnvelope) async throws -> WatchReply {
        let payload = [WatchLinkCoding.envelopeKey: try WatchLinkCoding.encode(envelope)]
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(payload, replyHandler: { answer in
                if let reply = WatchLinkCoding.reply(in: answer) {
                    continuation.resume(returning: reply.reply)
                } else {
                    continuation.resume(throwing: NotDelivered())
                }
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    func queue(_ envelope: WatchEnvelope) {
        guard let data = try? WatchLinkCoding.encode(envelope) else { return }
        session.transferUserInfo([WatchLinkCoding.envelopeKey: data])
    }

    /// Replies travel phone to watch only; the watch never sends one.
    func reply(_ reply: WatchReplyEnvelope) {}

    // MARK: WCSessionDelegate (background queue)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        deliver(context: session.receivedApplicationContext)
        requestSnapshot()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(context: applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { deliver(message: message) }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        deliver(message: message)
        replyHandler([:])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(message: userInfo)
    }

    private func deliver(context: [String: Any]) {
        guard let snapshot = WatchLinkCoding.snapshot(in: context) else { return }
        let handler = lock.withLock { snapshotHandler }
        handler?(snapshot)
    }

    private func deliver(message: [String: Any]) {
        deliver(context: message)  // a snapshot sent as a message is shown the same way
        guard let reply = WatchLinkCoding.reply(in: message) else { return }
        let handler = lock.withLock { replyHandler }
        handler?(reply)
    }
}
