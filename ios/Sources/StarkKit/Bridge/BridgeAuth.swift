import Foundation
import CryptoKit
import Security

public protocol SecretStore: Sendable {
    func read() throws -> Data?
    func write(_ secret: Data) throws
    func delete() throws
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?
    public init(initial: Data? = nil) { value = initial }
    public func read() throws -> Data? { lock.lock(); defer { lock.unlock() }; return value }
    public func write(_ secret: Data) throws { lock.lock(); value = secret; lock.unlock() }
    public func delete() throws { lock.lock(); value = nil; lock.unlock() }
}

/// Carries only the OSStatus, never the secret.
public struct KeychainError: Error, Equatable, CustomStringConvertible {
    public let status: OSStatus
    public init(status: OSStatus) { self.status = status }
    public var description: String { "Keychain error (OSStatus \(status))" }
}

/// Generic-password Keychain item. Used by the iOS app and the Mac CLI.
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() throws -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError(status: status == errSecSuccess ? errSecInternalError : status) }
        return data
    }

    public func write(_ secret: Data) throws {
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: secret] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var add = query
        add[kSecValueData as String] = secret
        #if os(iOS)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public enum BridgeAuth {
    static let secretLength = 32

    public static func newSecret() -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<secretLength).map { _ in UInt8.random(in: .min ... .max, using: &g) })
    }

    public static func sign(_ payload: Data, secret: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: payload, using: SymmetricKey(data: secret)))
    }

    public static func verify(payload: Data, signature: Data, secret: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: payload, using: SymmetricKey(data: secret))
    }

    public static func displayString(for secret: Data) -> String {
        BridgeCodec.base64URL(secret)
    }

    public static func secret(fromDisplay text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = BridgeCodec.data(fromBase64URL: trimmed), data.count == secretLength else { return nil }
        return data
    }
}

public enum BridgePairing {
    public static func ensureSecret(in store: SecretStore) throws -> Data {
        if let existing = try store.read() { return existing }
        let secret = BridgeAuth.newSecret()
        try store.write(secret)
        return secret
    }

    public static func reset(in store: SecretStore) throws -> Data {
        let secret = BridgeAuth.newSecret()
        try store.write(secret)
        return secret
    }
}
