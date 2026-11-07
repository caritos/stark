import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status; self.stdout = stdout; self.stderr = stderr
    }
}

public protocol ProcessRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult
}

public struct FoundationProcessRunner: ProcessRunning {
    private let timeout: TimeInterval
    public init(timeout: TimeInterval = 60) { self.timeout = timeout }

    public func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
        #if os(macOS)
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:" + (env["PATH"] ?? "/bin:/usr/sbin:/sbin")
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        final class Flag: @unchecked Sendable {
            private let lock = NSLock(); private var v = false
            func set() { lock.lock(); v = true; lock.unlock() }
            var value: Bool { lock.lock(); defer { lock.unlock() }; return v }
        }
        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            timedOut.set()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Drain both pipes concurrently so neither can fill and block the child.
        let group = DispatchGroup()
        final class Box: @unchecked Sendable { var data = Data() }
        let outBox = Box(), errBox = Box()
        group.enter()
        DispatchQueue.global().async { outBox.data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errBox.data = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()
        if timedOut.value { throw CLIError.launchFailed("timed out talking to the phone (\(Int(timeout)) s)") }
        return ProcessResult(status: process.terminationStatus,
                             stdout: String(decoding: outBox.data, as: UTF8.self),
                             stderr: String(decoding: errBox.data, as: UTF8.self))
        #else
        throw CLIError.launchFailed("running processes is only supported on macOS")
        #endif
    }
}
