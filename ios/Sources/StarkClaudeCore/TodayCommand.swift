import Foundation
import StarkKit

/// Best-effort read of one day's agenda: pulls the app's `/Documents` to a private temp folder,
/// reads it with the app's own file layer and agenda functions, prints `DayExport.text`, and
/// deletes everything it pulled. It only ever reads the pulled copy.
public struct TodayCommand {
    static let bundleID = "com.caritos.todo-txt"
    let runner: ProcessRunning
    let device: DeviceResolver
    let makeTempDirectory: () throws -> URL
    let now: () -> Date

    public init(runner: ProcessRunning, device: DeviceResolver,
                makeTempDirectory: @escaping () throws -> URL, now: @escaping () -> Date) {
        self.runner = runner; self.device = device
        self.makeTempDirectory = makeTempDirectory; self.now = now
    }

    /// Parses `yyyy-MM-dd` in this Mac's calendar and time zone.
    public static func parseDay(_ text: String, calendar: Calendar = Calendar(identifier: .gregorian)) throws -> Date {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: y, month: m, day: d)),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: y, month: m, day: d)
        else { throw CLIError.badRequest("--date must be a real date like 2026-11-07 (got \"\(text.prefix(40))\")") }
        return calendar.startOfDay(for: date)
    }

    public func run(day: Date?) throws -> String {
        let calendar = Calendar(identifier: .gregorian)
        let today = now()
        let target = calendar.startOfDay(for: day ?? today)

        let deviceID = try device.resolve()
        try PhoneLock.requireUnlocked(runner: runner, deviceID: deviceID)

        // Both folders hold or may hold the user's private data: owner-only, always removed.
        var made: [URL] = []
        defer { for url in made { try? FileManager.default.removeItem(at: url) } }
        func privateDirectory() throws -> URL {
            let url = try makeTempDirectory()
            made.append(url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        }
        let pulled = try privateDirectory()
        let pending = try privateDirectory()

        let r = try runner.run("xcrun", ["devicectl", "device", "copy", "from", "--device", deviceID,
                                         "--domain-type", "appDataContainer", "--domain-identifier", Self.bundleID,
                                         "--source", "/Documents", "--destination", pulled.path])
        guard r.status == 0 else {
            let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if err.lowercased().contains("locked") { throw CLIError.phoneLocked }
            throw CLIError.pullRefused("couldn't copy the app's data from the phone: \(String(err.prefix(300)))")
        }
        // devicectl may place the files in a Documents subfolder of the destination.
        var root = pulled
        var isDir: ObjCBool = false
        let sub = pulled.appendingPathComponent("Documents")
        if FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue { root = sub }

        let file = PlannerFile(directory: root, pendingDirectory: pending)
        let hasRecurring = FileManager.default.fileExists(atPath: root.appendingPathComponent("recurring.ics").path)
        guard hasRecurring || !file.availableMonths().isEmpty else {
            throw CLIError.pullRefused("no Stark data found on the phone (wrong app, or nothing saved yet?)")
        }
        var events: [Event] = [], reminders: [Reminder] = [], plans: [PlanBlock] = []
        do {
            let recurring = try file.loadRecurring()
            events += recurring.events; reminders += recurring.reminders

            // The months the app's store would load (lookback from the real today through the
            // day asked for), plus the month of every plan's task.
            let lo = min(AgendaWindow.loadRange(around: today, calendar: calendar).lowerBound,
                         AgendaWindow.loadRange(around: target, calendar: calendar).lowerBound)
            let hi = max(AgendaWindow.loadRange(around: today, calendar: calendar).upperBound,
                         AgendaWindow.loadRange(around: target, calendar: calendar).upperBound)
            var loaded = Set<YearMonth>()
            var queue: [YearMonth] = []
            var m = YearMonth(date: lo)
            while m <= YearMonth(date: hi) { queue.append(m); m = YearMonth(year: m.year, month0: m.month0 + 1) }
            while !queue.isEmpty {
                let month = queue.removeFirst()
                guard loaded.insert(month).inserted else { continue }
                let result = try file.loadMonth(month)
                events += result.events; reminders += result.reminders; plans += result.plans
                queue += result.plans.map { YearMonth(date: $0.occurrence) }
            }
        } catch let e as PlannerFileReadError {
            throw CLIError.pullRefused("the pulled file \(e.fileName) could not be read (not valid text?); nothing was shown")
        }

        let dayRange = calendar.startOfDay(for: target)...(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: target))!.addingTimeInterval(-1))
        let items = buildAgendaItems(events: events, reminders: reminders, in: dayRange, today: today)
        let planned = applyPlans(items, plans: plans, today: today, reminders: reminders, calendar: calendar)
        let days = groupAgendaByDay(planned, in: dayRange, calendar: calendar)
        return DayExport.text(day: target, items: days.first?.items ?? [], calendar: calendar)
    }
}
