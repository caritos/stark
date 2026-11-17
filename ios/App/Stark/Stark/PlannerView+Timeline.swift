// ios/App/Stark/Stark/PlannerView+Timeline.swift
import SwiftUI
import UIKit
import StarkKit

extension PlannerView {
    /// Accent bar above the planner after a failed save, in the style of `ContentView`'s
    /// store-error bar; a tap dismisses it.
    func saveErrorBanner(_ message: String) -> some View {
        errorBanner(message) { saveError = nil }
    }

    /// Shown while a failed first read of the plan file keeps the planner locked
    /// (`PlanCacheState.plannerNotice`); not dismissable, since the lock stays until a read works.
    func lockedNotice(_ message: String) -> some View {
        Text(message)
            .font(Fonts.mono(12))
            .foregroundStyle(Colors.text)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Colors.accent)
            .accessibilityAddTraits(.isStaticText)
    }

    /// The store's own error (a month file that failed to read), which `ContentView`'s bar
    /// would show but the full-screen planner covers.
    func storeErrorBanner(_ message: String) -> some View {
        errorBanner(message) { store.error = nil }
    }

    private func errorBanner(_ message: String, dismiss: @escaping () -> Void) -> some View {
        Button(action: dismiss) {
            Text(message)
                .font(Fonts.mono(12))
                .foregroundStyle(Colors.text)
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Colors.accent)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Dismisses the message")
    }

    // MARK: Positions

    private func y(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 3600) * Self.hourHeight
    }

    private func height(minutes: Double) -> CGFloat {
        CGFloat(minutes / 60) * Self.hourHeight
    }

    /// The time at a y offset in the timeline's content (unsnapped; `PlanDraft` snaps).
    func time(atY y: CGFloat) -> Date {
        let clamped = min(max(y, 0), contentHeight)
        return dayStart.addingTimeInterval(TimeInterval(clamped / Self.hourHeight * 3600))
    }

    static func slotID(_ index: Int) -> String { "slot-\(index)" }

    // MARK: Banner

    func banner(_ items: [AgendaItem]) -> some View {
        PlannerAllDayBanner(items: items, gutter: Self.gutter)
    }

    // MARK: Timeline

    var timeline: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    timelineContent(width: outer.size.width)
                }
                .scrollIndicators(.visible)
                // Once an item is lifted or resized, scrolling is switched off so only the item
                // moves (edge auto-scroll still scrolls programmatically).
                .scrollDisabled(lift != nil || resize != nil)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewportFrame = $0 }
                .onAppear {
                    // Open near the start of the working day (07:30), with room above it.
                    DispatchQueue.main.async {
                        proxy.scrollTo(Self.slotID(7 * 4 + 2), anchor: .top)
                    }
                }
                .onChange(of: lift?.globalY) { _, newY in
                    updateAutoScroll(globalY: newY, proxy: proxy)
                }
            }
        }
    }

    private func timelineContent(width: CGFloat) -> some View {
        let laneX = Self.gutter
        let laneWidth = max(width - laneX - Spacing.sm, 100)
        let eventWidth = (laneWidth * 0.38).rounded()
        let taskX = laneX + eventWidth + Spacing.xs
        let taskWidth = laneWidth - eventWidth - Spacing.xs

        return ZStack(alignment: .topLeading) {
            // Quarter-hour slots: the grid lines, the hour labels and the scroll anchors.
            VStack(spacing: 0) {
                ForEach(0..<slotCount, id: \.self) { index in
                    slotRow(index)
                        .id(Self.slotID(index))
                }
            }
            .frame(width: width)

            if let model {
                ForEach(model.doneBlocks) { done in
                    doneBlock(done, width: taskWidth)
                        .offset(x: taskX, y: y(for: done.block.start))
                }
                ForEach(model.events) { item in
                    eventBlock(item)
                        .frame(width: eventWidth, height: eventHeight(item))
                        .offset(x: laneX, y: y(for: max(item.occurrence, dayStart)))
                }
                ForEach(model.timed) { item in
                    timedTask(item, width: taskWidth)
                        .offset(x: taskX, y: liftedY(id: item.id) ?? y(for: item.displayDate))
                        .zIndex(lift?.id == item.id ? 2 : 1)
                }
                // Straight from the draft (not the model, which is rebuilt in an `onChange` one
                // pass later), so a drop lands in the same frame the lift ends and `place`'s
                // animation applies to what is on screen. The draft starts from `model.blocks`,
                // so it holds only blocks of still-open tasks.
                ForEach(draft?.blocks ?? model.blocks) { block in
                    planBlock(block, width: taskWidth)
                        .offset(x: taskX, y: liftedY(id: block.id) ?? y(for: block.start))
                        .zIndex(lift?.id == block.id ? 2 : 1)
                }
            }
            // Over the blocks (as in the Day view), under a lifted one.
            if Self.calendar.isDate(day, inSameDayAs: today) {
                PlannerNowLine(gutter: laneX, width: width - Spacing.sm, y: { y(for: $0) })
                    .zIndex(1.5)
            }
        }
        .frame(width: width, height: contentHeight, alignment: .topLeading)
        .background(dropTargeted ? Colors.accent.opacity(0.06) : Color.clear)
        .background(Colors.card)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { contentMinY = $0 }
        // A tray chip dropped here becomes a block. The location is in this (content) view's
        // own coordinates, so y maps straight to a time; the block is centred on the finger.
        .dropDestination(for: String.self) { ids, location in
            guard let id = ids.first,
                  let item = model.flatMap({ m in (m.tray + m.trayNoDate).first(where: { $0.id == id }) })
            else { return false }
            let start = time(atY: location.y - height(minutes: Double(PlanLayout.defaultMinutes)) / 2)
            return place(item, at: start)
        } isTargeted: { dropTargeted = $0 }
    }

    /// One quarter hour: on the hour the `HourGrid` rule and label (noon in red), else a fainter
    /// quarter-hour hairline, which shows where a block snaps.
    private func slotRow(_ index: Int) -> some View {
        let isHour = index % 4 == 0
        let date = dayStart.addingTimeInterval(TimeInterval(index * Self.slotMinutes * 60))
        return ZStack(alignment: .topLeading) {
            if isHour {
                PlannerHourRule(hour: Self.calendar.component(.hour, from: date), gutter: Self.gutter)
            } else {
                Rectangle()
                    .fill(Colors.hourRule.opacity(0.45))
                    .frame(height: 0.5)
                    .padding(.leading, Self.gutter - Spacing.xs)
            }
        }
        .frame(height: Self.slotHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventHeight(_ item: AgendaItem) -> CGFloat {
        guard case .event(let event) = item.kind else { return Self.slotHeight }
        let start = max(item.occurrence, dayStart)
        let length = event.end.map { $0.timeIntervalSince(event.start) } ?? 0
        let end = min(item.occurrence.addingTimeInterval(length), dayEnd)
        let minutes = end.timeIntervalSince(start) / 60
        return max(height(minutes: minutes), Self.slotHeight + Spacing.sm)
    }

    private func eventBlock(_ item: AgendaItem) -> some View {
        PlannerEventBlock(item: item)
    }

    /// A task due this day at a set time and not yet planned: an outline at its due time.
    /// Moving it creates a block (`PlanDraft.place`); its due time is never changed.
    private func timedTask(_ item: AgendaItem, width: CGFloat) -> some View {
        let minutes = Double(PlanLayout.defaultMinutes)
        let visual = VStack(alignment: .leading, spacing: 1) {
            Text(item.title)
                .font(Fonts.mono(12, weight: .semibold))
                .foregroundStyle(Colors.text)
                .lineLimit(1)
            Text(AgendaFormat.time(item.displayDate))
                .font(Fonts.mono(11))
                .foregroundStyle(Colors.accent)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(width: width, height: max(height(minutes: minutes) - 1, 1), alignment: .topLeading)
        .background(Colors.accent.opacity(Colors.timelineBlockOpacity),
                    in: RoundedRectangle(cornerRadius: PlannerStyle.blockCorner))
        .background(Colors.card, in: RoundedRectangle(cornerRadius: PlannerStyle.blockCorner))
        .overlay {
            RoundedRectangle(cornerRadius: PlannerStyle.blockCorner)
                .strokeBorder(Colors.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .clipShape(RoundedRectangle(cornerRadius: PlannerStyle.blockCorner))
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .frame(height: height(minutes: minutes), alignment: .top)
        .opacity(lift?.id == item.id ? 0.8 : 1)
        .contentShape(Rectangle())
        .onTapGesture { timePick = .place(item, initial: item.displayDate) }
        let target = LiftTarget(id: item.id, top: y(for: item.displayDate), onDrop: { start, overTray in
            // Not a block, so there is nothing to remove: a drop over the tray leaves it where
            // it was (and is not a refusal).
            guard !overTray else { return true }
            return place(item, at: start)
        })
        return liftable(visual, target)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), due \(AgendaFormat.time(item.displayDate)), not planned")
        .accessibilityAction(named: "Add to plan") { timePick = .place(item, initial: item.displayDate) }
    }

    private func planBlock(_ block: PlanBlock, width: CGFloat) -> some View {
        let shownMinutes: Double = {
            if let resize, resize.id == block.id { return max(Double(PlanLayout.minMinutes), Double(resize.minutes)) }
            return Double(block.minutes)
        }()
        let blockHeight = height(minutes: shownMinutes)
        let title = title(ofReminder: block.reminderID)
        let range = "\(AgendaFormat.time(block.start))–\(AgendaFormat.time(block.end))"
        let visual = Group {
            if shownMinutes < 40 {
                // Under 40 pt there is room for one line: title, then the start time.
                (Text(title).font(Fonts.mono(11, weight: .semibold)).foregroundColor(.white)
                 + Text("  \(AgendaFormat.time(block.start))").font(Fonts.mono(10)).foregroundColor(.white.opacity(0.85)))
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Fonts.mono(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(shownMinutes >= 45 ? 2 : 1)
                    Text(range)
                        .font(Fonts.mono(11))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 1 pt shorter than its slot, so back-to-back blocks read as separate blocks.
        .frame(width: width, height: max(blockHeight - 1, 1))
        .background(Colors.accent)
        .clipShape(RoundedRectangle(cornerRadius: PlannerStyle.blockCorner))
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        // The resize grip: a short bar on the bottom edge, at the trailing side so it never runs
        // through the title. Pressing along the bottom edge and dragging resizes.
        .overlay(alignment: .bottomTrailing) {
            Capsule()
                .fill(Color.white.opacity(0.7))
                .frame(width: 16, height: 3)
                .padding(.trailing, 6)
                .padding(.bottom, 2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            // Remove: a sibling button, not nested in another button.
            Button { withAnimation(.easeOut(duration: 0.15)) { draft?.remove(id: block.id) } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: min(24, max(blockHeight - 1, 1)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .frame(height: blockHeight, alignment: .top)
        .opacity(lift?.id == block.id ? 0.85 : 1)
        .contentShape(Rectangle())
        .onTapGesture { actionBlock = block }
        let target = LiftTarget(id: block.id, top: y(for: block.start),
                                resizable: (minutes: block.minutes, height: blockHeight),
                                onDrop: { start, overTray in
            if overTray {
                withAnimation(.easeOut(duration: 0.15)) { draft?.remove(id: block.id) }
                return true
            }
            return draft?.move(id: block.id, to: start) ?? false
        })
        return liftable(visual, target)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), planned \(range)")
        .accessibilityAction(named: "Mark done") { completeBlock(block) }
        .accessibilityAction(named: "Move") { timePick = .move(block.id, initial: block.start) }
        .accessibilityAction(named: "Make longer") { resizeBlock(id: block.id, toMinutes: block.minutes + PlanLayout.snapMinutes) }
        .accessibilityAction(named: "Make shorter") { resizeBlock(id: block.id, toMinutes: block.minutes - PlanLayout.snapMinutes) }
        .accessibilityAction(named: "Remove from plan") { draft?.remove(id: block.id) }
    }

    /// A completed task's block: dimmed, checked and struck through. Read-only: no grip, no
    /// remove button, no tap or drag (it takes no touches at all), but `PlanDraft` keeps every
    /// other block off its slot.
    private func doneBlock(_ done: DayPlanModel.DoneBlock, width: CGFloat) -> some View {
        let block = done.block
        let blockHeight = height(minutes: Double(block.minutes))
        let range = "\(AgendaFormat.time(block.start))–\(AgendaFormat.time(block.end))"
        let title = Text(done.title)
            .font(Fonts.mono(12, weight: .semibold))
            .strikethrough(true, color: Colors.textSecondary)
            .foregroundStyle(Colors.textSecondary)
        return HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Colors.accent.opacity(0.8))
                .padding(.top, 3)
            if block.minutes < 40 {
                title.lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    title.lineLimit(block.minutes >= 45 ? 2 : 1)
                    Text(range)
                        .font(Fonts.mono(11))
                        .foregroundStyle(Colors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: width, height: max(blockHeight - 1, 1))
        .background(Colors.accent.opacity(Colors.timelineBlockOpacity * 0.6))
        .overlay {
            RoundedRectangle(cornerRadius: PlannerStyle.blockCorner).strokeBorder(Colors.accent.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PlannerStyle.blockCorner))
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("done: \(done.title), \(range)")
    }
}
