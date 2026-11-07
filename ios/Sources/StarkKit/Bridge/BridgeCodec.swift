import Foundation

/// Wire format of the Claude Code bridge: sorted-key JSON, zlib-compressed, base64url in a `stark://add` URL.
public enum BridgeCodec {
    /// Longest base64url string allowed for one batch's compressed payload. The spike showed 65,536-character
    /// URLs work; 65,536 x 0.75 = 49,152, capped at 32,768.
    public static let maxEncodedBytes = 32_768
    /// Largest decompressed JSON `decode` will accept.
    public static let maxDecodedBytes = 1_048_576

    public static func encode(_ batch: BridgeBatch) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(batch)
        return try (json as NSData).compressed(using: .zlib) as Data
    }

    public static func decode(_ payload: Data) throws -> BridgeBatch {
        guard !payload.isEmpty else { throw BridgeError.malformed }
        guard let inflated = try? (payload as NSData).decompressed(using: .zlib) as Data,
              !inflated.isEmpty, inflated.count <= maxDecodedBytes,
              let batch = try? JSONDecoder().decode(BridgeBatch.self, from: inflated)
        else { throw BridgeError.malformed }
        return batch
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func data(fromBase64URL text: String) -> Data? {
        guard !text.isEmpty, text.utf8.allSatisfy({ isURLSafeBase64($0) }) else { return nil }
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        switch s.count % 4 {
        case 1: return nil
        case 2: s += "=="
        case 3: s += "="
        default: break
        }
        return Data(base64Encoded: s)
    }

    private static func isURLSafeBase64(_ c: UInt8) -> Bool {
        (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || c == 0x2d || c == 0x5f
    }

    public static func url(payload: Data, signature: Data) -> URL {
        var comps = URLComponents()
        comps.scheme = "stark"
        comps.host = "add"
        comps.queryItems = [
            URLQueryItem(name: "batch", value: base64URL(payload)),
            URLQueryItem(name: "sig", value: base64URL(signature)),
        ]
        return comps.url!
    }

    public static func parse(_ url: URL) -> (payload: Data, signature: Data)? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.scheme?.lowercased() == "stark", comps.host?.lowercased() == "add" else { return nil }
        let items = comps.queryItems ?? []
        let batches = items.filter { $0.name == "batch" }
        let sigs = items.filter { $0.name == "sig" }
        guard batches.count == 1, sigs.count == 1,
              let b = batches[0].value, let s = sigs[0].value,
              let payload = data(fromBase64URL: b), let signature = data(fromBase64URL: s) else { return nil }
        return (payload, signature)
    }

    /// Greedy split: each batch takes the most items (in order) that fit the item cap and `maxEncodedBytes`.
    public static func split(
        items: [BridgeItem], label: String?, issuedAt: TimeInterval, newBatchID: () -> String
    ) throws -> [BridgeBatch] {
        var batches: [BridgeBatch] = []
        var index = 0
        while index < items.count {
            let remaining = items.count - index
            let batchID = newBatchID()
            func make(_ n: Int) -> BridgeBatch {
                BridgeBatch(batch: batchID, issuedAt: issuedAt, label: label, items: Array(items[index..<index + n]))
            }
            func fits(_ n: Int) throws -> Bool {
                try base64URL(encode(make(n))).count <= maxEncodedBytes
            }
            guard try fits(1) else { throw BridgeError.itemTooLarge(id: items[index].id) }
            // Binary search the largest prefix that fits (size grows with item count).
            var lo = 1, hi = min(remaining, BridgeBatch.maxItems)
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if try fits(mid) { lo = mid } else { hi = mid - 1 }
            }
            batches.append(make(lo))
            index += lo
        }
        return batches
    }
}
