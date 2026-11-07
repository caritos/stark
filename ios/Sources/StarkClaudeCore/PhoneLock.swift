import Foundation

enum PhoneLock {
    /// devicectl reports success but silently drops the URL when the phone is locked, so check first.
    static func requireUnlocked(runner: ProcessRunning, deviceID: String) throws {
        let prefix = "couldn't check whether the phone is unlocked"
        let r: ProcessResult
        do { r = try runner.run("xcrun", ["devicectl", "device", "info", "lockState", "--device", deviceID]) }
        catch CLIError.launchFailed(let m) { throw CLIError.launchFailed("\(prefix): \(m)") }
        catch { throw CLIError.launchFailed("\(prefix): \(error)") }
        guard r.status == 0 else {
            throw CLIError.launchFailed("\(prefix): \(String(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))")
        }
        if r.stdout.contains("passcodeRequired: true") { throw CLIError.phoneLocked }
        guard r.stdout.contains("passcodeRequired: false") else {
            throw CLIError.launchFailed("\(prefix): unrecognised devicectl output")
        }
    }
}
