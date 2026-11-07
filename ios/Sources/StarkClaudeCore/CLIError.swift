import Foundation

public enum CLIError: Error, Equatable, CustomStringConvertible {
    case notPaired, noDevice, ambiguousDevice([String]), phoneLocked
    case launchFailed(String), badRequest(String), pullRefused(String)

    public var description: String {
        switch self {
        case .notPaired: return "Not paired. Run `stark-claude pair` and paste the secret from Stark > Settings > Claude Code."
        case .noDevice: return "No available paired iPhone found. Connect and unlock it, or set STARK_DEVICE to its name, identifier or UDID."
        case .ambiguousDevice(let names): return "More than one iPhone is available (\(names.joined(separator: ", "))). Set STARK_DEVICE to pick one."
        case .phoneLocked: return "The phone is locked. Unlock it and run the command again (a locked phone silently drops the request)."
        case .launchFailed(let m): return "Could not send to the phone: \(m)"
        case .badRequest(let m): return "Bad request: \(m)"
        case .pullRefused(let m): return "Refused: \(m)"
        }
    }
}

/// A send that failed part way: `sent` of `total` batches had been launched before `cause`.
public struct AddFailure: Error, CustomStringConvertible {
    public var cause: CLIError
    public var sent: Int
    public var total: Int
    public var description: String { "\(cause.description) (sent \(sent) of \(total) batches)" }
}
