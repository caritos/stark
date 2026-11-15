import Foundation

public enum CLIUsage {
    public static let text = """
    usage: stark-claude pair            (secret from stdin, or a hidden prompt)
           stark-claude add <file|->    (JSON: {"label": "...", "items": [...]})
           stark-claude today [--date yyyy-MM-dd]   (unavailable until the Mac tool: Stark keeps items in Apple Calendar and Reminders)
    times are read in the phone's time zone (this Mac's zone is only used for a pre-check).
    """

    public static func isHelp(_ args: [String]) -> Bool {
        args.count == 1 && ["--help", "-h", "help"].contains(args[0])
    }
}
