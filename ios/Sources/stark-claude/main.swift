import Foundation
import StarkKit
import StarkClaudeCore

#if os(macOS)
func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())
let env = ProcessInfo.processInfo.environment
let store = KeychainSecretStore(service: "com.caritos.stark-claude", account: "pairing")

let usage = """
usage: stark-claude pair            (secret from stdin, or a hidden prompt)
       stark-claude add <file|->    (JSON: {"label": "...", "items": [...]})
       stark-claude today [--date yyyy-MM-dd]   (best effort: pulls the app's data from an unlocked phone, prints that day's agenda)
times are read in the phone's time zone (this Mac's zone is only used for a pre-check).
"today" and --date use this Mac's calendar and time zone, which may differ from the phone's.
--date for a future day lists that day's occurrences (the app's agenda shows only a recurring reminder's next one).
"""

do {
    switch args.first {
    case "pair":
        let text: String
        if isatty(STDIN_FILENO) != 0 {
            guard let p = getpass("Pairing secret (from Stark > Settings > Claude Code): ") else { fail("no input") }
            text = String(cString: p)
        } else {
            text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
        try PairCommand(secrets: store).run(secretText: text)
        print("Paired.")
    case "add":
        let rest = Array(args.dropFirst())
        let printOnly = rest.contains("--print-url")
        let paths = rest.filter { $0 != "--print-url" }
        guard paths.count == 1 else { fail(usage, code: 2) }
        let data: Data
        if paths[0] == "-" { data = FileHandle.standardInput.readDataToEndOfFile() }
        else if let d = FileManager.default.contents(atPath: paths[0]) { data = d }
        else { fail("cannot read \(paths[0])") }
        let runner = FoundationProcessRunner()
        let command = AddCommand(runner: runner, secrets: store,
                                 device: DeviceResolver(runner: runner, environment: env),
                                 now: { Date() }, newID: { UUID().uuidString.lowercased() },
                                 terminateExisting: false)
        if printOnly {
            for url in try command.signedURLs(requestJSON: data).urls { print(url.absoluteString) }
        } else {
            let report = try command.run(requestJSON: data)
            print("Items: \(report.itemIDs.joined(separator: ", "))")
            print("Sent \(report.batchesSent) of \(report.batchesTotal) batches (the phone does not confirm and may lock mid-send; check Stark for the 'Added N items' banner).")
            print("Times are read in the phone's time zone; this Mac's zone (\(TimeZone.current.identifier)) was used only for the pre-check.")
        }
    case "today":
        var rest = Array(args.dropFirst())
        var day: Date?
        if let i = rest.firstIndex(of: "--date") {
            guard i + 1 < rest.count else { fail(usage, code: 2) }
            day = try TodayCommand.parseDay(rest[i + 1])
            rest.removeSubrange(i...(i + 1))
        }
        guard rest.isEmpty else { fail(usage, code: 2) }
        let runner = FoundationProcessRunner(timeout: 120)
        let command = TodayCommand(runner: runner, device: DeviceResolver(runner: runner, environment: env),
                                   makeTempDirectory: {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stark-claude-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            return url
        }, now: { Date() })
        print(try command.run(day: day))
    default:
        fail(usage, code: 2)
    }
} catch let f as AddFailure {
    fail(f.description)
} catch let e as CLIError {
    fail(e.description)
} catch {
    fail("\(error)")
}
#endif
