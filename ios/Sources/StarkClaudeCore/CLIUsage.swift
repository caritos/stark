import Foundation

public enum CLIUsage {
    public static let text = """
    usage: stark-claude pair            (secret from stdin, or a hidden prompt)
           stark-claude add <file|->    (JSON: {"label": "...", "items": [...]})
           stark-claude today [--date yyyy-MM-dd]   (best effort: pulls the app's data from an unlocked phone, prints that day's agenda)
    times are read in the phone's time zone (this Mac's zone is only used for a pre-check).
    "today" and --date use this Mac's calendar and time zone, which may differ from the phone's.
    --date for a future day lists that day's occurrences (the app's agenda shows only a recurring reminder's next one).
    """

    public static func isHelp(_ args: [String]) -> Bool {
        args.count == 1 && ["--help", "-h", "help"].contains(args[0])
    }
}
