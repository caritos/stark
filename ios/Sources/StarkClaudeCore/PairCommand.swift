import Foundation
import StarkKit

public struct PairCommand {
    let secrets: SecretStore
    public init(secrets: SecretStore) { self.secrets = secrets }

    /// Stores the secret shown in Stark > Settings > Claude Code. Never echoes it, even in errors.
    public func run(secretText: String) throws {
        guard let secret = BridgeAuth.secret(fromDisplay: secretText) else {
            throw CLIError.badRequest("that is not a valid pairing secret (copy it again from Stark > Settings > Claude Code)")
        }
        try secrets.write(secret)
    }
}
