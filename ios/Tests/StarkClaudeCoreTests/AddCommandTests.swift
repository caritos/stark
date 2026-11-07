import Foundation
import Testing
import StarkKit
@testable import StarkClaudeCore

@Suite struct AddCommandTests {
    let secret = BridgeAuth.newSecret()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func make(_ r: FakeRunner, paired: Bool = true, terminate: Bool = false, env: [String: String] = [:]) -> AddCommand {
        var n = 0
        return AddCommand(runner: r, secrets: InMemorySecretStore(initial: paired ? secret : nil),
                          device: DeviceResolver(runner: r, environment: env), now: { t0 },
                          newID: { n += 1; return "gen-\(n)" }, terminateExisting: terminate)
    }
    func json(_ items: Int, label: String? = "demo") -> Data {
        let arr = (0..<items).map { "{\"kind\":\"reminder\",\"title\":\"Task \($0)\",\"start\":\"2026-12-01T09:00\"}" }
        let l = label.map { "\"label\":\"\($0)\"," } ?? ""
        return Data("{\(l)\"items\":[\(arr.joined(separator: ","))]}".utf8)
    }
    func batch(from launch: FakeRunner.Call) throws -> BridgeBatch {
        let i = launch.arguments.firstIndex(of: "--payload-url")!
        let url = try #require(URL(string: launch.arguments[i + 1]))
        let (p, s) = try #require(BridgeCodec.parse(url))
        #expect(BridgeAuth.verify(payload: p, signature: s, secret: secret))
        return try BridgeCodec.decode(p)
    }

    @Test func sendsOneSignedBatchWithFilledIDs() throws {
        let r = FakeRunner()
        let report = try make(r).run(requestJSON: json(2))
        #expect(report.batchesSent == 1 && report.batchesTotal == 1)
        #expect(report.itemIDs.count == 2 && report.itemIDs.allSatisfy { $0.hasPrefix("bridge-") })
        #expect(r.launches.count == 1)
        let call = r.launches[0]
        #expect(call.arguments.starts(with: ["devicectl", "device", "process", "launch", "--device", "AAAA-1111", "--payload-url"]))
        #expect(call.arguments.last == "com.caritos.todo-txt")
        #expect(!call.arguments.contains("--terminate-existing"))
        let b = try batch(from: call)
        #expect(b.issuedAt == t0.timeIntervalSince1970)
        #expect(b.label == "demo")
        #expect(b.items.map(\.id) == report.itemIDs)
        #expect(b.items.map(\.title) == ["Task 0", "Task 1"])
    }
    @Test func keepsGivenIDs() throws {
        let r = FakeRunner()
        let data = Data("{\"items\":[{\"id\":\"mine-1\",\"kind\":\"event\",\"title\":\"E\",\"start\":\"2026-12-01\"}]}".utf8)
        #expect(try make(r).run(requestJSON: data).itemIDs == ["mine-1"])
    }
    @Test func terminateExistingOnlyWhenConfigured() throws {
        let r = FakeRunner()
        _ = try make(r, terminate: true).run(requestJSON: json(1))
        #expect(r.launches[0].arguments.contains("--terminate-existing"))
    }
    @Test func unpairedRunsNothing() {
        let r = FakeRunner()
        #expect(throws: CLIError.notPaired) { try make(r, paired: false).run(requestJSON: json(1)) }
        #expect(r.calls.isEmpty)
    }
    @Test func invalidItemIsCaughtBeforeAnythingRuns() {
        let r = FakeRunner()
        let data = Data("{\"items\":[{\"id\":\"ok-1\",\"kind\":\"reminder\",\"title\":\"A\",\"start\":\"2026-12-01\"},{\"id\":\"bad-2\",\"kind\":\"reminder\",\"title\":\"B\",\"start\":\"nonsense\"}]}".utf8)
        do { _ = try make(r).run(requestJSON: data); Issue.record("expected throw") }
        catch let CLIError.badRequest(message) { #expect(message.contains("bad-2")) }
        catch { Issue.record("wrong error \(error)") }
        #expect(r.calls.isEmpty)
    }
    @Test func garbageJSONIsBadRequest() {
        let r = FakeRunner()
        #expect(throws: CLIError.self) { try make(r).run(requestJSON: Data("nope".utf8)) }
        #expect(r.calls.isEmpty)
    }
    @Test func manyItemsAreSplitAndSentInOrder() throws {
        let r = FakeRunner()
        let report = try make(r).run(requestJSON: json(300))
        #expect(report.batchesTotal >= 2)
        #expect(report.batchesSent == report.batchesTotal)
        let titles = try r.launches.flatMap { try batch(from: $0).items.map(\.title) }
        #expect(titles == (0..<300).map { "Task \($0)" })
        #expect(Set(try r.launches.map { try batch(from: $0).batch }).count == r.launches.count)
    }
    @Test func stopsAtFirstFailure() throws {
        let r = FakeRunner()
        r.launchFailure = { $0 == 2 ? ProcessResult(status: 1, stdout: "", stderr: "boom") : nil }
        do { _ = try make(r).run(requestJSON: json(300)); Issue.record("expected throw") }
        catch let f as AddFailure {
            #expect(f.sent == 1); #expect(f.total >= 2); #expect(f.cause == .launchFailed("boom"))
        }
        #expect(r.launches.count == 2)
    }
    @Test func stderrLockedMapsToPhoneLocked() {
        let r = FakeRunner()
        r.launchFailure = { _ in ProcessResult(status: 1, stdout: "", stderr: "ERROR: device is locked") }
        do { _ = try make(r).run(requestJSON: json(1)); Issue.record("expected throw") }
        catch let f as AddFailure { #expect(f.cause == .phoneLocked) }
        catch { Issue.record("wrong error \(error)") }
    }
    @Test func lockedPhoneRunsNoLaunch() {
        let r = FakeRunner(); r.lockStdout = "• passcodeRequired: true\n"
        do { _ = try make(r).run(requestJSON: json(1)); Issue.record("expected throw") }
        catch let f as AddFailure { #expect(f.cause == .phoneLocked); #expect(f.sent == 0) }
        catch { Issue.record("wrong error \(error)") }
        #expect(r.launches.isEmpty)
        #expect(r.calls.contains { $0.arguments.contains("lockState") && $0.arguments.contains("AAAA-1111") })
    }
    @Test func lockCheckFailureFailsClosed() {
        for result in [ProcessResult(status: 1, stdout: "", stderr: "no route"), ProcessResult(status: 0, stdout: "garbage", stderr: "")] {
            let r = FakeRunner(); r.lockResult = result
            do { _ = try make(r).run(requestJSON: json(1)); Issue.record("expected throw") }
            catch let f as AddFailure {
                guard case .launchFailed(let m) = f.cause else { Issue.record("wrong cause"); continue }
                #expect(m.hasPrefix("couldn't check whether the phone is unlocked"))
            }
            catch { Issue.record("wrong error \(error)") }
            #expect(r.launches.isEmpty)
        }
    }
    @Test func printURLsSendsNothing() throws {
        let r = FakeRunner()
        let (ids, urls) = try make(r).signedURLs(requestJSON: json(2))
        #expect(urls.count == 1); #expect(ids.count == 2)
        #expect(r.calls.isEmpty)
        let (p, s) = try #require(BridgeCodec.parse(urls[0]))
        #expect(BridgeAuth.verify(payload: p, signature: s, secret: secret))
    }

    @Test func idsAreDeterministicAcrossRuns() throws {
        let a = try make(FakeRunner()).signedURLs(requestJSON: json(3)).ids
        let b = try make(FakeRunner()).signedURLs(requestJSON: json(3)).ids
        #expect(a == b)
        #expect(a.allSatisfy { $0.count <= 64 && $0.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil })
    }
    @Test func identicalItemsGetDifferentIDs() throws {
        let item = "{\"kind\":\"reminder\",\"title\":\"Same\",\"start\":\"2026-12-01\"}"
        let ids = try make(FakeRunner()).signedURLs(requestJSON: Data("{\"items\":[\(item),\(item)]}".utf8)).ids
        #expect(ids[0] != ids[1])
        let again = try make(FakeRunner()).signedURLs(requestJSON: Data("{\"items\":[\(item),\(item)]}".utf8)).ids
        #expect(ids == again)
    }
    @Test func changingTheTitleChangesTheID() throws {
        func id(_ t: String) throws -> String {
            try make(FakeRunner()).signedURLs(requestJSON: Data("{\"items\":[{\"kind\":\"reminder\",\"title\":\"\(t)\",\"start\":\"2026-12-01\"}]}".utf8)).ids[0]
        }
        #expect(try id("A") != id("B"))
    }
    @Test func nullAndEmptyIDsAreFilledNonStringRejected() throws {
        let ok = Data("{\"items\":[{\"id\":null,\"kind\":\"reminder\",\"title\":\"A\",\"start\":\"2026-12-01\"},{\"id\":\"\",\"kind\":\"reminder\",\"title\":\"B\",\"start\":\"2026-12-01\"}]}".utf8)
        #expect(try make(FakeRunner()).signedURLs(requestJSON: ok).ids.allSatisfy { $0.hasPrefix("bridge-") })
        let bad = Data("{\"items\":[{\"id\":5,\"kind\":\"reminder\",\"title\":\"Five\",\"start\":\"2026-12-01\"}]}".utf8)
        do { _ = try make(FakeRunner()).signedURLs(requestJSON: bad); Issue.record("expected throw") }
        catch let CLIError.badRequest(m) { #expect(m.contains("Five")) }
    }
    @Test func retryAfterFailureResendsTheSameIDs() throws {
        let r1 = FakeRunner()
        r1.launchFailure = { $0 == 2 ? ProcessResult(status: 1, stdout: "", stderr: "boom") : nil }
        var failure: AddFailure?
        do { _ = try make(r1).run(requestJSON: json(300)) } catch let f as AddFailure { failure = f }
        let f = try #require(failure)
        #expect(f.description.contains(f.itemIDs[0]))
        let r2 = FakeRunner()
        let report = try make(r2).run(requestJSON: json(300))
        #expect(report.itemIDs == f.itemIDs)
        let first = try r1.launches.prefix(1).flatMap { try batch(from: $0).items.map(\.id) }
        let retry = try r2.launches.prefix(1).flatMap { try batch(from: $0).items.map(\.id) }
        #expect(first == retry)
    }
    @Test func lockIsCheckedBeforeEveryBatch() throws {
        let r = FakeRunner()
        r.lockByCall = { $0 == 1 ? "passcodeRequired: false" : "passcodeRequired: true" }
        do { _ = try make(r).run(requestJSON: json(300)); Issue.record("expected throw") }
        catch let f as AddFailure { #expect(f.cause == .phoneLocked); #expect(f.sent == 1); #expect(f.total >= 2) }
        #expect(r.launches.count == 1)
    }
}
