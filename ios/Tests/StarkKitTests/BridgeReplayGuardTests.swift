import Testing
import Foundation
@testable import StarkKit

@Suite struct BridgeReplayGuardTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func batch(_ id: String = "b1", age: TimeInterval = 0) -> BridgeBatch {
        BridgeBatch(batch: id, issuedAt: now.timeIntervalSince1970 - age, label: nil, items: [])
    }
    func make(_ store: ReplayStore = InMemoryReplayStore(), capacity: Int = 200) -> BridgeReplayGuard {
        BridgeReplayGuard(store: store, now: { now }, capacity: capacity)
    }

    @Test func freshAccepts() { #expect(make().check(batch()) == .accept) }
    @Test func ageBoundary() {
        let g = make()
        #expect(g.check(batch(age: 599)) == .accept)
        #expect(g.check(batch(age: 600)) == .accept)
        #expect(g.check(batch(age: 601)) == .expired)
    }
    @Test func futureBoundary() {
        let g = make()
        #expect(g.check(batch(age: -120)) == .accept)
        #expect(g.check(batch(age: -121)) == .fromFuture)
    }
    @Test func nonFiniteIssuedAtExpired() {
        let g = make()
        for v in [Double.nan, .infinity, -.infinity] {
            let b = BridgeBatch(batch: "x", issuedAt: v, label: nil, items: [])
            #expect(g.check(b) == .expired)
        }
    }
    @Test func recordMakesDuplicateCheckDoesNot() {
        let g = make()
        _ = g.check(batch())
        #expect(g.check(batch()) == .accept)
        g.record(batch())
        #expect(g.check(batch()) == .duplicate)
    }
    @Test func recordTwiceKeepsOne() {
        let store = InMemoryReplayStore()
        let g = make(store)
        g.record(batch()); g.record(batch())
        #expect(store.load() == ["b1"])
    }
    @Test func capacityEvictsOldest() {
        let store = InMemoryReplayStore()
        let g = make(store)
        for i in 0..<201 { g.record(batch("id\(i)")) }
        #expect(store.load().count == 200)
        #expect(g.check(batch("id0")) == .accept)
        #expect(g.check(batch("id0", age: 601)) == .expired)
        #expect(g.check(batch("id1")) == .duplicate)
        #expect(g.check(batch("id200")) == .duplicate)
    }
    @Test func survivesNewGuard() {
        let store = InMemoryReplayStore()
        make(store).record(batch())
        #expect(make(store).check(batch()) == .duplicate)
    }
    @Test func userDefaultsStore() {
        let name = "bridge-replay-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let s1 = UserDefaultsReplayStore(defaults: d)
        #expect(s1.load() == [])
        s1.save(["a", "b"])
        #expect(UserDefaultsReplayStore(defaults: d).load() == ["a", "b"])
    }
}
