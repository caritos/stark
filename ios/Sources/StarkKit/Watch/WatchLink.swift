import Foundation

/// What the watch asks the iPhone to do. EventKit writes are unavailable on watchOS, so the watch
/// sends these and the iPhone app writes (`WatchCommandHandler`). Dates are absolute: the watch
/// parsed them, the phone does no re-parsing.
public enum WatchCommand: Codable, Equatable, Sendable {
    /// Completes one occurrence of a reminder (reminders only; `identifier` is EventKit's
    /// `calendarItemIdentifier`, without Stark's `apple-` prefix).
    case complete(identifier: String, externalID: String?, occurrence: Date)
    case add(WatchAddDraft)
}

/// One command with the id the phone remembers (so a redelivered command is acknowledged, not
/// applied twice) and the time the watch sent it.
public struct WatchEnvelope: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let sentAt: Date
    public let command: WatchCommand

    public init(id: UUID = UUID(), sentAt: Date, command: WatchCommand) {
        self.id = id
        self.sentAt = sentAt
        self.command = command
    }

    /// By id only (equal envelopes have equal ids, so this agrees with `==`).
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The phone's answer. `done` carries "Added to Home · iCloud" for an add (nil for a complete) and
/// the local-only warning when the destination does not sync.
public enum WatchReply: Codable, Equatable, Sendable {
    case done(notice: String?, warning: String?)
    case failed(String)
}

public struct WatchReplyEnvelope: Codable, Equatable, Sendable {
    public let id: UUID
    public let reply: WatchReply

    public init(id: UUID, reply: WatchReply) {
        self.id = id
        self.reply = reply
    }
}

/// The link between the watch and the phone. Only app-target glue implements it over
/// `WCSession`; the Kit never imports WatchConnectivity.
public protocol WatchTransport: Sendable {
    var isReachable: Bool { get }
    /// A live message (`sendMessage`); throws when it cannot be delivered.
    func send(_ envelope: WatchEnvelope) async throws -> WatchReply
    /// Queued delivery that survives a relaunch (`transferUserInfo`).
    func queue(_ envelope: WatchEnvelope)
    /// Phone to watch: live when reachable, else queued.
    func reply(_ reply: WatchReplyEnvelope)
}

/// How envelopes travel inside WatchConnectivity's property-list dictionaries: JSON `Data` under
/// one key, so both sides share one encoding.
public enum WatchLinkCoding {
    /// `[envelopeKey: Data]` carries a `WatchEnvelope` (watch to phone).
    public static let envelopeKey = "stark.envelope"
    /// `[replyKey: Data]` carries a `WatchReplyEnvelope` (phone to watch).
    public static let replyKey = "stark.reply"

    /// `[snapshotKey: Data]` carries a `WatchSnapshot` (phone to watch, application context).
    public static let snapshotKey = "stark.snapshot"
    /// `[requestSnapshotKey: true]` asks the phone to push a fresh snapshot (watch to phone).
    public static let requestSnapshotKey = "stark.requestSnapshot"

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    /// The envelope in a received WatchConnectivity dictionary, or nil when it carries none.
    public static func envelope(in message: [String: Any]) -> WatchEnvelope? {
        guard let data = message[envelopeKey] as? Data else { return nil }
        return try? decode(WatchEnvelope.self, from: data)
    }

    /// The reply envelope in a received WatchConnectivity dictionary, or nil when it carries none.
    public static func reply(in message: [String: Any]) -> WatchReplyEnvelope? {
        guard let data = message[replyKey] as? Data else { return nil }
        return try? decode(WatchReplyEnvelope.self, from: data)
    }

    /// The snapshot in a received WatchConnectivity dictionary, or nil when it carries none.
    public static func snapshot(in message: [String: Any]) -> WatchSnapshot? {
        guard let data = message[snapshotKey] as? Data else { return nil }
        return try? decode(WatchSnapshot.self, from: data)
    }
}
