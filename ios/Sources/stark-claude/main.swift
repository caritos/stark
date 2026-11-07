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
// STARK_CLAUDE_KEYCHAIN_SERVICE exists only so experiments can avoid the real pairing item.
let store = KeychainSecretStore(service: env["STARK_CLAUDE_KEYCHAIN_SERVICE"] ?? "com.caritos.stark-claude", account: "pairing")

let usage = """
usage: stark-claude pair            (secret from stdin, or a hidden prompt)
       stark-claude add <file|->    (JSON: {"label": "...", "items": [...]})
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
            print("Sent \(report.batchesSent) of \(report.batchesTotal) batches (the phone does not confirm; check Stark for the 'Added N items' banner).")
        }
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
