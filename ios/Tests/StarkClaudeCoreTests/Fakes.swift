import Foundation
@testable import StarkClaudeCore

final class FakeRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable { var executable: String; var arguments: [String] }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var devicesJSON: String = Fixtures.oneIPhone
    var lockStdout: String = "• passcodeRequired: false\n"
    var lockResult: ProcessResult?
    /// Overrides lockStdout per lockState call (1-based).
    var lockByCall: ((Int) -> String)?
    private var lockCalls = 0
    /// Called for each launch (1-based index); return nil for success.
    var launchFailure: (Int) -> ProcessResult? = { _ in nil }

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    var launches: [Call] { calls.filter { $0.arguments.contains("launch") } }

    func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
        lock.lock(); _calls.append(Call(executable: executable, arguments: arguments)); lock.unlock()
        if arguments.contains("devices") {
            let i = arguments.firstIndex(of: "--json-output")!
            try devicesJSON.write(toFile: arguments[i + 1], atomically: true, encoding: .utf8)
            return ProcessResult(status: 0, stdout: "", stderr: "")
        }
        if arguments.contains("lockState") {
            lock.lock(); lockCalls += 1; let n = lockCalls; lock.unlock()
            return lockResult ?? ProcessResult(status: 0, stdout: lockByCall?(n) ?? lockStdout, stderr: "")
        }
        if arguments.contains("launch") {
            let n = launches.count
            return launchFailure(n) ?? ProcessResult(status: 0, stdout: "Launched application", stderr: "")
        }
        return ProcessResult(status: 1, stdout: "", stderr: "unexpected")
    }
}

enum Fixtures {
    static func device(id: String, name: String, type: String, udid: String, pairing: String = "paired", tunnel: String = "disconnected") -> String {
        """
        {"connectionProperties":{"pairingState":"\(pairing)","tunnelState":"\(tunnel)"},
         "deviceProperties":{"name":"\(name)"},
         "hardwareProperties":{"deviceType":"\(type)","udid":"\(udid)","platform":"iOS"},
         "identifier":"\(id)"}
        """
    }
    static func list(_ devices: [String]) -> String {
        "{\"info\":{\"jsonVersion\":3},\"result\":{\"devices\":[\(devices.joined(separator: ","))]}}"
    }
    static let phone = device(id: "AAAA-1111", name: "Eladio’s iPhone", type: "iPhone", udid: "0000-UDID1")
    static let oneIPhone = list([
        phone,
        device(id: "W-1", name: "Eladio’s Apple Watch", type: "appleWatch", udid: "W-UDID", tunnel: "unavailable"),
        device(id: "P-1", name: "Old iPhone", type: "iPhone", udid: "OLD-UDID", tunnel: "unavailable"),
        device(id: "I-1", name: "Nina’s iPad", type: "iPad", udid: "IPAD-UDID"),
    ])
    static let twoIPhones = list([
        phone, device(id: "BBBB-2222", name: "Spare iPhone", type: "iPhone", udid: "0000-UDID2", tunnel: "connected"),
    ])
    static let none = list([device(id: "W-1", name: "Watch", type: "appleWatch", udid: "W", tunnel: "unavailable")])
}
