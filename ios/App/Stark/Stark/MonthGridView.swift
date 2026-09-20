// ios/App/Stark/Stark/MonthGridView.swift
import SwiftUI
import StarkKit

/// Fixed-height, Sunday-first month grid. Today is a filled accent square, the selected day
/// (when it isn't today) an outlined one. No density dots.
struct MonthGridView: View {
    @EnvironmentObject private var store: PlannerStore
    @State private var visibleMonth = YearMonth(date: Date())
    /// Passed in (not read from `Date()` here) so the highlight moves when the day changes.
    let today: Date
    let selectedDate: Date
    let onSelectDate: (Date) -> Void

    private static let rowHeight: CGFloat = 34
    private static let cellSize: CGFloat = 30
    /// A month spans at most 6 week-rows; always reserving all 6 keeps the grid (and so the
    /// agenda below it) from resizing as the user pages between months.
    private static let maxRows = 6
    private static let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let daysInMonth = DateMath.daysInMonth(year: visibleMonth.year, month0: visibleMonth.month0)
        // DateMath.weekday: 0 = Sunday ... 6 = Saturday, i.e. the count of leading blanks
        // for a Sunday-first grid.
        let leadingBlanks = DateMath.weekday(year: visibleMonth.year, month0: visibleMonth.month0, day: 1)
        let todayIso = DateMath.isoDate(from: today)
        let selectedIso = DateMath.isoDate(from: selectedDate)

        VStack(spacing: 0) {
            header

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Self.weekdayLabels[index])
                        .font(Fonts.mono(11))
                        .foregroundStyle(Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 20)
                }
            }

            LazyVGrid(columns: columns, spacing: 0) {
                // One ForEach over distinctly-identified cells: two ForEaches keyed by bare Int
                // (blanks 0..<n, days 1...m) collide on id 1 and silently drop the 1st.
                ForEach(cells(leadingBlanks: leadingBlanks, daysInMonth: daysInMonth), id: \.self) { cell in
                    switch cell {
                    case .blank:
                        Color.clear.frame(height: Self.rowHeight)
                    case .day(let day):
                        let iso = DateMath.isoDate(year: visibleMonth.year, month0: visibleMonth.month0, day: day)
                        dayCell(day: day, iso: iso, isToday: iso == todayIso, isSelected: iso == selectedIso)
                    }
                }
            }
            .frame(height: Self.rowHeight * CGFloat(Self.maxRows), alignment: .top)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .background(Colors.background)
        .task { store.loadMonth(visibleMonth) }
        // The day rolled over: if the grid was showing the old today's month, show the new one's.
        .onChange(of: today) { oldToday, newToday in
            guard visibleMonth == YearMonth(date: oldToday) else { return }
            visibleMonth = YearMonth(date: newToday)
            store.loadMonth(visibleMonth)
        }
    }

    private enum Cell: Hashable {
        case blank(Int)
        case day(Int)
    }

    private func cells(leadingBlanks: Int, daysInMonth: Int) -> [Cell] {
        (0..<leadingBlanks).map(Cell.blank) + (1...daysInMonth).map(Cell.day)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(monthTitle)
                .font(Fonts.mono(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Colors.text)
                .padding(.leading, Spacing.sm)
            Spacer()
            chevron("‹", label: "Previous month") { changeMonth(by: -1) }
            chevron("›", label: "Next month") { changeMonth(by: 1) }
        }
        .frame(height: 44)
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(Fonts.mono(22))
                .foregroundStyle(Colors.text)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayCell(day: Int, iso: String, isToday: Bool, isSelected: Bool) -> some View {
        Button {
            onSelectDate(DateMath.date(from: iso))
        } label: {
            Text("\(day)")
                .font(Fonts.mono(15))
                .foregroundStyle(isToday ? Colors.background : Colors.text)
                .frame(width: Self.cellSize, height: Self.cellSize)
                .background {
                    if isToday {
                        Rectangle().fill(Colors.accent)
                    } else if isSelected {
                        Rectangle().strokeBorder(Colors.accent, lineWidth: 1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var monthTitle: String {
        let first = DateMath.date(from: DateMath.isoDate(year: visibleMonth.year, month0: visibleMonth.month0, day: 1))
        return AgendaFormat.monthYear(first).uppercased()
    }

    private func changeMonth(by offset: Int) {
        visibleMonth = YearMonth(year: visibleMonth.year, month0: visibleMonth.month0 + offset)
        store.loadMonth(visibleMonth)
    }
}
