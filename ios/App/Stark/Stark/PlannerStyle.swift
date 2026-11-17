// ios/App/Stark/Stark/PlannerStyle.swift
import SwiftUI
import StarkKit

/// The planner's look, shared by the editable timeline (`PlannerView+Timeline`) and the past-day
/// view (`PastDayView`): the Day view's tokens (`HourGrid`, `TimelineBlockView`) at the planner's
/// own geometry (its slot height and gutter never change here).
enum PlannerStyle {
    /// Corner radius of every block on the timeline.
    static let blockCorner: CGFloat = 6
    /// Tray chips and tabs.
    static let chipCorner: CGFloat = 8

    /// An event's calendar colour (an Apple calendar's own), else the default event colour.
    static func tint(_ item: AgendaItem) -> Color {
        item.appleSource?.colorRGB.map { Color(hex: $0) } ?? Colors.eventDot
    }
}

/// One hour rule and its label, as in `HourGrid`: a light hairline, the label centred on it,
/// "noon" (or 12:00) semibold red. `hour` is the wall-clock hour at the rule.
struct PlannerHourRule: View {
    let hour: Int
    let gutter: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Colors.hourRule)
                .frame(height: 0.5)
                .padding(.leading, gutter - Spacing.xs)
            Text(HourGridMetrics.hourLabel(hour))
                .font(Fonts.mono(11, weight: hour == 12 ? .semibold : .regular))
                .foregroundStyle(hour == 12 ? Colors.yearRed : Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: gutter - Spacing.sm, height: 16, alignment: .trailing)
                .offset(y: -8)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .accessibilityHidden(true)
        }
    }
}

/// A calendar event on the planner's timeline, like a Day-view block: pale calendar-colour fill,
/// a colour bar at the leading edge, the title in semibold. Takes no touches.
struct PlannerEventBlock: View {
    let item: AgendaItem

    var body: some View {
        let tint = PlannerStyle.tint(item)
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(tint).frame(width: 3)
            Text(item.title)
                .font(Fonts.mono(11, weight: .semibold))
                .foregroundStyle(Colors.text)
                .lineLimit(2)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(Colors.timelineBlockOpacity))
        // Opaque under the tint: the planner draws overlapping events in one column, so a
        // later one covers an earlier one instead of mixing their titles.
        .background(Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: PlannerStyle.blockCorner))
        .overlay {
            RoundedRectangle(cornerRadius: PlannerStyle.blockCorner).strokeBorder(Colors.card, lineWidth: 0.5)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Event: \(item.title), \(AgendaFormat.time(item.occurrence))")
    }
}

/// The day's all-day and multi-day events above the timeline, as Day-view chips.
struct PlannerAllDayBanner: View {
    let items: [AgendaItem]
    let gutter: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(items) { item in
                    Text(item.title)
                        .font(Fonts.mono(12, weight: .medium))
                        .foregroundStyle(Colors.text)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 22)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(PlannerStyle.tint(item).opacity(Colors.timelineBlockOpacity)))
                        .accessibilityLabel("All day: \(item.title)")
                }
            }
            .padding(.leading, gutter)
            .padding(.trailing, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

/// The red current-time line across the lanes, with a dot at the lane's leading edge and the
/// time in the label column, as in `HourGrid`. `y` maps an instant to the timeline's content.
struct PlannerNowLine: View {
    let gutter: CGFloat
    let width: CGFloat
    let y: (Date) -> CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            let lineY = y(context.date)
            ZStack(alignment: .topLeading) {
                Text(HourGridMetrics.nowLabel(context.date))
                    .font(Fonts.mono(11, weight: .semibold))
                    .foregroundStyle(Colors.nowLine)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: gutter - Spacing.sm, height: 16, alignment: .trailing)
                    .background(Colors.card)
                    .offset(y: lineY - 8)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                Rectangle()
                    .fill(Colors.nowLine)
                    .frame(width: max(0, width - gutter), height: 1.5)
                    .offset(x: gutter, y: lineY - 0.75)
                Circle()
                    .fill(Colors.nowLine)
                    .frame(width: 10, height: 10)
                    .offset(x: gutter - 5, y: lineY - 5)
            }
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Now, \(AgendaFormat.time(context.date))")
        }
    }
}
