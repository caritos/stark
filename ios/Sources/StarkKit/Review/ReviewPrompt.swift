// ios/Sources/StarkKit/Review/ReviewPrompt.swift
import Foundation

/// What the app remembers, on the device only, to decide when to ask for an App Store rating.
public struct ReviewPromptState: Codable, Equatable, Sendable {
    /// Cold launches so far.
    public var launches: Int
    /// Reminders completed (committed after the undo window) in total.
    public var completions: Int
    public var lastPromptedAt: Date?
    public var lastPromptedVersion: String?

    public init(launches: Int = 0, completions: Int = 0, lastPromptedAt: Date? = nil, lastPromptedVersion: String? = nil) {
        self.launches = max(0, launches)
        self.completions = max(0, completions)
        self.lastPromptedAt = lastPromptedAt
        self.lastPromptedVersion = lastPromptedVersion
    }

    public mutating func recordLaunch() { launches = Self.increment(launches) }
    public mutating func recordCompletion() { completions = Self.increment(completions) }

    public mutating func markPrompted(now: Date, version: String) {
        lastPromptedAt = now
        lastPromptedVersion = version
    }

    private static func increment(_ n: Int) -> Int { n == Int.max ? n : n + 1 }
}

/// Ask only after the user has felt value: from the third launch and the fifth completed
/// reminder, once per app version, at least 120 days apart (at most about 3 a year; Apple caps it
/// too). The caller asks only right after a completion, never from onboarding, and never gates
/// the system prompt on sentiment.
public enum ReviewPromptPolicy {
    public static let minLaunches = 3
    public static let minCompletions = 5
    public static let minDaysBetween = 120

    public static func shouldPrompt(_ state: ReviewPromptState, now: Date, version: String) -> Bool {
        guard state.launches >= minLaunches, state.completions >= minCompletions else { return false }
        guard state.lastPromptedVersion != version else { return false }
        if let last = state.lastPromptedAt {
            let days = now.timeIntervalSince(last) / 86_400
            // A negative gap means the clock was set back: treat it as "asked recently".
            guard days >= Double(minDaysBetween) else { return false }
        }
        return true
    }
}

/// The counters in UserDefaults as JSON (non-secret, device only). Missing or corrupt data loads
/// as empty, so a bad value can only delay the prompt, never crash or spam.
public struct ReviewPromptStore {
    public static let key = "reviewPromptState"
    private let defaults: UserDefaults
    private let enabled: Bool

    public init(defaults: UserDefaults = .standard, enabled: Bool = true) {
        self.defaults = defaults
        self.enabled = enabled
    }

    public func load() -> ReviewPromptState {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(ReviewPromptState.self, from: data) else { return ReviewPromptState() }
        // The synthesized decoder skips the init's clamping; rebuild through it.
        return ReviewPromptState(launches: decoded.launches, completions: decoded.completions,
                                 lastPromptedAt: decoded.lastPromptedAt, lastPromptedVersion: decoded.lastPromptedVersion)
    }

    public func recordLaunch() { update { $0.recordLaunch() } }
    public func recordCompletion() { update { $0.recordCompletion() } }

    /// True when the system rating dialog should be requested now. Marks the ask as made, so a
    /// second call cannot ask twice.
    public func claimPrompt(now: Date = Date(), version: String) -> Bool {
        guard enabled else { return false }
        var state = load()
        guard ReviewPromptPolicy.shouldPrompt(state, now: now, version: version) else { return false }
        state.markPrompted(now: now, version: version)
        save(state)
        return true
    }

    private func update(_ change: (inout ReviewPromptState) -> Void) {
        var state = load()
        change(&state)
        save(state)
    }

    private func save(_ state: ReviewPromptState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
