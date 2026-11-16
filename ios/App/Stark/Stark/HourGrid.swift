// ios/App/Stark/Stark/HourGrid.swift
import SwiftUI
import StarkKit

/// Sizes and the minute-to-y mapping shared by the Day and Week timelines.
enum HourGridMetrics {
    /// About 60 pt per hour, as in Fantastical.
    static let hourHeight: CGFloat = 60
    /// Room above the first rule so the "12 AM" label is not cut in half.
    static let topInset: CGFloat = 10
    static let bottomInset: CGFloat = 10
    /// The hour-label column at the leading edge.
    static let labelWidth: CGFloat = 52
    /// A short block (a 15 minute event is 15 pt) is still drawn this tall, so it can be read
    /// and tapped.
    static let minBlockHeight: CGFloat = 22
    static let totalHeight: CGFloat = topInset + 24 * hourHeight + bottomInset

    /// The y of wall-clock `minute` (0...1440) inside the grid.
    static func y(forMinute minute: Int) -> CGFloat {
        topInset + CGFloat(minute) * hourHeight / 60
    }

    /// The instant at wall-clock `minute` of `day` (1440 is the next day's start). Built from
    /// hour and minute, never by adding seconds, so a DST day still reads 9:00 at minute 540.
    static func date(minute: Int, on day: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        let start = calendar.startOfDay(for: day)
        if minute >= 1440 {
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        }
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: start) ?? start
    }

    /// "12 AM", "1 AM" ... "11 AM", "noon", "1 PM" ... on a 12-hour phone; "00:00" ... "23:00"
    /// on a 24-hour one (a bare "09" reads as a number, not a time).
    static func hourLabel(_ hour: Int) -> String {
        if !uses12Hour { return String(format: "%02d:00", hour) }
        if hour == 12 { return "noon" }
        let date = Calendar(identifier: .gregorian).date(bySettingHour: hour, minute: 0, second: 0, of: Date(timeIntervalSince1970: 0)) ?? Date()
        return hourFormatter.string(from: date)
    }

    /// The now-line's label, e.g. "1:28" (no AM/PM, like Fantastical).
    static func nowLabel(_ date: Date) -> String {
        nowFormatter.string(from: date).trimmingCharacters(in: .whitespaces)
    }

    /// The phone's hour style: true when its short time format has an AM/PM marker.
    static var uses12Hour: Bool { hourFormatter.dateFormat.contains("a") }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.setLocalizedDateFormatFromTemplate("j")
        return f
    }()

    private static let nowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.setLocalizedDateFormatFromTemplate("jmm")
        f.amSymbol = ""
        f.pmSymbol = ""
        return f
    }()

    /// Wall-clock minutes of `date` in the phone's calendar.
    static func wallMinute(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// The 24-hour grid behind the Day and Week timelines: an hour label at every rule (noon in red),
/// light hour rules, `columnCount` equal columns to the right of the labels (optional hairlines
/// between them and a pale highlight on one), and, when `nowColumn` is set, a red current-time
/// line across the columns with a dot at that column's leading edge and the time in the label
/// column, updated every minute. `content` is laid over the columns (its frame starts at minute
/// 0's column origin and is `HourGridMetrics.totalHeight` tall) and gets the column width.
///
/// Always 24 rows: minutes are wall-clock (`HourGridMetrics.y(forMinute:)`), so a DST day's
/// missing or repeated hour is not drawn.
struct HourGrid<Content: View>: View {
    let columnCount: Int
    /// The column showing today, which gets the now-line's dot; nil hides the now-line.
    var nowColumn: Int?
    /// A column drawn on a pale blue ground (Week: today).
    var highlightedColumn: Int?
    /// Hairlines between columns (Week).
    var showsColumnRules = false
    @ViewBuilder let content: (_ columnWidth: CGFloat) -> Content

    private typealias M = HourGridMetrics

    var body: some View {
        GeometryReader { proxy in
            let gridWidth = max(0, proxy.size.width - M.labelWidth)
            let columnWidth = gridWidth / CGFloat(max(1, columnCount))
            ZStack(alignment: .topLeading) {
                if let column = highlightedColumn, column >= 0, column < columnCount {
                    Rectangle()
                        .fill(Colors.todayCell)
                        .frame(width: columnWidth, height: M.totalHeight)
                        .offset(x: M.labelWidth + CGFloat(column) * columnWidth)
                }
                if showsColumnRules {
                    Path { p in
                        for i in 0...columnCount {
                            let x = M.labelWidth + CGFloat(i) * columnWidth
                            p.move(to: CGPoint(x: x, y: M.y(forMinute: 0)))
                            p.addLine(to: CGPoint(x: x, y: M.y(forMinute: 1440)))
                        }
                    }
                    .stroke(Colors.hourRule, lineWidth: 0.5)
                }
                Path { p in
                    for hour in 0...24 {
                        let y = M.y(forMinute: hour * 60)
                        p.move(to: CGPoint(x: M.labelWidth, y: y))
                        p.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(Colors.hourRule, lineWidth: 0.5)

                TimelineView(.everyMinute) { context in
                    labels(hidingNear: nowColumn == nil ? nil : M.wallMinute(context.date))
                }

                content(columnWidth)
                    .frame(width: gridWidth, height: M.totalHeight, alignment: .topLeading)
                    .offset(x: M.labelWidth)

                // Over the blocks, as in Fantastical.
                if let column = nowColumn {
                    TimelineView(.everyMinute) { context in
                        nowLine(minute: M.wallMinute(context.date), date: context.date, column: column,
                                columnWidth: columnWidth, width: proxy.size.width)
                    }
                }
            }
        }
        .frame(height: M.totalHeight)
    }

    /// Hour labels centred on their rules; one within 12 minutes of the now-line gives way to it.
    private func labels(hidingNear now: Int?) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { hour in
                if now.map({ abs($0 - hour * 60) >= 12 }) ?? true {
                    Text(M.hourLabel(hour))
                        .font(Fonts.mono(11, weight: hour == 12 ? .semibold : .regular))
                        .foregroundStyle(hour == 12 ? Colors.yearRed : Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: M.labelWidth - 8, height: 16, alignment: .trailing)
                        .offset(y: M.y(forMinute: hour * 60) - 8)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func nowLine(minute: Int, date: Date, column: Int, columnWidth: CGFloat, width: CGFloat) -> some View {
        let y = M.y(forMinute: minute)
        let dotX = M.labelWidth + CGFloat(column) * columnWidth
        return ZStack(alignment: .topLeading) {
            Text(M.nowLabel(date))
                .font(Fonts.mono(11, weight: .semibold))
                .foregroundStyle(Colors.nowLine)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: M.labelWidth - 8, height: 16, alignment: .trailing)
                .offset(y: y - 8)
            Rectangle()
                .fill(Colors.nowLine)
                .frame(width: max(0, width - M.labelWidth), height: 1.5)
                .offset(x: M.labelWidth, y: y - 0.75)
            Circle()
                .fill(Colors.nowLine)
                .frame(width: 10, height: 10)
                .offset(x: dotX - 5, y: y - 5)
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Now, \(AgendaFormat.time(date))")
    }
}

/// One timed block on the grid: pale calendar-colour fill, a colour bar at the leading edge, the
/// title (a reminder gets a small checkbox glyph first) and, when there is room and `showsTime`,
/// the time range under it.
struct TimelineBlockView: View {
    let block: TimelineBlock
    let day: Date
    let height: CGFloat
    var showsTime = true
    /// Week's narrow columns: smaller text, a smaller checkbox, tighter padding.
    var compact = false
    /// The drawn width, when known: a sliver of an overlap cluster drops the checkbox (under
    /// 22 pt) and then the title (under 16 pt) rather than showing a glyph and no text.
    var width: CGFloat = .infinity

    private var showsCheckbox: Bool { block.isReminder && width >= 22 }
    private var showsTitle: Bool { width >= 16 }

    var body: some View {
        let tint = block.colorRGB.map { Color(hex: $0) } ?? (block.isReminder ? Colors.reminderBox : Colors.eventDot)
        // Top-aligned: a long block reads its title at its start time, not in its middle.
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: compact ? 2 : 4) {
                    if showsCheckbox {
                        RoundedRectangle(cornerRadius: 2.5)
                            .strokeBorder(tint, lineWidth: 1.2)
                            .background(RoundedRectangle(cornerRadius: 2.5).fill(block.isCompleted ? tint : Color.clear))
                            .frame(width: compact ? 8 : 11, height: compact ? 8 : 11)
                            .padding(.top, 2)
                    }
                    if showsTitle {
                        Text(block.title)
                            .font(Fonts.mono(compact ? 10 : 12, weight: .semibold))
                            .strikethrough(block.isCompleted)
                            .foregroundStyle(block.isCompleted ? Colors.textSecondary : Colors.text)
                            .lineLimit(compact ? max(1, Int((height - 4) / 13)) : (height >= 52 ? 2 : 1))
                    }
                }
                if showsTime && height >= 38 {
                    Text(timeRange)
                        .font(Fonts.mono(11))
                        .foregroundStyle(Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 2 : 4)
            .padding(.vertical, height >= 30 ? 3 : 1)
            Spacer(minLength: 0)
        }
        .frame(height: height, alignment: .top)
        .background(tint.opacity(Colors.timelineBlockOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var timeRange: String {
        let start = HourGridMetrics.date(minute: block.startMinute, on: day)
        if block.isReminder { return AgendaFormat.time(start) }
        let end = HourGridMetrics.date(minute: block.endMinute, on: day)
        return "\(AgendaFormat.time(start)) – \(AgendaFormat.time(end))"
    }

    /// "<title>, <start> to <end>" (a reminder: "<title>, reminder at <time>").
    var accessibilityText: String {
        let start = AgendaFormat.time(HourGridMetrics.date(minute: block.startMinute, on: day))
        if block.isReminder {
            return "\(block.title), reminder at \(start)\(block.isCompleted ? ", completed" : "")"
        }
        let end = AgendaFormat.time(HourGridMetrics.date(minute: block.endMinute, on: day))
        return "\(block.title), \(start) to \(end)"
    }
}

/// An all-day item above the grid: pale calendar-colour pill with its title (holiday calendars
/// lilac, as in the full Month).
struct TimelineChipView: View {
    let chip: TimelineChip
    /// Week's narrow columns: smaller text and padding.
    var compact = false

    var body: some View {
        let tint = chip.colorRGB.map { Color(hex: $0) } ?? Colors.eventDot
        Text(chip.title)
            .font(Fonts.mono(compact ? 10 : 12, weight: .medium))
            .foregroundStyle(chip.isHoliday ? Colors.holidayText : Colors.text)
            .lineLimit(1)
            .padding(.horizontal, compact ? 3 : 6)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(chip.isHoliday ? Colors.holidayChip : tint.opacity(Colors.timelineBlockOpacity)))
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

/// The last slot of a full all-day strip: "+N" for the chips that did not fit.
struct TimelineMoreChipView: View {
    let count: Int
    var compact = false

    var body: some View {
        Text("+\(count)")
            .font(Fonts.mono(compact ? 10 : 12, weight: .semibold))
            .foregroundStyle(Colors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, compact ? 3 : 6)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4).fill(Colors.hourRule.opacity(0.5)))
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}
