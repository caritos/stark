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
    /// Invitations come from outsiders: only this much of each field is scanned.
    static let scanLimit = 20_000

    /// The first supported https conference link, searching `url`, then `location`, then `notes`.
    public static func detect(url: String?, location: String?, notes: String?) -> ConferenceLink? {
        for text in [url, location, notes] {
            guard let text, !text.isEmpty else { continue }
            if let link = firstLink(in: text) { return link }
        }
        return nil
    }

    // A fixed literal prefix, so the scan is linear (a generic "scheme://" pattern backtracks
    // quadratically on long runs of letters). A link ends at whitespace, a quote, an angle
    // bracket, a comma or a zero-width space.
    // swiftlint:disable:next force_try
    private static let candidate = try! NSRegularExpression(pattern: "https://[^\\s<>\"'\u{200B},\u{FF0C}\u{3002}]+",
                                                            options: [.caseInsensitive])
    private static let trailing = CharacterSet(charactersIn: ".,;:!?)]}>'\"*_\u{201D}\u{2019}\u{2026}\u{3002}\u{FF09}\u{FF0C}")

    private static func firstLink(in field: String) -> ConferenceLink? {
        // The first `scanLimit` UTF-16 units; a split surrogate becomes a replacement character.
        let text = field.utf16.count > scanLimit
            ? String(decoding: Array(field.utf16.prefix(scanLimit)), as: UTF16.self) : field
        let whole = NSRange(location: 0, length: (text as NSString).length)
        for match in candidate.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text) else { continue }
            var raw = String(text[range])
            while let last = raw.unicodeScalars.last, trailing.contains(last) { raw.removeLast() }
            if let link = classify(raw) { return link }
        }
        return nil
    }

    // swiftlint:disable:next force_try
    private static let hostShape = try! NSRegularExpression(pattern: "^[a-z0-9-]+(\\.[a-z0-9-]+)+$")
    // swiftlint:disable:next force_try
    private static let meetCode = try! NSRegularExpression(pattern: "^/[a-z]{3}-[a-z]{4}-[a-z]{3}$")

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func classify(_ raw: String) -> ConferenceLink? {
        guard let components = URLComponents(string: raw), let url = components.url,
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              let decodedHost = components.host, components.percentEncodedHost == decodedHost
        else { return nil }
        var host = decodedHost.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        guard matches(hostShape, host) else { return nil }
        let path = components.path.lowercased()

        func isHost(_ base: String) -> Bool { host == base || host.hasSuffix("." + base) }
        /// The path starts with one of `prefixes`; a prefix ending in "/" needs something after it.
        func under(_ prefixes: [String]) -> Bool {
            prefixes.contains { $0.hasSuffix("/") ? (path.hasPrefix($0) && path.count > $0.count) : path.hasPrefix($0) }
        }

        if isHost("zoom.us") || isHost("zoomgov.com"), under(["/j/", "/my/", "/s/", "/w/"]) {
            return .init(provider: .zoom, url: url)
        }
        if host == "meet.google.com", matches(meetCode, path) || under(["/lookup/"]) {
            return .init(provider: .googleMeet, url: url)
        }
        if host == "teams.microsoft.com", under(["/l/meetup-join/", "/meet/"]) { return .init(provider: .teams, url: url) }
        if host == "teams.live.com", under(["/meet/"]) { return .init(provider: .teams, url: url) }
        if isHost("webex.com"), under(["/meet/", "/join/", "/wbxmjs/", "/webappng/", "/j.php"]) {
            return .init(provider: .webex, url: url)
        }
        if host == "facetime.apple.com", under(["/join"]) { return .init(provider: .faceTime, url: url) }
        return nil
    }
}
