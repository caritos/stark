// ios/Sources/StarkKit/Planner/MonthLayout.swift
import Foundation

/// A multi-day or all-day event drawn as a bar across one week row of the month view.
public struct MonthBar: Equatable, Sendable {
    public let id: String
    public let title: String
    public let colorRGB: UInt32?
    public let isHoliday: Bool
    /// Columns 0...6, Sunday first like `MonthGrid`.
    public let startColumn: Int
    public let endColumn: Int
    public let lane: Int
    public let continuesBefore: Bool
    public let continuesAfter: Bool
}

public enum MonthLineKind: Equatable, Sendable {
    case timed(colorRGB: UInt32?)
    case reminder(isCompleted: Bool, isRecurring: Bool)
}

/// One text line inside a day cell (a timed event or a reminder).
public struct MonthLine: Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: MonthLineKind
}

/// One row of the month grid: its bars plus, per column, the lines shown and the hidden count.
public struct MonthWeek: Equatable, Sendable {
    public let bars: [MonthBar]
    /// Exactly 7 entries, one per column.
    public let lines: [[MonthLine]]
    /// Exactly 7 entries: how many bars and lines are hidden behind the "N more" label.
    public let overflow: [Int]
}

/// Lays the merged agenda rows of `month`'s grid out as week rows of bars and lines. Pure: no UI
/// types, no `Date()`. Rows outside the grid are ignored. See the stage 3b plan for the rules.
public func monthLayout(items: [AgendaItem], month: YearMonth, rowCapacity: Int,
                        calendar: Calendar = Calendar(identifier: .gregorian)) -> [MonthWeek] {
    let days = MonthGrid.days(for: month)
    let dayCount = days.count
    let weekCount = dayCount / 7
    var indexByISO: [String: Int] = [:]
    for (i, d) in days.enumerated() { indexByISO[d.iso] = i }
    func index(of date: Date) -> Int? {
        // Day in the passed calendar's zone (DateMath's own zone is TimeZone.current; callers
        // keep the two equal, see `dayDensity`).
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return indexByISO[DateMath.isoDate(year: y, month0: m - 1, day: d)]
    }

    // Same span as `mergeAppleItems`: an Apple timed event ending exactly at midnight stops the
    // instant before it. Local rows use the plain span, as `buildAgendaItems` does.
    func span(of event: Event, source: AppleSource?) -> Int {
        var e = event
        if source != nil, !e.isAllDay, let end = e.end, end > e.start, calendar.startOfDay(for: end) == end {
            e.end = end.addingTimeInterval(-1)
        }
        return spanDays(of: e, calendar: calendar)
    }

    // Split rows into bar candidates (by event id) and per-day lines.
    var barDays: [String: (event: Event, source: AppleSource?, days: Set<Int>)] = [:]
    var timed = [[(Date, String, MonthLine)]](repeating: [], count: dayCount)
    var open = [[(Date, String, MonthLine)]](repeating: [], count: dayCount)
    var done = [[(Date, String, MonthLine)]](repeating: [], count: dayCount)

    for item in items {
        guard let day = index(of: item.displayDate) else { continue }
        switch item.kind {
        case .event(let event):
            if event.isAllDay || span(of: event, source: item.appleSource) > 0 {
                // Every occurrence of an Apple series shares one id but has its own start.
                let key = item.appleSource == nil ? event.id : "\(event.id)|\(event.start.timeIntervalSince1970)"
                var entry = barDays[key] ?? (event, item.appleSource, [])
                entry.days.insert(day)
                barDays[key] = entry
            } else {
                let line = MonthLine(id: item.id, title: event.title,
                                     kind: .timed(colorRGB: item.appleSource?.colorRGB))
                timed[day].append((item.occurrence, event.title, line))
            }
        case .reminder(let reminder):
            let recurring = item.appleSource?.isRecurringSeries == true || reminder.recurrence != nil
            let line = MonthLine(id: item.id, title: reminder.title,
                                 kind: .reminder(isCompleted: item.isCompleted, isRecurring: recurring))
            if item.isCompleted { done[day].append((item.occurrence, reminder.title, line)) }
            else { open[day].append((item.occurrence, reminder.title, line)) }
        }
    }

    // Chunk each event's day rows into occurrences, then split each chunk per week row.
    struct Piece { let id: String; let title: String; let color: UInt32?; let holiday: Bool
        let row: Int; let start: Int; let end: Int; let before: Bool; let after: Bool }
    var pieces: [Piece] = []
    for (eventID, entry) in barDays {
        let span = span(of: entry.event, source: entry.source)
        let present = entry.days.sorted()
        let holiday = entry.source?.calendarTitle.lowercased().contains("holiday") == true
        var i = 0
        var first = true
        while i < present.count {
            let d0 = present[i]
            var chunkStart = d0
            if first, entry.event.recurrence == nil {
                // A one-off that began before the grid: its real start (possibly negative).
                let startOffset = calendar.dateComponents(
                    [.day], from: calendar.startOfDay(for: days[0].date),
                    to: calendar.startOfDay(for: entry.event.start)).day ?? d0
                if startOffset < d0, startOffset + span >= d0 { chunkStart = startOffset }
            }
            first = false
            let chunkEnd = chunkStart + span
            var covered: [Int] = []
            // Follow real occurrence boundaries: stop at a missing day or after span + 1 days.
            while i < present.count, present[i] <= chunkEnd,
                  covered.isEmpty || present[i] == covered.last! + 1 {
                covered.append(present[i]); i += 1
            }
            for row in 0..<weekCount {
                let inRow = covered.filter { $0 / 7 == row }
                guard let lo = inRow.first, let hi = inRow.last else { continue }
                let isFirstPiece = lo == covered.first!
                let isLastPiece = hi == covered.last!
                pieces.append(Piece(
                    id: "\(eventID)-\(chunkStart)-\(row)", title: entry.event.title,
                    color: entry.source?.colorRGB, holiday: holiday, row: row,
                    start: lo % 7, end: hi % 7,
                    before: isFirstPiece ? chunkStart < 0 : true,
                    after: isLastPiece ? chunkEnd > dayCount - 1 : true))
            }
        }
    }

    var weeks: [MonthWeek] = []
    let cap = max(rowCapacity, 0)
    for row in 0..<weekCount {
        // Lanes: longest first, then start column, then id; lowest free lane.
        let rowPieces = pieces.filter { $0.row == row }.sorted {
            let l = $0.end - $0.start, r = $1.end - $1.start
            if l != r { return l > r }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
        var laneCols: [[Bool]] = []
        var placed: [MonthBar] = []
        for p in rowPieces {
            var lane = 0
            while true {
                if lane == laneCols.count { laneCols.append([Bool](repeating: false, count: 7)) }
                if !(p.start...p.end).contains(where: { laneCols[lane][$0] }) { break }
                lane += 1
            }
            for c in p.start...p.end { laneCols[lane][c] = true }
            placed.append(MonthBar(id: p.id, title: p.title, colorRGB: p.color, isHoliday: p.holiday,
                                   startColumn: p.start, endColumn: p.end, lane: lane,
                                   continuesBefore: p.before, continuesAfter: p.after))
        }

        func lanesUsed(_ bars: [MonthBar], _ col: Int) -> Int {
            bars.filter { $0.startColumn <= col && col <= $0.endColumn }.map { $0.lane + 1 }.max() ?? 0
        }
        func sortedLines(_ day: Int) -> [MonthLine] {
            let key: ((Date, String, MonthLine), (Date, String, MonthLine)) -> Bool = {
                $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1
            }
            return timed[day].sorted(by: key).map { $0.2 } + open[day].sorted(by: key).map { $0.2 }
                + done[day].sorted(by: key).map { $0.2 }
        }

        let allLines = (0..<7).map { sortedLines(row * 7 + $0) }
        let overflowing = (0..<7).map { lanesUsed(placed, $0) + allLines[$0].count > cap }
        // Drop bars that cannot fit: beyond the last-but-one row and only over overflowing days.
        let kept = placed.filter { bar in
            !(bar.lane >= cap - 1 && (bar.startColumn...bar.endColumn).allSatisfy { overflowing[$0] })
        }
        var lines: [[MonthLine]] = []
        var overflow: [Int] = []
        for col in 0..<7 {
            if !overflowing[col] {
                lines.append(allLines[col]); overflow.append(0); continue
            }
            // Every bar at lane >= cap - 1 covering this day sits in (or below) the row the
            // "N more" label takes, so it is hidden here whether or not it stays in `bars`.
            let used = lanesUsed(kept.filter { $0.lane < cap - 1 }, col)
            let shown = max(0, cap - 1 - used)
            let hiddenBars = placed.filter {
                $0.startColumn <= col && col <= $0.endColumn && $0.lane >= cap - 1
            }.count
            lines.append(Array(allLines[col].prefix(shown)))
            overflow.append(hiddenBars + max(0, allLines[col].count - shown))
        }
        weeks.append(MonthWeek(bars: kept, lines: lines, overflow: overflow))
    }
    return weeks
}
