import Foundation
import StarkKit

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
        for i in rawItems.indices where (rawItems[i]["id"] as? String).map({ $0.isEmpty }) ?? true {
            rawItems[i]["id"] = newID()
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
        try requireUnlocked(deviceID)
        var sent = 0
        for url in urls {
            var args = ["devicectl", "device", "process", "launch", "--device", deviceID,
                        "--payload-url", url.absoluteString]
            if terminateExisting { args.append("--terminate-existing") }
            args.append(Self.bundleID)
            do {
                let r = try runner.run("xcrun", args)
                if r.status != 0 {
                    let err = r.stderr.lowercased().contains("locked")
                        ? CLIError.phoneLocked : CLIError.launchFailed(String(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)))
                    throw AddFailure(cause: err, sent: sent, total: urls.count)
                }
            } catch let f as AddFailure {
                throw f
            } catch {
                throw AddFailure(cause: .launchFailed("\(error)"), sent: sent, total: urls.count)
            }
            sent += 1
        }
        return AddReport(itemIDs: ids, batchesSent: sent, batchesTotal: urls.count)
    }

    /// devicectl reports success but silently drops the URL when the phone is locked, so check first.
    private func requireUnlocked(_ deviceID: String) throws {
        let prefix = "couldn't check whether the phone is unlocked"
        let r: ProcessResult
        do { r = try runner.run("xcrun", ["devicectl", "device", "info", "lockState", "--device", deviceID]) }
        catch { throw CLIError.launchFailed("\(prefix): \(error)") }
        guard r.status == 0 else {
            throw CLIError.launchFailed("\(prefix): \(String(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))")
        }
        if r.stdout.contains("passcodeRequired: true") { throw CLIError.phoneLocked }
        guard r.stdout.contains("passcodeRequired: false") else {
            throw CLIError.launchFailed("\(prefix): unrecognised devicectl output")
        }
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
