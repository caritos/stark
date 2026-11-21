// ios/Tests/StarkKitTests/ReviewPromptTests.swift
import Testing
import Foundation
@testable import StarkKit

private func freshDefaults() -> UserDefaults {
    let name = "ReviewPromptTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private let day: TimeInterval = 86_400
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func ready(_ store: ReviewPromptStore) {
    for _ in 0..<3 { store.recordLaunch() }
    for _ in 0..<5 { store.recordCompletion() }
}

@Suite struct ReviewPromptPolicyTests {
    @Test func notDueOnFirstLaunchesEvenWithManyCompletions() {
        let s = ReviewPromptState(launches: 2, completions: 50)
        #expect(!ReviewPromptPolicy.shouldPrompt(s, now: t0, version: "1.0"))
    }

    @Test func notDueBeforeFiveCompletions() {
        let s = ReviewPromptState(launches: 10, completions: 4)
        #expect(!ReviewPromptPolicy.shouldPrompt(s, now: t0, version: "1.0"))
    }

    @Test func dueAtThresholds() {
        let s = ReviewPromptState(launches: 3, completions: 5)
        #expect(ReviewPromptPolicy.shouldPrompt(s, now: t0, version: "1.0"))
    }

    @Test func oncePerVersionEvenAfterCooldown() {
        var s = ReviewPromptState(launches: 9, completions: 99)
        s.markPrompted(now: t0, version: "1.0")
        #expect(!ReviewPromptPolicy.shouldPrompt(s, now: t0.addingTimeInterval(400 * day), version: "1.0"))
    }

    @Test func notAgainWithinCooldownEvenForNewVersion() {
        var s = ReviewPromptState(launches: 9, completions: 99)
        s.markPrompted(now: t0, version: "1.0")
        #expect(!ReviewPromptPolicy.shouldPrompt(s, now: t0.addingTimeInterval(119 * day), version: "1.1"))
    }

    @Test func dueAgainForNewVersionAfterCooldown() {
        var s = ReviewPromptState(launches: 9, completions: 99)
        s.markPrompted(now: t0, version: "1.0")
        #expect(ReviewPromptPolicy.shouldPrompt(s, now: t0.addingTimeInterval(120 * day), version: "1.1"))
    }

    @Test func clockSetBackCountsAsAskedRecently() {
        var s = ReviewPromptState(launches: 9, completions: 99)
        s.markPrompted(now: t0, version: "1.0")
        #expect(!ReviewPromptPolicy.shouldPrompt(s, now: t0.addingTimeInterval(-10 * day), version: "1.1"))
    }

    @Test func negativeCountsClampToZero() {
        let s = ReviewPromptState(launches: -5, completions: -1)
        #expect(s.launches == 0 && s.completions == 0)
    }
}

@Suite struct ReviewPromptStoreTests {
    @Test func firstLaunchesAreNotDue() {
        let store = ReviewPromptStore(defaults: freshDefaults())
        store.recordLaunch()
        for _ in 0..<5 { store.recordCompletion() }
        #expect(!store.claimPrompt(now: t0, version: "1.0"))
    }

    @Test func dueAfterThresholdsThenClaimedOnce() {
        let store = ReviewPromptStore(defaults: freshDefaults())
        ready(store)
        #expect(store.claimPrompt(now: t0, version: "1.0"))
        #expect(!store.claimPrompt(now: t0, version: "1.0"))
    }

    @Test func cooldownAndVersionSurviveRelaunch() {
        let defaults = freshDefaults()
        ready(ReviewPromptStore(defaults: defaults))
        #expect(ReviewPromptStore(defaults: defaults).claimPrompt(now: t0, version: "1.0"))
        let relaunched = ReviewPromptStore(defaults: defaults)
        #expect(!relaunched.claimPrompt(now: t0.addingTimeInterval(30 * day), version: "1.1"))
        #expect(relaunched.claimPrompt(now: t0.addingTimeInterval(200 * day), version: "1.1"))
    }

    @Test func countersPersistAcrossRelaunch() {
        let defaults = freshDefaults()
        let a = ReviewPromptStore(defaults: defaults)
        a.recordLaunch()
        a.recordCompletion()
        let b = ReviewPromptStore(defaults: defaults)
        #expect(b.load().launches == 1 && b.load().completions == 1)
    }

    @Test func corruptDataLoadsEmptyAndRecovers() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: ReviewPromptStore.key)
        let store = ReviewPromptStore(defaults: defaults)
        #expect(store.load() == ReviewPromptState())
        #expect(!store.claimPrompt(now: t0, version: "1.0"))
        store.recordLaunch()
        #expect(store.load().launches == 1)
    }

    @Test func wrongTypeStoredLoadsEmpty() {
        let defaults = freshDefaults()
        defaults.set("oops", forKey: ReviewPromptStore.key)
        #expect(ReviewPromptStore(defaults: defaults).load() == ReviewPromptState())
    }

    @Test func negativeStoredCountsAreClampedOnLoad() {
        let defaults = freshDefaults()
        defaults.set(Data(#"{"launches":-4,"completions":-2}"#.utf8), forKey: ReviewPromptStore.key)
        let s = ReviewPromptStore(defaults: defaults).load()
        #expect(s.launches == 0 && s.completions == 0)
    }

    @Test func disabledStoreNeverClaims() {
        let store = ReviewPromptStore(defaults: freshDefaults(), enabled: false)
        ready(store)
        #expect(!store.claimPrompt(now: t0, version: "1.0"))
    }
}
