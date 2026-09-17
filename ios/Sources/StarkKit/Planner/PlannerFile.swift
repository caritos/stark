// ios/Sources/StarkKit/Planner/PlannerFile.swift
import Foundation

public final class PlannerFile {
    private let directory: URL
    private let pendingDirectory: URL
    private let fileManager: FileManager

    public init(directory: URL, pendingDirectory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.pendingDirectory = pendingDirectory
        self.fileManager = fileManager
    }

    public func loadRecurring() -> ICSParseResult {
        load(fileName: "recurring.ics")
    }

    public func loadMonth(_ month: YearMonth) -> ICSParseResult {
        load(fileName: month.fileName)
    }

    private func load(fileName: String) -> ICSParseResult {
        let url = directory.appendingPathComponent(fileName)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ICSParseResult(events: [], reminders: [], warnings: [])
        }
        return ICSParser.parse(content)
    }

    public func saveRecurring(events: [Event], reminders: [Reminder]) throws {
        try save(fileName: "recurring.ics", events: events, reminders: reminders)
    }

    public func saveMonth(_ month: YearMonth, events: [Event], reminders: [Reminder]) throws {
        try save(fileName: month.fileName, events: events, reminders: reminders)
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
