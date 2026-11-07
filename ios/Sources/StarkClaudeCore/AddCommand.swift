import Foundation
import StarkKit
import CryptoKit

public struct AddRequest: Decodable {
    public var label: String?
    public var items: [BridgeItem]
}

public struct AddReport: Equatable {
    public var itemIDs: [String]
    public var batchesSent: Int
    public var batchesTotal: Int
}

public struct AddCommand {
    static let bundleID = "com.caritos.todo-txt"
    let runner: ProcessRunning
    let secrets: SecretStore
    let device: DeviceResolver
    let now: () -> Date
    let newID: () -> String
    let terminateExisting: Bool

    public init(runner: ProcessRunning, secrets: SecretStore, device: DeviceResolver, now: @escaping () -> Date,
                newID: @escaping () -> String, terminateExisting: Bool) {
        self.runner = runner; self.secrets = secrets; self.device = device
        self.now = now; self.newID = newID; self.terminateExisting = terminateExisting
    }

    /// Parses, fills ids, validates and signs everything without running any process.
    public func signedURLs(requestJSON: Data) throws -> (ids: [String], urls: [URL]) {
        guard let secret = try secrets.read() else { throw CLIError.notPaired }

        // Fill missing item ids before decoding (ids are optional in the request file).
        guard var root = (try? JSONSerialization.jsonObject(with: requestJSON)) as? [String: Any],
              var rawItems = root["items"] as? [[String: Any]]
        else { throw CLIError.badRequest("expected a JSON object with an \"items\" array") }
        var seen: [String: Int] = [:]
        for i in rawItems.indices {
            let title = (rawItems[i]["title"] as? String) ?? ""
            switch rawItems[i]["id"] {
            case nil, is NSNull: break
            case let id as String where !id.isEmpty: continue
            case let id as String where id.isEmpty: break
            default: throw CLIError.badRequest("item \(i + 1) (\"\(title)\"): id must be a string")
            }
            // Deterministic id: the same item text always gets the same id, so re-running a file is
            // recognised by the phone as "Already added". Identical items in one file get -k.
            var body = rawItems[i]
            body.removeValue(forKey: "id")
            let canonical = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
            let hex = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined().prefix(24)
            let k = seen[String(hex), default: 0]
            seen[String(hex)] = k + 1
            rawItems[i]["id"] = "bridge-\(hex)-\(k)"
        }
        root["items"] = rawItems
        let request: AddRequest
        do {
            request = try JSONDecoder().decode(AddRequest.self, from: JSONSerialization.data(withJSONObject: root))
        } catch {
            throw CLIError.badRequest("could not read the items: \(Self.describe(error))")
        }
        guard !request.items.isEmpty else { throw CLIError.badRequest("no items") }

        let batches: [BridgeBatch]
        do {
            var n = 0
            batches = try BridgeCodec.split(items: request.items, label: request.label,
                                            issuedAt: now().timeIntervalSince1970,
                                            newBatchID: { n += 1; return "\(newID())-\(n)" })
            for b in batches { _ = try b.models() }
        } catch {
            if case BridgeError.nonexistentLocalTime = error {
                throw CLIError.badRequest("\(error) The phone's time zone may differ from this Mac's (\(TimeZone.current.identifier)), which was used only for this pre-check.")
            }
            throw CLIError.badRequest("\(error)")
        }
        let urls = try batches.map { batch -> URL in
            let payload = try BridgeCodec.encode(batch)
            return BridgeCodec.url(payload: payload, signature: BridgeAuth.sign(payload, secret: secret))
        }
        return (request.items.map(\.id), urls)
    }

    public func run(requestJSON: Data) throws -> AddReport {
        let (ids, urls) = try signedURLs(requestJSON: requestJSON)
        let deviceID = try device.resolve()
        var sent = 0
        func fail(_ cause: CLIError) -> AddFailure {
            AddFailure(cause: cause, sent: sent, total: urls.count, itemIDs: ids)
        }
        for url in urls {
            // Re-checked before every batch: the phone can lock mid-send.
            do { try PhoneLock.requireUnlocked(runner: runner, deviceID: deviceID) } catch let e as CLIError { throw fail(e) }
            var args = ["devicectl", "device", "process", "launch", "--device", deviceID,
                        "--payload-url", url.absoluteString]
            if terminateExisting { args.append("--terminate-existing") }
            args.append(Self.bundleID)
            let r: ProcessResult
            do { r = try runner.run("xcrun", args) }
            catch let e as CLIError { throw fail(e) }
            catch { throw fail(.launchFailed("\(error)")) }
            if r.status != 0 {
                throw fail(r.stderr.lowercased().contains("locked")
                    ? .phoneLocked
                    : .launchFailed(String(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))))
            }
            sent += 1
        }
        return AddReport(itemIDs: ids, batchesSent: sent, batchesTotal: urls.count)
    }

    private static func describe(_ error: Error) -> String {
        if let d = error as? DecodingError {
            switch d {
            case .keyNotFound(let k, _): return "missing \"\(k.stringValue)\""
            case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
                return "bad value at \(c.codingPath.map(\.stringValue).joined(separator: "."))"
            @unknown default: return "invalid JSON"
            }
        }
        return "invalid JSON"
    }
}
