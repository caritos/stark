// ios/Sources/StarkKit/Apple/ConferenceLink.swift
import Foundation

/// A video-call link found in an event's URL, location or notes. Detection only parses text; the
/// link is never fetched and is opened only when the owner taps Join.
public struct ConferenceLink: Equatable, Sendable {
    public enum Provider: String, Equatable, Sendable {
        case zoom, googleMeet, teams, webex, faceTime

        public var displayName: String {
            switch self {
            case .zoom: return "Zoom"
            case .googleMeet: return "Google Meet"
            case .teams: return "Teams"
            case .webex: return "Webex"
            case .faceTime: return "FaceTime"
            }
        }
    }

    public let provider: Provider
    public let url: URL

    public init(provider: Provider, url: URL) {
        self.provider = provider
        self.url = url
    }

    /// "Join Zoom".
    public var title: String { "Join \(provider.displayName)" }
    /// "Join Zoom meeting".
    public var accessibilityLabel: String { "Join \(provider.displayName) meeting" }
}

public enum ConferenceLinkDetector {
    /// The first supported https conference link, searching `url`, then `location`, then `notes`.
    public static func detect(url: String?, location: String?, notes: String?) -> ConferenceLink? {
        for text in [url, location, notes] {
            guard let text, !text.isEmpty else { continue }
            if let link = firstLink(in: text) { return link }
        }
        return nil
    }

    // swiftlint:disable:next force_try
    private static let candidate = try! NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9+.\-]*://[^\s<>"']+"#)
    private static let trailing = CharacterSet(charactersIn: ".,;:!?)]}>'\"")

    private static func firstLink(in text: String) -> ConferenceLink? {
        let whole = NSRange(text.startIndex..., in: text)
        for match in candidate.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text) else { continue }
            var raw = String(text[range])
            while let last = raw.unicodeScalars.last, trailing.contains(last) { raw.removeLast() }
            if let link = classify(raw) { return link }
        }
        return nil
    }

    private static func classify(_ raw: String) -> ConferenceLink? {
        guard let components = URLComponents(string: raw), let url = components.url,
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        let path = components.path.lowercased()
        func isHost(_ base: String) -> Bool { host == base || host.hasSuffix("." + base) }
        /// A path starting with one of `prefixes`, with something after a prefix that ends in "/".
        func under(_ prefixes: [String]) -> Bool {
            prefixes.contains { $0.hasSuffix("/") ? (path.hasPrefix($0) && path.count > $0.count) : path.hasPrefix($0) }
        }

        if isHost("zoom.us"), under(["/j/", "/my/", "/s/", "/w/"]) { return .init(provider: .zoom, url: url) }
        if host == "meet.google.com", path.count > 1 { return .init(provider: .googleMeet, url: url) }
        if host == "teams.microsoft.com", under(["/l/meetup-join", "/meet/"]) { return .init(provider: .teams, url: url) }
        if host == "teams.live.com", under(["/meet/"]) { return .init(provider: .teams, url: url) }
        if isHost("webex.com"), path.count > 1 { return .init(provider: .webex, url: url) }
        if host == "facetime.apple.com", under(["/join"]) { return .init(provider: .faceTime, url: url) }
        return nil
    }
}
