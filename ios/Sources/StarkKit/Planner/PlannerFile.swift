// ios/Sources/StarkKit/Planner/PlannerFile.swift
import Foundation

/// Thrown by `PlannerFile.load` when a file genuinely exists but couldn't be read
/// (a real I/O error, permissions issue, or corrupt encoding) — as opposed to the file
/// simply not existing yet, which is a normal, expected state (nothing saved there yet)
/// and is NOT an error.
public struct PlannerFileReadError: Error, CustomStringConvertible {
    public let fileName: String
    public let underlying: Error

    public var description: String {
        "couldn't read \(fileName): \(underlying.localizedDescription)"
    }
}

public final class PlannerFile {
    private let directory: URL
    private let pendingDirectory: URL
    private let fileManager: FileManager

    public init(directory: URL, pendingDirectory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.pendingDirectory = pendingDirectory
        self.fileManager = fileManager
    }

    public func loadRecurring() throws -> ICSParseResult {
        try load(fileName: "recurring.ics")
    }

    public func loadMonth(_ month: YearMonth) throws -> ICSParseResult {
        try load(fileName: month.fileName)
    }

    /// Returns an empty result only when the file genuinely doesn't exist yet.
    /// If the file exists but can't be read (I/O error, corrupt encoding, etc.),
    /// throws `PlannerFileReadError` instead of silently returning empty — a caller
    /// must never treat a real read failure as "no items", since that can lead to
    /// the empty in-memory state being persisted back over the real (unreadable) file.
    private func load(fileName: String) throws -> ICSParseResult {
        let url = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            return ICSParseResult(events: [], reminders: [], warnings: [])
        }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return ICSParser.parse(content)
        } catch {
            throw PlannerFileReadError(fileName: fileName, underlying: error)
        }
    }

    public func saveRecurring(events: [Event], reminders: [Reminder]) throws {
        try save(fileName: "recurring.ics", events: events, reminders: reminders)
    }

    public func saveMonth(_ month: YearMonth, events: [Event], reminders: [Reminder]) throws {
        try save(fileName: month.fileName, events: events, reminders: reminders)
    }

    /// Every month file that exists in `directory`, discovered by filename pattern
    /// (`YYYY-MM.ics`) rather than assumed — the app has no other way to know which months
    /// have ever been saved, which Search needs in order to load everything rather than just
    /// the agenda's display window. Skips `recurring.ics` and anything that isn't a two-part
    /// `YYYY-MM` filename. Returns `[]` if `directory` doesn't exist yet or can't be
    /// enumerated (a normal state for a brand-new install, not an error).
    public func availableMonths() -> [YearMonth] {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url -> YearMonth? in
            let name = url.lastPathComponent
            guard name.hasSuffix(".ics"), name != "recurring.ics" else { return nil }
            let base = String(name.dropLast(4))
            let parts = base.split(separator: "-")
            guard parts.count == 2, let year = Int(parts[0]), let month1 = Int(parts[1]), (1...12).contains(month1) else {
                return nil
            }
            return YearMonth(year: year, month0: month1 - 1)
        }
    }

    /// Removes a month's file entirely, rather than leaving an empty `BEGIN:VCALENDAR…
    /// END:VCALENDAR` stub on disk once every event/reminder in it has been deleted (or moved
    /// elsewhere by `updateEvent`/`updateReminder`). A no-op if the file doesn't already exist —
    /// callers don't need to check first. Also clears any stale pending-write stub for the same
    /// month, so a previously-failed save can't resurrect the file on the next retry.
    public func deleteMonth(_ month: YearMonth) throws {
        let url = directory.appendingPathComponent(month.fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        clearPendingWrite(fileName: month.fileName)
    }

    private func save(fileName: String, events: [Event], reminders: [Reminder]) throws {
        let content = ICSSerializer.serialize(events: events, reminders: reminders)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            clearPendingWrite(fileName: fileName)
        } catch {
            try fileManager.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
            try content.write(to: pendingDirectory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            throw error
        }
    }

    private func clearPendingWrite(fileName: String) {
        try? fileManager.removeItem(at: pendingDirectory.appendingPathComponent(fileName))
    }

    public func retryPendingWrites() {
        guard let files = try? fileManager.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in files {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            if (try? content.write(to: destination, atomically: true, encoding: .utf8)) != nil {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    public var pendingWriteCount: Int {
        (try? fileManager.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil).count) ?? 0
    }
}
