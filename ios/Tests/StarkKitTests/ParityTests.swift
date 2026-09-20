// ios/Tests/StarkKitTests/ParityTests.swift
//
// Acceptance test for the todo.txt migration. Skipped unless both env vars are set:
//   STARK_PARITY_DIR       an export directory written by `t export-ics`
//   STARK_PARITY_EXPECTED  the JSON written by console/scripts/parity-expected.ts
// It loads the export into a real PlannerStore and compares the native agenda with the rows the
// console's own occurrence logic expects. Read-only: the export directory is never written to.
import Testing
import Foundation
@testable import StarkKit

private struct Row: Codable, Hashable {
    let kind: String
    let date: String
    let time: String?
    let title: String
}

private struct Expected: Codable {
    let today: String
    let windowDays: Int
    let window: [Row]
    let overdueOneOffs: [Row]
}

private let env = ProcessInfo.processInfo.environment
private let parityEnabled = env["STARK_PARITY_DIR"] != nil && env["STARK_PARITY_EXPECTED"] != nil
private let cal = Calendar(identifier: .gregorian)

private func key(_ r: Row) -> String { "\(r.kind)|\(r.date)|\(r.time ?? "-")|\(r.title)" }

private func multiset(_ keys: [String]) -> [String: Int] {
    Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: +)
}

/// 'allday' for an all-day event, the real HH:mm (a timed 00:00 event included) for a timed event,
/// and nil for an untimed reminder (a reminder's date-only or 00:00 time). Matches the JSON's
/// `time: 'HH:MM' | 'allday' | null`.
private func timeString(_ item: AgendaItem) -> String? {
    let c = cal.dateComponents([.hour, .minute], from: item.occurrence)
    let hhmm = String(format: "%02d:%02d", c.hour!, c.minute!)
    switch item.kind {
    case .event(let event):
        return event.isAllDay ? "allday" : hhmm
    case .reminder:
        return hhmm == "00:00" ? nil : hhmm
    }
}

private func nativeKey(_ item: AgendaItem) -> String {
    let kind: String
    switch item.kind {
    case .event: kind = "event"
    case .reminder: kind = "reminder"
    }
    return "\(kind)|\(DateMath.isoDate(from: item.occurrence))|\(timeString(item) ?? "-")|\(item.title)"
}

/// Missing = expected by the console but absent natively; extra = shown natively but not expected.
private func diff(expected: [String: Int], got: [String: Int]) -> (missing: [String], extra: [String]) {
    var missing: [String] = []
    var extra: [String] = []
    for (k, n) in expected where (got[k] ?? 0) < n { missing.append("\(k)  (expected \(n), got \(got[k] ?? 0))") }
    for (k, n) in got where (expected[k] ?? 0) < n { extra.append("\(k)  (expected \(expected[k] ?? 0), got \(n))") }
    return (missing.sorted(), extra.sorted())
}

private func describe(_ lines: [String]) -> String {
    (lines.prefix(40) + (lines.count > 40 ? ["… and \(lines.count - 40) more"] : [])).joined(separator: "\n")
}

/// Always on (not gated by the parity suite's trait): a run with only one of the two variables set
/// is a misconfiguration and must not read as a silent skip.
@Suite("todo.txt migration parity configuration")
struct ParityConfigurationTests {
    @Test("STARK_PARITY_DIR and STARK_PARITY_EXPECTED are either both set or both unset")
    func environmentIsConsistent() {
        let hasDir = env["STARK_PARITY_DIR"] != nil
        let hasExpected = env["STARK_PARITY_EXPECTED"] != nil
        if hasDir && !hasExpected {
            Issue.record("STARK_PARITY_DIR is set but STARK_PARITY_EXPECTED is missing: the parity suite would be skipped")
        } else if hasExpected && !hasDir {
            Issue.record("STARK_PARITY_EXPECTED is set but STARK_PARITY_DIR is missing: the parity suite would be skipped")
        }
    }
}

@Suite("todo.txt migration parity", .enabled(if: parityEnabled))
struct ParityTests {
    private var dir: URL { URL(fileURLWithPath: env["STARK_PARITY_DIR"]!) }

    @Test("every exported file parses without warnings")
    func exportParsesCleanly() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".ics") }
        #expect(!names.isEmpty)
        var events = 0, reminders = 0
        for name in names {
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            let result = ICSParser.parse(text)
            #expect(result.warnings.isEmpty, "\(name): \(result.warnings)")
            events += result.events.count
            reminders += result.reminders.count
        }
        print("parity: parsed \(names.count) files, \(events) events, \(reminders) reminders")
    }

    @MainActor
    @Test("the native agenda matches the console's occurrences")
    func agendaMatchesTheConsole() throws {
        let expected = try JSONDecoder().decode(
            Expected.self, from: Data(contentsOf: URL(fileURLWithPath: env["STARK_PARITY_EXPECTED"]!)))
        let today = DateMath.date(from: expected.today)   // local noon of that day

        let pending = FileManager.default.temporaryDirectory.appendingPathComponent("parity-pending-\(UUID().uuidString)")
        let store = PlannerStore(file: PlannerFile(directory: dir, pendingDirectory: pending))
        let load = AgendaWindow.loadRange(around: today)
        store.start(windowStart: load.lowerBound, windowEnd: load.upperBound)
        #expect(store.error == nil, "\(store.error ?? "")")

        let start = cal.startOfDay(for: today)
        let after = cal.date(byAdding: .day, value: expected.windowDays + 1, to: start)!
        let items = buildAgendaItems(
            events: store.events, reminders: store.reminders,
            in: start...after.addingTimeInterval(-1), today: today)

        // (a) items dated today ... today + windowDays
        let window = diff(
            expected: multiset(expected.window.map(key)),
            got: multiset(items.filter { !$0.isCompleted && !$0.isOverdue }.map(nativeKey)))
        #expect(window.missing.isEmpty, "MISSING from the native agenda (\(window.missing.count)):\n\(describe(window.missing))")
        #expect(window.extra.isEmpty, "EXTRA in the native agenda (\(window.extra.count)):\n\(describe(window.extra))")

        // (b) one-off reminders overdue by 1...90 days
        let overdue = diff(
            expected: multiset(expected.overdueOneOffs.map(key)),
            got: multiset(items.filter { $0.isOverdue && !$0.isRecurring }.map(nativeKey)))
        #expect(overdue.missing.isEmpty, "MISSING overdue one-offs (\(overdue.missing.count)):\n\(describe(overdue.missing))")
        #expect(overdue.extra.isEmpty, "EXTRA overdue one-offs (\(overdue.extra.count)):\n\(describe(overdue.extra))")
    }
}
