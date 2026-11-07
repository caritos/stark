import Foundation
import Testing
import StarkKit
@testable import StarkClaudeCore

/// Wraps FakeRunner and "pulls" by writing fixture files into the --destination folder.
final class PullRunner: ProcessRunning, @unchecked Sendable {
    let base = FakeRunner()
    var files: [String: Data] = [:]
    var subfolder: String?
    var pullResult: ProcessResult?
    var pullThrows: Error?
    private let lock = NSLock()
    private var _destinations: [String] = []
    var destinations: [String] { lock.lock(); defer { lock.unlock() }; return _destinations }
    var pulls: [FakeRunner.Call] { base.calls.filter { $0.arguments.contains("copy") } }

    func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
        guard arguments.contains("copy") else { return try base.run(executable, arguments) }
        _ = try base.run(executable, arguments)
        let dest = arguments[arguments.firstIndex(of: "--destination")! + 1]
        lock.lock(); _destinations.append(dest); lock.unlock()
        if let e = pullThrows { throw e }
        if let r = pullResult { return r }
        var dir = URL(fileURLWithPath: dest)
        if let s = subfolder { dir.appendPathComponent(s); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        for (name, data) in files { try data.write(to: dir.appendingPathComponent(name)) }
        return ProcessResult(status: 0, stdout: "File received from Device", stderr: "")
    }
}

@Suite struct TodayCommandTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    var now: Date { at(2026, 11, 7, 12, 0) }

    final class Dirs: @unchecked Sendable { var made: [URL] = [] }

    func make(_ r: PullRunner, dirs: Dirs, env: [String: String] = [:]) -> TodayCommand {
        TodayCommand(runner: r, device: DeviceResolver(runner: r, environment: env), makeTempDirectory: {
            let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("today-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false)
            dirs.made.append(u); return u
        }, now: { now })
    }
    func ics(events: [Event] = [], reminders: [Reminder] = []) -> Data {
        Data(ICSSerializer.serialize(events: events, reminders: reminders).utf8)
    }
    func gone(_ dirs: Dirs) { #expect(!dirs.made.isEmpty); for u in dirs.made { #expect(!FileManager.default.fileExists(atPath: u.path)) } }

    @Test func agendaForTodayInAgendaOrder() throws {
        let r = PullRunner(); let dirs = Dirs()
        r.files["2026-11.ics"] = ics(
            events: [Event(title: "Standup", start: at(2026, 11, 7, 9, 30)),
                     Event(title: "Holiday", start: at(2026, 11, 7), isAllDay: true)],
            reminders: [Reminder(title: "Overdue thing", dueDate: at(2026, 11, 4, 8, 0)),
                        Reminder(title: "Done thing", dueDate: at(2026, 11, 7, 10, 0), isCompleted: true, completedDate: at(2026, 11, 7, 10, 0)),
                        Reminder(title: "Other day", dueDate: at(2026, 11, 8, 10, 0))])
        r.files["recurring.ics"] = ics(reminders: [
            Reminder(title: "Daily pill", dueDate: at(2026, 11, 1, 7, 0), recurrence: RecurrenceRule(frequency: .daily))])
        let out = try make(r, dirs: dirs).run(day: nil)
        let lines = out.split(separator: "\n").map(String.init)
        #expect(lines.first == "2026-11-07")
        #expect(out.contains("- [ ] Overdue thing (due 2026-11-04)"))
        #expect(out.contains("- [x] Done thing"))
        #expect(out.contains("- 09:30 Standup"))
        #expect(out.contains("- Holiday"))
        #expect(out.contains("Daily pill"))
        #expect(!out.contains("Other day"))
        // The recurring daily reminder carries its first open miss (Nov 1) as one overdue row.
        #expect(out.contains("- [ ] Daily pill (due 2026-11-01)"))
        #expect(out.components(separatedBy: "Daily pill").count == 2)
        #expect(lines == ["2026-11-07", "- [ ] Daily pill (due 2026-11-01)", "- [ ] Overdue thing (due 2026-11-04)",
                          "- Holiday", "- 09:30 Standup", "- [x] Done thing"])
        gone(dirs)
    }

    @Test func otherDayShowsThatDay() throws {
        let r = PullRunner(); let dirs = Dirs()
        r.files["2026-11.ics"] = ics(reminders: [Reminder(title: "Tomorrow task", dueDate: at(2026, 11, 8, 10, 0))])
        let out = try make(r, dirs: dirs).run(day: at(2026, 11, 8))
        #expect(out == "2026-11-08\n- [ ] Tomorrow task")
        gone(dirs)
    }

    @Test func emptyDay() throws {
        let r = PullRunner(); let dirs = Dirs()
        r.files["2026-11.ics"] = ics(reminders: [Reminder(title: "Not today", dueDate: at(2026, 11, 20, 10, 0))])
        #expect(try make(r, dirs: dirs).run(day: nil) == "2026-11-07\n- (none)")
        gone(dirs)
    }

    @Test func emptyPullIsRefused() {
        for sub in [nil, "Documents"] as [String?] {
            let r = PullRunner(); let dirs = Dirs()
            r.subfolder = sub
            r.files["notes.txt"] = Data("x".utf8)  // not a planner file
            do { _ = try make(r, dirs: dirs).run(day: nil); Issue.record("expected throw") }
            catch let e as CLIError {
                #expect(e == .pullRefused("no Stark data found on the phone (wrong app, or nothing saved yet?)"))
            } catch { Issue.record("wrong error \(error)") }
            gone(dirs)
        }
    }

    @Test func plannedFarTaskFromAnotherMonthShows() throws {
        let r = PullRunner(); let dirs = Dirs()
        let far = Reminder(id: "far-1", title: "Far task", dueDate: at(2027, 3, 10, 10, 0))
        r.files["2027-03.ics"] = ics(reminders: [far])
        let plan = PlanBlock(reminderID: "far-1", occurrence: at(2027, 3, 10, 10, 0), start: at(2026, 11, 8, 9, 0), minutes: 30)
        r.files["2026-11.ics"] = Data(ICSSerializer.serialize(events: [], reminders: [], plans: [plan]).utf8)
        #expect(try make(r, dirs: dirs).run(day: at(2026, 11, 8)) == "2026-11-08\n- [ ] Far task")
        gone(dirs)
    }

    @Test func filesInDocumentsSubfolderAreFound() throws {
        let r = PullRunner(); let dirs = Dirs()
        r.subfolder = "Documents"
        r.files["2026-11.ics"] = ics(events: [Event(title: "Sub", start: at(2026, 11, 7, 13, 0))])
        #expect(try make(r, dirs: dirs).run(day: nil) == "2026-11-07\n- 13:00 Sub")
        gone(dirs)
    }

    @Test func pullArguments() throws {
        let r = PullRunner(); let dirs = Dirs()
        r.files["recurring.ics"] = ics()
        _ = try make(r, dirs: dirs).run(day: nil)
        let c = try #require(r.pulls.first)
        #expect(c.arguments.starts(with: ["devicectl", "device", "copy", "from", "--device", "AAAA-1111",
                                          "--domain-type", "appDataContainer", "--domain-identifier", "com.caritos.todo-txt",
                                          "--source", "/Documents", "--destination"]))
        #expect(r.destinations.count == 1)
    }

    @Test func tempFoldersArePrivateAndDeletedWhenRunnerThrows() throws {
        let r = PullRunner(); let dirs = Dirs()
        r.pullThrows = CLIError.launchFailed("boom")
        #expect(throws: CLIError.launchFailed("boom")) { try make(r, dirs: dirs).run(day: nil) }
        #expect(dirs.made.count == 2)
        gone(dirs)
    }

    @Test func tempFoldersAreOwnerOnly() throws {
        final class Inspect: ProcessRunning, @unchecked Sendable {
            let inner: PullRunner; var mode: Int?
            init(_ i: PullRunner) { inner = i }
            func run(_ e: String, _ a: [String]) throws -> ProcessResult {
                if a.contains("copy") {
                    let d = a[a.firstIndex(of: "--destination")! + 1]
                    mode = (try FileManager.default.attributesOfItem(atPath: d)[.posixPermissions] as? NSNumber)?.intValue
                }
                return try inner.run(e, a)
            }
        }
        let inner = PullRunner(); inner.files["recurring.ics"] = ics()
        let ins = Inspect(inner); let dirs2 = Dirs()
        let cmd2 = TodayCommand(runner: ins, device: DeviceResolver(runner: ins, environment: [:]), makeTempDirectory: {
            let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("today-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false)
            dirs2.made.append(u); return u
        }, now: { now })
        _ = try cmd2.run(day: nil)
        #expect(ins.mode == 0o700)
        gone(dirs2)
    }

    @Test func refusedPullIsPullRefusedAndCleansUp() {
        let r = PullRunner(); let dirs = Dirs()
        r.pullResult = ProcessResult(status: 1, stdout: "", stderr: "ERROR: the app is not installed")
        do { _ = try make(r, dirs: dirs).run(day: nil); Issue.record("expected throw") }
        catch let e as CLIError {
            guard case .pullRefused(let m) = e else { Issue.record("wrong error \(e)"); return }
            #expect(m.contains("not installed"))
        } catch { Issue.record("wrong error \(error)") }
        gone(dirs)
    }

    @Test func lockedPhoneRefusesBeforePulling() {
        let r = PullRunner(); let dirs = Dirs()
        r.base.lockStdout = "• passcodeRequired: true\n"
        #expect(throws: CLIError.phoneLocked) { try make(r, dirs: dirs).run(day: nil) }
        #expect(r.pulls.isEmpty)
        #expect(dirs.made.isEmpty)
    }

    @Test func unparseableOrFailedLockCheckFailsClosed() {
        for setup in [{ (r: PullRunner) in r.base.lockStdout = "garbage" },
                      { (r: PullRunner) in r.base.lockResult = ProcessResult(status: 1, stdout: "", stderr: "nope") }] {
            let r = PullRunner(); let dirs = Dirs()
            setup(r)
            #expect(throws: (any Error).self) { try make(r, dirs: dirs).run(day: nil) }
            #expect(r.pulls.isEmpty)
        }
    }

    @Test func corruptMonthFileIsAnErrorNotEmpty() {
        let r = PullRunner(); let dirs = Dirs()
        r.files["2026-11.ics"] = Data([0xFF, 0xFE, 0x80, 0x81, 0xC0])
        do { _ = try make(r, dirs: dirs).run(day: nil); Issue.record("expected throw") }
        catch let e as CLIError {
            guard case .pullRefused(let m) = e else { Issue.record("wrong error \(e)"); return }
            #expect(m.contains("2026-11.ics"))
        } catch { Issue.record("wrong error \(error)") }
        gone(dirs)
    }

    @Test func invalidDatesAreBadRequest() throws {
        for bad in ["2026-13-01", "2026-02-30", "26-11-07", "2026/11/07", "", "yesterday", "2026-1-7"] {
            #expect(throws: (any Error).self) { try TodayCommand.parseDay(bad) }
            do { _ = try TodayCommand.parseDay(bad) } catch let e as CLIError {
                guard case .badRequest = e else { Issue.record("wrong error"); continue }
            }
        }
        #expect(try TodayCommand.parseDay("2026-11-08") == at(2026, 11, 8))
    }
}
