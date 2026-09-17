// ios/App/Stark/Stark/MonthGridView.swift
import SwiftUI
import StarkKit

struct MonthGridView: View {
    @EnvironmentObject private var store: PlannerStore
    @State private var visibleMonth = YearMonth(date: Date())
    let onSelectDate: (Date) -> Void

    var body: some View {
        let daysInMonth = DateMath.daysInMonth(year: visibleMonth.year, month0: visibleMonth.month0)
        let firstWeekday = DateMath.weekday(year: visibleMonth.year, month0: visibleMonth.month0, day: 1)

        VStack {
            HStack {
                Button("‹") { changeMonth(by: -1) }
                Spacer()
                Text(String(format: "%04d-%02d", visibleMonth.year, visibleMonth.month0 + 1))
                    .foregroundStyle(Colors.text)
                Spacer()
                Button("›") { changeMonth(by: 1) }
            }
            .padding(Spacing.md)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                ForEach(0..<firstWeekday, id: \.self) { _ in Color.clear }
                ForEach(1...daysInMonth, id: \.self) { day in
                    let date = DateMath.date(from: DateMath.isoDate(year: visibleMonth.year, month0: visibleMonth.month0, day: day))
                    Button("\(day)") { onSelectDate(date) }
                        .foregroundStyle(Colors.text)
                }
            }
        }
        .background(Colors.background)
        .task { store.loadMonth(visibleMonth) }
    }

    private func changeMonth(by offset: Int) {
        visibleMonth = YearMonth(year: visibleMonth.year, month0: visibleMonth.month0 + offset)
        store.loadMonth(visibleMonth)
    }
}
