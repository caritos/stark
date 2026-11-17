// ios/App/Stark/Stark/PlannerView+Tray.swift
import SwiftUI
import UIKit
import StarkKit

extension PlannerView {
    // MARK: Tray

    /// True while a plan block is lifted: dropping it on the tray removes it.
    private var liftingBlock: Bool {
        guard let id = lift?.id else { return false }
        return draft?.blocks.contains { $0.id == id } == true
    }

    /// Tabs, then the three panes in a paged `TabView` (swipe sideways, or tap a tab), then
    /// page dots. The pager's horizontal pan and a chip's system drag (a long press) do not
    /// compete: a quick sideways swipe pages, a press-and-hold lifts the chip.
    var tray: some View {
        VStack(spacing: 0) {
            trayTabs
            TabView(selection: $pane) {
                ForEach(trayPanes, id: \.self) { pane in
                    trayPane(pane).tag(pane)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // A new pager when the panes change (NO DATE comes or goes): the paged TabView keeps
            // its page index when a page is removed and writes that page's tag back (FUTURE
            // instead of TODAY, seen in the simulator); a fresh one opens on `pane`.
            .id(trayPanes)
            trayDots
        }
        .frame(height: Self.trayHeight)
        .frame(maxWidth: .infinity)
        .background(Colors.background)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { trayFrame = $0 }
    }

    private func count(_ pane: TrayPane) -> Int {
        model.map { pane.items(in: $0).count } ?? 0
    }

    private var trayTabs: some View {
        HStack(spacing: 0) {
            ForEach(trayPanes, id: \.self) { tab in
                let selected = tab == pane
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { pane = tab }
                } label: {
                    VStack(spacing: Spacing.xs) {
                        (Text(tab.label(dayWord: dayWord))
                            .foregroundColor(selected ? Colors.text : Colors.textSecondary)
                         + Text(" \(count(tab))")
                            .foregroundColor(selected ? Colors.accent : Colors.textSecondary.opacity(0.6)))
                            .font(Fonts.mono(10, weight: .semibold))
                            .tracking(1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Rectangle()
                            .fill(selected ? Colors.accent : Color.clear)
                            .frame(height: 2)
                    }
                    .padding(.top, Spacing.sm)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.accessibilityLabel(dayWord: dayWord, count: count(tab)))
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, Spacing.md)
        .overlay(alignment: .bottom) { Rectangle().fill(Colors.separator).frame(height: 1) }
    }

    private func trayPane(_ pane: TrayPane) -> some View {
        let items = model.map { pane.items(in: $0) } ?? []
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(liftingBlock ? "DROP HERE TO REMOVE FROM PLAN" : pane.hint(dayWord: dayWord))
                .font(Fonts.mono(9))
                .tracking(1.5)
                .foregroundStyle(liftingBlock ? Colors.accent : Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if items.isEmpty {
                Text(model == nil ? "Loading…" : "Nothing here")
                    .font(Fonts.mono(12))
                    .foregroundStyle(Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.xs)],
                              alignment: .leading, spacing: Spacing.xs) {
                        ForEach(items) { item in
                            trayChip(item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var trayDots: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(trayPanes, id: \.self) { dot in
                Rectangle()
                    .fill(dot == pane ? Colors.accent : Colors.separator)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }

    private func trayChip(_ item: AgendaItem) -> some View {
        Button {
            timePick = .place(item, initial: suggestedStart)
        } label: {
            chipLabel(item)
        }
        .buttonStyle(.plain)
        .draggable(item.id) {
            chipLabel(item).frame(width: 160)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chipAccessibilityLabel(item))
        .accessibilityHint("Drag onto the timeline, or use the Add to plan action.")
        .accessibilityAction(named: "Add to plan") { timePick = .place(item, initial: suggestedStart) }
    }

    private func chipLabel(_ item: AgendaItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title)
                .font(Fonts.mono(11))
                .foregroundStyle(Colors.text)
                .lineLimit(1)
            if let note = chipNote(item) {
                Text(note)
                    .font(Fonts.mono(9))
                    .foregroundStyle(item.isOverdue ? Colors.accent : Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(Colors.separator)
        .overlay(alignment: .leading) { Rectangle().fill(Colors.accent).frame(width: 2) }
        .contentShape(Rectangle())
    }

    private func chipNote(_ item: AgendaItem) -> String? {
        // An undated Apple reminder (NO DATE pane) has a sentinel occurrence, never shown.
        if item.isUndatedApple { return nil }
        if item.isOverdue { return "due \(AgendaFormat.monthDay(item.occurrence))" }
        if Self.calendar.isDate(item.occurrence, inSameDayAs: day) { return nil }
        return "due \(AgendaFormat.monthDay(item.occurrence))"
    }

    private func chipAccessibilityLabel(_ item: AgendaItem) -> String {
        guard let note = chipNote(item) else { return item.title }
        return "\(item.title), \(note)"
    }

    /// Where the time picker starts for a tray task: right after the last block, else 09:00.
    private var suggestedStart: Date {
        if let last = model?.blocks.map(\.end).max() { return last }
        return dayStart.addingTimeInterval(9 * 3600)
    }

    // MARK: Changes

    @discardableResult
    func place(_ item: AgendaItem, at start: Date) -> Bool {
        var placed = false
        withAnimation(.easeOut(duration: 0.15)) {
            placed = draft?.place(item, at: start) ?? false
        }
        if !placed { refuse() }
        return placed
    }

    func apply(_ pick: TimePick, at start: Date) {
        switch pick {
        case .place(let item, _):
            place(item, at: start)
        case .move(let id, _):
            if draft?.move(id: id, to: start) != true { refuse() }
        }
    }

    /// Resizes a block; when `PlanDraft` had to clamp the length (the next block or midnight),
    /// plays the same refusal haptic as a refused move. Shrinking to the 15 minute minimum is
    /// not a refusal.
    func resizeBlock(id: String, toMinutes requested: Int) {
        let step = PlanLayout.snapMinutes
        let wanted = max(PlanLayout.minMinutes, Int((Double(requested) / Double(step)).rounded()) * step)
        draft?.resize(id: id, toMinutes: requested)
        if let result = draft?.blocks.first(where: { $0.id == id }), result.minutes != wanted { refuse() }
    }

    /// A refused place or move leaves the draft unchanged; this is the only feedback.
    func refuse() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
