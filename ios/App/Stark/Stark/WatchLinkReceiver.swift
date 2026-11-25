//
//  WatchLinkReceiver.swift
//  Stark
//
//  The iPhone end of the watch link. The watch cannot write to EventKit (watchOS prohibits it), so
//  it sends `complete` and `add` envelopes here over WatchConnectivity; this applies them with
//  StarkKit's `WatchCommandHandler` (tested there) through the app's `AppleItemRepository` and the
//  phone's default calendar/list, and answers. Only this glue touches `WCSession`.
//
//  Background: iOS delivers a live message (`sendMessage`) by launching or waking Stark in the
//  background, and a queued one (`transferUserInfo`) whenever Stark next runs (also in the
//  background). Both are applied at once, foreground or not: the session is activated in
//  `StarkApp.init`, so a launch for a watch message has a delegate before the first callback, and
//  each command runs under a background task so iOS does not suspend Stark mid-write.
//

import Foundation
import StarkKit
import UIKit
import WatchConnectivity

/// `WatchTransport` over `WCSession.default`. The phone only uses `reply`; `send` and `queue` are
/// the watch's direction and work the same way here.
nonisolated final class WCSessionTransport: WatchTransport, @unchecked Sendable {
    struct NotDelivered: Error {}

    private var session: WCSession { WCSession.default }

    var isReachable: Bool {
        WCSession.isSupported() && session.activationState == .activated && session.isReachable
    }

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

    func reply(_ reply: WatchReplyEnvelope) {
        guard let data = try? WatchLinkCoding.encode(reply) else { return }
        let payload = [WatchLinkCoding.replyKey: data]
        let session = self.session
        guard isReachable else {
            session.transferUserInfo(payload)
            return
        }
        // A live reply that fails is queued instead; a duplicate is harmless (the outbox takes the
        // reply for an id it already settled as the same answer).
        session.sendMessage(payload, replyHandler: nil) { _ in session.transferUserInfo(payload) }
    }
}

/// Activates `WCSession` and applies the watch's envelopes.
nonisolated final class WatchLinkReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let noAccessMessage = "Open Stark on your iPhone and allow Calendar and Reminders access."

    private let handler: WatchCommandHandler
    private let transport: WatchTransport
    private let accessGranted: @Sendable () -> Bool
    private let afterWrite: @Sendable () async -> Void
    private let snapshotWanted: @Sendable () -> Void

    /// - Parameters:
    ///   - destinations: the phone's default calendar and list (Settings), resolved fresh.
    ///   - accessGranted: Calendar and Reminders access; without it nothing is attempted.
    ///   - afterWrite: reloads what shows Apple data (overlay, plans, widgets) after a write.
    ///   - snapshotWanted: the session activated or the watch asked for a fresh Up Next snapshot.
    init(repository: ItemRepository,
         destinations: @escaping @Sendable () async -> (calendar: AppleCalendarInfo?, list: AppleCalendarInfo?),
         accessGranted: @escaping @Sendable () -> Bool,
         afterWrite: @escaping @Sendable () async -> Void,
         snapshotWanted: @escaping @Sendable () -> Void = {},
         transport: WatchTransport = WCSessionTransport()) {
        handler = WatchCommandHandler(repository: repository, destinations: destinations,
                                      applied: UserDefaultsAppliedIDStore())
        self.transport = transport
        self.accessGranted = accessGranted
        self.afterWrite = afterWrite
        self.snapshotWanted = snapshotWanted
        super.init()
    }

    /// Call once at launch. Does nothing where WatchConnectivity is unsupported (iPad, Mac).
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: WCSessionDelegate (called on a background queue)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if activationState == .activated { snapshotWanted() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The owner switched to another watch: activate again for the new one.
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    /// A live message: the reply goes back through its reply handler (the watch is waiting on it).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        let answer = ReplyHandlerBox(replyHandler)
        if message[WatchLinkCoding.requestSnapshotKey] != nil {
            snapshotWanted()
            answer.call([:])
            return
        }
        guard let envelope = WatchLinkCoding.envelope(in: message) else {
            answer.call([:])
            return
        }
        Task {
            let reply = await self.process(envelope)
            guard let data = try? WatchLinkCoding.encode(WatchReplyEnvelope(id: envelope.id, reply: reply)) else {
                answer.call([:])
                return
            }
            answer.call([WatchLinkCoding.replyKey: data])
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receiveQueued(message)
    }

    /// A queued envelope (`transferUserInfo`): the reply goes back as its own message.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receiveQueued(userInfo)
    }

    private func receiveQueued(_ payload: [String: Any]) {
        if payload[WatchLinkCoding.requestSnapshotKey] != nil { snapshotWanted() }
        guard let envelope = WatchLinkCoding.envelope(in: payload) else { return }
        Task {
            let reply = await self.process(envelope)
            self.transport.reply(WatchReplyEnvelope(id: envelope.id, reply: reply))
        }
    }

    private func process(_ envelope: WatchEnvelope) async -> WatchReply {
        let background = await BackgroundTask.begin()
        defer { Task { @MainActor in background.end() } }
        guard accessGranted() else { return .failed(Self.noAccessMessage) }
        let reply = await handler.handle(envelope)
        if case .done = reply { await afterWrite() }
        return reply
    }
}

/// WatchConnectivity's reply handler is not `Sendable`; it is called exactly once, from any queue.
private nonisolated final class ReplyHandlerBox: @unchecked Sendable {
    private let handler: ([String: Any]) -> Void
    init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }
    func call(_ payload: [String: Any]) { handler(payload) }
}

/// Keeps Stark running while a watch command is applied in the background.
@MainActor
private final class BackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    static func begin() -> BackgroundTask {
        let task = BackgroundTask()
        task.identifier = UIApplication.shared.beginBackgroundTask(withName: "Stark watch command") { [weak task] in
            task?.end()
        }
        return task
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
