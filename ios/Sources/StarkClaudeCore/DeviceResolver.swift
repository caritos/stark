import Foundation

public struct DeviceResolver {
    let runner: ProcessRunning
    let environment: [String: String]

    public init(runner: ProcessRunning, environment: [String: String]) {
        self.runner = runner
        self.environment = environment
    }

    private struct Listing: Decodable {
        struct Result: Decodable { var devices: [Device] }
        struct Device: Decodable {
            struct Conn: Decodable { var pairingState: String?; var tunnelState: String? }
            struct Props: Decodable { var name: String? }
            struct HW: Decodable { var deviceType: String?; var udid: String? }
            var identifier: String
            var connectionProperties: Conn?
            var deviceProperties: Props?
            var hardwareProperties: HW?
        }
        var result: Result
    }

    /// Returns the CoreDevice identifier to pass to `devicectl --device`.
    public func resolve() throws -> String {
        let file = NSTemporaryDirectory() + "stark-claude-devices-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: file) }
        let r = try runner.run("xcrun", ["devicectl", "list", "devices", "--json-output", file])
        guard r.status == 0 else { throw CLIError.launchFailed("couldn't list devices: \(String(r.stderr.prefix(300)))") }
        guard let data = FileManager.default.contents(atPath: file),
              let listing = try? JSONDecoder().decode(Listing.self, from: data)
        else { throw CLIError.launchFailed("couldn't read the device list from devicectl") }

        let phones = listing.result.devices.filter {
            $0.hardwareProperties?.deviceType == "iPhone"
                && $0.connectionProperties?.pairingState == "paired"
                && $0.connectionProperties?.tunnelState != "unavailable"
        }
        func name(_ d: Listing.Device) -> String { d.deviceProperties?.name ?? d.identifier }

        if let wanted = environment["STARK_DEVICE"], !wanted.isEmpty {
            let hits = phones.filter { name($0) == wanted || $0.identifier == wanted || $0.hardwareProperties?.udid == wanted }
            switch hits.count {
            case 0: throw CLIError.noDevice
            case 1: return hits[0].identifier
            default: throw CLIError.ambiguousDevice(hits.map(name))
            }
        }
        switch phones.count {
        case 0: throw CLIError.noDevice
        case 1: return phones[0].identifier
        default: throw CLIError.ambiguousDevice(phones.map(name))
        }
    }
}
