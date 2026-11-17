// ios/App/Stark/Stark/YearView.swift
import SwiftUI
import StarkKit

/// The year mode: a year title with chevrons, a scrolling two-column grid of the twelve
/// mini-months, and the drag bar underneath (dragging it up, or tapping it, returns to month).
///
/// Each mini-month is a Sunday-first 6 x 7 block of real dates (`MonthGrid.days`), neighbouring
/// months' days dimmed and never tinted. A day with items is a rounded square tinted by
/// `DayDensity.level` (1 / 2-3 / 4+ items): pale yellow, amber, salmon (`Colors.heat*`). Today is
/// the solid accent square regardless of heat. One drag gesture per block maps the touch to a
/// cell (`cellIndex`), shows a magnified preview while pressed and selects the date on release;
/// `ContentView` then returns to month mode and scrolls the agenda.
///
/// The counts come from `yearDensity` (the same Apple rows and plans as the month grid) computed
/// off the main actor, never in `body`, and the Apple overlay fetches all twelve months of the
/// shown year, or their days would silently show as empty.
struct YearView: View {
    @Environment(AppleOverlayModel.self) private var overlay
    /// Apple reminders' plan blocks (sidecar), counted like the agenda does.
    @Environment(PlanCache.self) private var planCache
    /// The year on screen. Starts as the selected day's year; the chevrons change it.
    @State private var year: Int
    /// The last computed density, tagged with the year it belongs to (see `MonthGridView`).
    @State private var density: DensitySnapshot?
    let today: Date
    @Binding var mode: CalendarMode
    let onSelectDate: (Date) -> Void

    private static let cellHeight: CGFloat = 24
    private static let cellRadius: CGFloat = 6
    @State private var pressed: PressedCell?
    @State private var gridWidth: CGFloat = 0
    private static let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md, alignment: .top), count: 2)
    private let dayColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    init(today: Date, selectedDate: Date, mode: Binding<CalendarMode>, onSelectDate: @escaping (Date) -> Void) {
        self.today = today
        self._mode = mode
        self.onSelectDate = onSelectDate
        self._year = State(initialValue: YearMonth(date: selectedDate).year)
    }

    /// One day cell of one mini-month. The same date shows up in two mini-months (as a day of its
    /// own month and as a neighbouring day of the adjacent one), so the identity carries the
    /// month: `(month, iso)` is unique across all twelve blocks.
    private struct YearCell: Identifiable {
        let month0: Int
        let day: GridDay
        var id: String { "\(month0)-\(day.iso)" }
    }

    var body: some View {
        let todayIso = DateMath.isoDate(from: today)
        // Only a snapshot computed for the year on screen is used, so paging never flashes the
        // previous year's tint on the new year's days while the new counts are computed.
        let visibleDensity = density?.year == year ? density?.days ?? [:] : [:]

        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(columns: monthColumns, spacing: Spacing.md) {
                    ForEach(0..<12, id: \.self) { month0 in
                        miniMonth(month0, todayIso: todayIso, density: visibleDensity)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .contentMargins(.bottom, FloatingBottomBar.clearance + 20, for: .scrollContent)
            .onPreferenceChange(GridWidthKey.self) { gridWidth = $0 }
        }
        // The grid uses the space down to the bar; the drag handle floats over its bottom edge.
        .overlay(alignment: .bottom) {
            #if !targetEnvironment(macCatalyst)
            ModeHandle(mode: $mode, floating: true)
                .padding(.bottom, FloatingBottomBar.clearance)
            #endif
        }
        .background(Colors.background)
        // The Apple overlay must fetch every month of the year the screen shows. Runs on appear
        // and again whenever the year changes.
        .task(id: year) {
            let range = YearGrid.range(year: year)
            await overlay.reload(for: .year, display: range, today: today)
        }
        // Stop widening the overlay's fetch to this year once the year view is gone.
        .onDisappear {
            let today = today
            Task { await overlay.reload(for: .year, display: nil, today: today) }
        }
        // Recompute when (and only when) the year, today, the Apple snapshot or the plans change; off the
        // main actor, and a stale result (the id changed while it ran) is dropped.
        .task(id: densityInputs) {
            // Debounce: the detached computation below cannot be cancelled, so tapping ‹/› quickly
            // would otherwise run one full-year `yearDensity` per tap. `.task(id:)` cancels this
            // task on every new id, so a rapid burst wakes up only once, for the last year.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let inputs = densityInputs
            let events = inputs.events
            let reminders = inputs.reminders
            let plans = inputs.plans
            let apple = inputs.apple
            let today = inputs.today
            let year = inputs.year
            let days = await Task.detached(priority: .userInitiated) {
                yearDensity(events: events, reminders: reminders, year: year, today: today, plans: plans, apple: apple)
            }.value
            guard !Task.isCancelled else { return }
            density = DensitySnapshot(year: year, days: days)
        }
    }

    /// Everything the density depends on. It is the `.task(id:)`, so the density is recomputed
    /// exactly when one of these changes.
    private struct DensityInputs: Equatable {
        let year: Int
        let today: Date
        let events: [Event]
        let reminders: [Reminder]
        let plans: [PlanBlock]
        let apple: AppleSnapshot
    }

    private struct DensitySnapshot {
        let year: Int
        /// Keyed by ISO date (`yyyy-MM-dd`), only days of that year with something on them.
        let days: [String: DayDensity]
    }

    private var densityInputs: DensityInputs {
        DensityInputs(year: year, today: today, events: [], reminders: [],
                      plans: planCache.applePlans,
                      apple: overlay.snapshot)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(String(year))
                .font(Fonts.mono(34, weight: .bold))
                .foregroundStyle(Colors.yearRed)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.leading, Spacing.md)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            chevron("‹", label: "Previous year") { year -= 1 }
            chevron("›", label: "Next year") { year += 1 }
        }
        .padding(.trailing, Spacing.sm)
        .frame(minHeight: 52)
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

    /// Row and column of a touch inside a mini-month's 6 x 7 day grid, as the flat index into
    /// `MonthGrid.days`; nil outside the grid. Pure, so the touch mapping has no view state.
    static func cellIndex(x: CGFloat, y: CGFloat, width: CGFloat, cellHeight: CGFloat = YearView.cellHeight) -> Int? {
        guard width > 0, x >= 0, y >= 0, x < width else { return nil }
        let column = Int(x / (width / 7))
        let row = Int(y / cellHeight)
        guard column < 7, row < 6 else { return nil }
        return row * 7 + column
    }

    private func miniMonth(_ month0: Int, todayIso: String, density: [String: DayDensity]) -> some View {
        let cells = MonthGrid.days(for: YearMonth(year: year, month0: month0))
            .map { YearCell(month0: month0, day: $0) }
        let todayWeekday = Calendar.current.component(.weekday, from: today) - 1
        let showsToday = YearMonth(date: today) == YearMonth(year: year, month0: month0)
        let pressedIndex = pressed?.month0 == month0 ? pressed?.index : nil
        return VStack(spacing: 0) {
            Text(AgendaFormat.monthName(DateMath.date(from: DateMath.isoDate(year: year, month0: month0, day: 1))))
                .font(Fonts.mono(17, weight: .bold))
                .foregroundStyle(Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 28)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: dayColumns, spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Self.weekdayLabels[index])
                        .font(Fonts.mono(11, weight: .semibold))
                        .foregroundStyle(showsToday && index == todayWeekday ? Colors.accent : Colors.text)
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .accessibilityHidden(true)
                }
            }

            LazyVGrid(columns: dayColumns, spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.element.id) { offset, cell in
                    dayCell(cell.day, isToday: cell.day.iso == todayIso, counts: density[cell.day.iso] ?? .none)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel((density[cell.day.iso] ?? .none)
                            .accessibilityLabel(title: AgendaFormat.monthDay(cell.day.date), isToday: cell.day.iso == todayIso))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onSelectDate(cell.day.date) }
                        // A neighbouring-month day duplicates a label that exists in its own
                        // month's block; it stays touchable but VoiceOver skips it.
                        .accessibilityHidden(!cell.day.isInMonth)
                }
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: GridWidthKey.self, value: proxy.size.width)
            })
            .overlay(alignment: .topLeading) {
                if let index = pressedIndex, index < cells.count {
                    preview(cells[index].day, index: index, isToday: cells[index].day.iso == todayIso)
                }
            }
            // One touch tracker per block replaces a Button per cell, so a press can show the
            // magnified preview. It is a UIKit recogniser (see `PressTracker`): a SwiftUI
            // `DragGesture` over a ScrollView's content swallows the scroll on iOS 18+.
            .overlay(
                PressTracker(
                    onMove: { point in
                        let index = Self.cellIndex(x: point.x, y: point.y, width: gridWidth)
                        let next = index.map { PressedCell(month0: month0, index: $0) }
                        if pressed != next { pressed = next }
                    },
                    onEnd: { point in
                        pressed = nil
                        guard let index = Self.cellIndex(x: point.x, y: point.y, width: gridWidth),
                              index < cells.count else { return }
                        onSelectDate(cells[index].day.date)
                    },
                    onCancel: { pressed = nil }
                )
                .accessibilityHidden(true)
            )
        }
        .zIndex(pressed?.month0 == month0 ? 1 : 0)
    }

    private struct PressedCell: Equatable {
        let month0: Int
        let index: Int
    }

    private struct GridWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    /// The magnified white square over the pressed cell, kept inside the screen: it may reach
    /// into the page margin but no further.
    private func preview(_ day: GridDay, index: Int, isToday: Bool) -> some View {
        let size = Self.previewSize
        let cellWidth = gridWidth / 7
        let column = CGFloat(index % 7), row = CGFloat(index / 7)
        let centerX = min(max((column + 0.5) * cellWidth, size / 2 - Spacing.md + 2),
                          gridWidth + Spacing.md - 2 - size / 2)
        let centerY = (row + 0.5) * Self.cellHeight
        return Text("\(day.day)")
            .font(Fonts.mono(24, weight: .bold))
            .foregroundStyle(Color.black)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2))
            .position(x: centerX, y: centerY)
            .frame(width: 0, height: 0, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static let previewSize: CGFloat = 46

    private func dayCell(_ day: GridDay, isToday: Bool, counts: DayDensity) -> some View {
        Text("\(day.day)")
            .font(Fonts.mono(14, weight: isToday ? .bold : .regular))
            .foregroundStyle(isToday ? Color.white : (day.isInMonth ? Colors.text : Colors.textSecondary))
            .frame(maxWidth: .infinity, minHeight: Self.cellHeight, maxHeight: Self.cellHeight)
            .background {
                if isToday {
                    RoundedRectangle(cornerRadius: Self.cellRadius).fill(Colors.accent)
                } else if day.isInMonth, let heat = Self.heatColor(level: counts.level) {
                    RoundedRectangle(cornerRadius: Self.cellRadius).fill(heat)
                }
            }
            .contentShape(Rectangle())
    }

    /// The heat tint for a `DayDensity.level`, nil for an empty day.
    private static func heatColor(level: Int) -> Color? {
        switch level {
        case 1: return Colors.heatLow
        case 2: return Colors.heatMedium
        case 3...: return Colors.heatHigh
        default: return nil
        }
    }
}

/// Reports a touch's position inside its frame: down and drags (`onMove`), lift (`onEnd`) and
/// cancellation (`onCancel`, e.g. once the surrounding scroll view starts scrolling, which is
/// allowed to happen simultaneously, so a vertical swipe still scrolls the year).
private struct PressTracker: UIViewRepresentable {
    let onMove: (CGPoint) -> Void
    let onEnd: (CGPoint) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let recognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PressTracker?

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began, .changed: parent?.onMove(point)
            case .ended: parent?.onEnd(point)
            case .cancelled, .failed: parent?.onCancel()
            default: break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
