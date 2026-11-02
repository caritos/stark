// ios/App/Stark/Stark/PlannerView.swift
import SwiftUI
import UIKit
import StarkKit

/// The day planner (timeboxing): a full-screen editor for one day's plan. The ‹ › chevrons in
/// the header step one calendar day at a time, with no bounds: today and later days are
/// editable, earlier days are view-only (`PastDayView` under the `DayHistory` numbers, with no
/// tray, no gestures and no save). Each editable day keeps its own unsaved draft in a
/// `PlanSession` while the user steps elsewhere.
///
/// - A vertically scrolling timeline (60 pt per hour, one row per real hour of the day, so a
///   23- or 25-hour DST day is drawn as it is). Events are dimmed purple blocks in a narrow
///   left column and never move; all-day and multi-day events sit in a banner above it.
///   Tasks due that day at a set time (`DayPlanModel.timed`) are accent outlines at their due
///   time; plan blocks are filled accent blocks with a resize grip on their bottom edge
///   (press the bottom edge, then drag).
///   Completed tasks' blocks stay as dimmed, struck-through DONE blocks (`DayPlanModel.doneBlocks`):
///   read-only, but nothing can be placed over them (`PlanDraft.done`).
/// - A tray along the bottom holds the open tasks with no block yet, in three panes, PAST,
///   TODAY (or TOMORROW) and FUTURE (`DayPlanModel.trayPast`/`trayToday`/`trayFuture`),
///   switched by the tab row or by swiping sideways (a paged `TabView`). It opens on the middle.
///
/// Every change goes into a `PlanDraft` (StarkKit), which owns the rules (15 minute snapping,
/// no overlap between blocks, nothing crossing midnight); nothing is written until the check
/// button calls `store.replacePlans(on:with:)`. The view only converts positions to times.
///
/// Gestures: a tray chip is dragged with system drag and drop (`.draggable` onto the
/// timeline's `.dropDestination`). A block or a timed task is lifted with a short press and
/// then dragged: a UIKit long-press recognizer on iOS 18+, a SwiftUI `LongPressGesture`
/// sequenced before a `DragGesture` on iOS 17 (see `liftable`), so a plain swipe over it
/// still scrolls the timeline. Dropping a block on the tray removes it (a timed task dropped
/// there stays put), and dragging near the timeline's top or bottom edge scrolls it. The same
/// press-then-drag on a block's bottom edge resizes it. VoiceOver cannot drag, so every chip
/// and block also has actions ("Add to plan", "Move", "Remove from plan", longer/shorter) and
/// a tap opens the same time picker.
struct PlannerView: View {
    /// The viewed day (start of day); the ‹ › chevrons step it. Today and later are editable,
    /// earlier days are view-only (`PlannerDays.isEditable`).
    @State private var day: Date
    /// The real today, handed down by `ContentView` (views never read `Date()` themselves).
    let today: Date

    init(day: Date, today: Date) {
        self.today = today
        _day = State(initialValue: Calendar(identifier: .gregorian).startOfDay(for: day))
    }

    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PlanDraft?
    /// The model is rebuilt only when the draft or the store changes, never per drag frame.
    @State private var model: DayPlanModel?
    @State private var confirmDiscard = false
    /// How many days the discard dialog is about to throw away (set when ✕ opens it).
    @State private var discardDayCount = 0
    /// The failed-save message ("Could not save the plan for Wed Nov 4"), shown as a banner.
    @State private var saveError: String?
    @State private var timePick: TimePick?
    /// The open block whose action menu (Done / Move / Remove) is showing.
    @State private var actionBlock: PlanBlock?
    /// Unsaved drafts of the days stepped away from, restored on stepping back.
    @State private var session = PlanSession()
    /// The tray pane on screen; the planner opens on the planned day's own pane.
    @State private var pane: TrayPane = .today

    // Drag state (blocks and timed tasks).
    @State private var lift: Lift?
    @State private var resize: Resize?
    @State private var contentMinY: CGFloat = 0
    @State private var viewportFrame: CGRect = .zero
    @State private var trayFrame: CGRect = .zero
    @State private var autoScroll: Task<Void, Never>?
    @State private var dropTargeted = false
    /// iOS 17 only: true while a SwiftUI lift gesture is in progress. SwiftUI never calls
    /// `.onEnded` for a cancelled gesture (an alert, Control Center), but it always resets this,
    /// so its reset is where a cancelled lift is cleaned up.
    @GestureState private var liftGestureActive = false

    private static let calendar = Calendar(identifier: .gregorian)
    static let hourHeight: CGFloat = 60
    private static let slotMinutes = PlanLayout.snapMinutes
    private static var slotHeight: CGFloat { hourHeight * CGFloat(slotMinutes) / 60 }
    private static let gutter: CGFloat = 60
    /// Room for the tab row, the hint, two rows of chips and the page dots.
    private static let trayHeight: CGFloat = 250
    private static let edgeZone: CGFloat = 48
    /// How far up from a block's bottom edge a press starts a resize instead of a move.
    private static let gripZone: CGFloat = 12

    private var dayStart: Date { Self.calendar.startOfDay(for: day) }
    private var dayEnd: Date { Self.calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400) }
    /// Quarter-hour slots in this calendar day (96 normally, 92 or 100 on a DST change day).
    private var slotCount: Int { Int(dayEnd.timeIntervalSince(dayStart) / 60) / Self.slotMinutes }
    private var contentHeight: CGFloat { CGFloat(slotCount) * Self.slotHeight }

    var body: some View {
        NavigationStack {
            Group {
                if isEditable {
                    VStack(spacing: 0) {
                        if let saveError { saveErrorBanner(saveError) }
                        if let model, !model.allDayEvents.isEmpty {
                            banner(model.allDayEvents)
                        }
                        Rectangle().fill(Colors.separator).frame(height: 1)
                        timeline
                        Rectangle().fill(Colors.separator).frame(height: 1)
                        tray
                    }
                } else {
                    VStack(spacing: 0) {
                        if let saveError { saveErrorBanner(saveError) }
                        pastDay
                    }
                }
            }
            .background(Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) { header }
                if isEditable {
                    SquareToolbarButton(systemImage: "checkmark", label: "Save plan", placement: .confirmationAction,
                                        isProminent: true, isDisabled: unsavedDayCount == 0) { save() }
                } else {
                    // Keeps the chevrons where they were while stepping into the past.
                    SquareToolbarPlaceholder(placement: .confirmationAction)
                }
                SquareToolbarButton(systemImage: "xmark", label: "Close", placement: .cancellationAction) { close() }
            }
            .confirmationDialog("Discard changes to this plan?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            } message: {
                if discardDayCount > 1 {
                    Text("\(discardDayCount) days have unsaved changes.")
                }
            }
            .confirmationDialog(
                actionBlock.map { title(ofReminder: $0.reminderID) } ?? "Task",
                isPresented: Binding(get: { actionBlock != nil }, set: { if !$0 { actionBlock = nil } }),
                titleVisibility: .visible, presenting: actionBlock
            ) { block in
                Button("Done") { completeBlock(block) }
                Button("Move") { timePick = .move(block.id, initial: block.start) }
                Button("Remove from plan", role: .destructive) {
                    withAnimation(.easeOut(duration: 0.15)) { draft?.remove(id: block.id) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $timePick) { pick in
                PlanTimePicker(title: pick.title, initial: pick.initial, day: day) { start in
                    apply(pick, at: start)
                }
            }
        }
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
        .task(id: day) { loadDay() }
        .onChange(of: today) { _, _ in todayChanged() }
        .onChange(of: draft?.blocks) { _, _ in rebuildModel() }
        .onChange(of: store.reminders) { _, _ in rebuildModel() }
        .onChange(of: store.events) { _, _ in rebuildModel() }
        .onChange(of: liftGestureActive) { _, active in
            guard !active else { return }
            // Deferred one turn so a normal release's `.onEnded` (which commits and cleans up)
            // has run first, whatever order SwiftUI uses; after a cancel this is the only
            // cleanup. `endLift` is idempotent and never commits or plays a haptic.
            DispatchQueue.main.async {
                if !liftGestureActive { endLift() }
            }
        }
    }

    // MARK: Model

    /// `blocks == nil` uses the saved plans; otherwise the draft's blocks replace this day's.
    private func makeModel(blocks: [PlanBlock]?) -> DayPlanModel {
        let plans: [PlanBlock]
        if let blocks {
            plans = store.plans.filter { !Self.calendar.isDate($0.start, inSameDayAs: day) } + blocks
        } else {
            plans = store.plans
        }
        return DayPlanModel.make(day: day, events: store.events, reminders: store.reminders,
                                 plans: plans, today: today,
                                 plannedElsewhere: session.plannedElsewhere(of: day, saved: store.plans, today: today))
    }

    // MARK: Day stepping

    private var isEditable: Bool { PlannerDays.isEditable(day, today: today, calendar: Self.calendar) }

    /// Loads the months `day` needs (its week widened by the overdue lookback), then builds the
    /// draft: the one kept from an earlier visit in this session, or a fresh one from the saved
    /// plans. A past day has no draft or model; it draws from `DayHistory`.
    private func loadDay() {
        store.loadMonths(covering: PlannerDays.loadRange(for: day, calendar: Self.calendar))
        guard isEditable else {
            draft = nil
            model = nil
            return
        }
        if let kept = session.draft(for: day) {
            draft = kept
            model = makeModel(blocks: kept.blocksToSave)
        } else {
            let saved = makeModel(blocks: nil)
            draft = PlanDraft(model: saved, saved: store.plans(on: day))
            model = saved
        }
    }

    /// Keeps the current day's draft in the session, moves to the day `days` away and drops
    /// every in-flight gesture or menu; `.task(id: day)` then loads the new day.
    private func step(_ days: Int) {
        if let draft, isEditable { session.stash(draft, for: day) }
        endLift()  // lift, resize, autoScroll
        actionBlock = nil
        timePick = nil
        pane = .today
        draft = nil
        model = nil
        let next = PlannerDays.step(day, by: days, calendar: Self.calendar)
        // Load first, so a day in an unloaded month never draws empty for a frame.
        store.loadMonths(covering: PlannerDays.loadRange(for: next, calendar: Self.calendar))
        day = next
    }

    /// `‹  TITLE  ›`: the day word (TODAY / TOMORROW / weekday) over the date line, which says
    /// VIEW ONLY on a past day, and the done/planned summary on an editable one.
    private var header: some View {
        HStack(spacing: Spacing.sm) {
            SquareButton(systemImage: "chevron.left", label: "Previous day") { step(-1) }
            VStack(spacing: 1) {
                Text(dayWord)
                    .font(Fonts.mono(12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Colors.text)
                Text(dateLine)
                    .font(Fonts.mono(10))
                    .tracking(1.5)
                    .foregroundStyle(Colors.textSecondary)
                if isEditable, let summary = DayPlanModel.summary(done: model?.doneCount ?? 0, planned: draft?.blocks.count ?? 0) {
                    Text(summary)
                        .font(Fonts.mono(9))
                        .tracking(1.5)
                        .foregroundStyle(Colors.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 150)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            SquareButton(systemImage: "chevron.right", label: "Next day") { step(1) }
        }
    }

    private var dateLine: String {
        let date = Self.titleFormatter.string(from: day).uppercased()
        return isEditable ? date : "\(date) - VIEW ONLY"
    }

    /// A past day: the `DayHistory` numbers above the read-only timeline. No tray, no gestures.
    private var pastDay: some View {
        let history = DayHistory.make(day: day, events: store.events, reminders: store.reminders,
                                      plans: store.plans, today: today)
        let week = DayHistory.weekStats(containing: day, reminders: store.reminders, plans: store.plans, today: today)
        return VStack(spacing: 0) {
            PastDayHeader(history: history, weekStats: week)
            PastDayView(day: day, history: history, isToday: false)
        }
    }

    /// Done from the block menu: the store's own completion path (same as the agenda checkbox,
    /// idempotent), then the block becomes a done block in the draft; the due date and the plan
    /// itself are untouched, and unsaved draft edits survive.
    private func completeBlock(_ block: PlanBlock) {
        guard draft?.blocks.contains(where: { $0.id == block.id }) == true else { return }
        store.completeReminder(id: block.reminderID, on: block.occurrence, today: today)
        withAnimation(.easeOut(duration: 0.15)) { _ = draft?.markDone(id: block.id) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        rebuildModel()
    }

    private func rebuildModel() {
        guard let draft else { return }
        // Everything the save would write, so the done blocks stay in the rebuilt model.
        model = makeModel(blocks: draft.blocksToSave)
    }

    private var dayWord: String {
        if Self.calendar.isDate(day, inSameDayAs: today) { return "TODAY" }
        if let tomorrow = Self.calendar.date(byAdding: .day, value: 1, to: Self.calendar.startOfDay(for: today)),
           Self.calendar.isDate(day, inSameDayAs: tomorrow) { return "TOMORROW" }
        return AgendaFormat.weekdayName(day).uppercased()
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    private func title(ofReminder id: String) -> String {
        store.reminders.first { $0.id == id }?.title ?? "Task"
    }

    // MARK: Save / close

    /// Puts the viewed day's live draft into the session (editable days only) and drops drafts
    /// for days that have lapsed, so `session.hasChanges`/`changedDays` count exactly the
    /// still-editable days with unsaved edits.
    private func syncSession() {
        session.dropLapsed(today: today)
        if let draft, isEditable { session.stash(draft, for: day) }
    }

    /// The days with unsaved changes, without mutating the session (for the ✓ button's state):
    /// the live draft for the viewed day, the session's drafts for the others, lapsed ones
    /// left out.
    private var unsavedDayCount: Int {
        let others = session.changedDays.filter {
            !Self.calendar.isDate($0, inSameDayAs: day) && PlannerDays.isEditable($0, today: today, calendar: Self.calendar)
        }
        let current = isEditable && (draft?.hasChanges ?? session.draft(for: day)?.hasChanges ?? false)
        return others.count + (current ? 1 : 0)
    }

    /// ✓: writes every changed, still-editable day (never a past day). If every write succeeds
    /// the planner closes; otherwise it stays open with all drafts kept and a banner naming the
    /// failed days, and a retry rewrites the same blocks (`replacePlans` is a replace).
    private func save() {
        syncSession()
        let failed = session.saveAll(today: today) { store.replacePlans(on: $0, with: $1) }
        if failed.isEmpty {
            saveError = nil
            dismiss()
        } else {
            let days = failed.map { Self.titleFormatter.string(from: $0) }.joined(separator: ", ")
            saveError = "Could not save the plan for \(days)"
        }
    }

    /// ✕: asks first when any editable day has unsaved changes.
    private func close() {
        syncSession()
        if session.hasChanges {
            discardDayCount = session.changedDays.count
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    /// `today` moved on (midnight) while the planner was open: lapsed drafts go, and a viewed
    /// day that is now past switches to the view-only body with its draft and gestures dropped.
    private func todayChanged() {
        session.dropLapsed(today: today)
        guard !isEditable else { return }
        endLift()
        actionBlock = nil
        timePick = nil
        draft = nil
        model = nil
    }

    /// Accent bar above the planner after a failed save, in the style of `ContentView`'s
    /// store-error bar; a tap dismisses it.
    private func saveErrorBanner(_ message: String) -> some View {
        Button { saveError = nil } label: {
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
    private func time(atY y: CGFloat) -> Date {
        let clamped = min(max(y, 0), contentHeight)
        return dayStart.addingTimeInterval(TimeInterval(clamped / Self.hourHeight * 3600))
    }

    private static func slotID(_ index: Int) -> String { "slot-\(index)" }

    // MARK: Banner

    private func banner(_ items: [AgendaItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(items) { item in
                    Text(item.title)
                        .font(Fonts.mono(11))
                        .foregroundStyle(Colors.text)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Colors.eventDot.opacity(0.35))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Colors.eventDot).frame(width: 3)
                        }
                        .accessibilityLabel("All day: \(item.title)")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: Timeline

    private var timeline: some View {
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
        }
        .frame(width: width, height: contentHeight, alignment: .topLeading)
        .background(dropTargeted ? Colors.accent.opacity(0.06) : Colors.background)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { contentMinY = $0 }
        // A tray chip dropped here becomes a block. The location is in this (content) view's
        // own coordinates, so y maps straight to a time; the block is centred on the finger.
        .dropDestination(for: String.self) { ids, location in
            guard let id = ids.first, let item = model?.tray.first(where: { $0.id == id }) else { return false }
            let start = time(atY: location.y - height(minutes: Double(PlanLayout.defaultMinutes)) / 2)
            return place(item, at: start)
        } isTargeted: { dropTargeted = $0 }
    }

    private func slotRow(_ index: Int) -> some View {
        let isHour = index % 4 == 0
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(isHour ? Colors.separator : Colors.separator.opacity(0.35))
                .frame(height: 1)
                .padding(.leading, Self.gutter - Spacing.xs)
            if isHour {
                Text(AgendaFormat.time(dayStart.addingTimeInterval(TimeInterval(index * Self.slotMinutes * 60))))
                    .font(Fonts.mono(10))
                    .foregroundStyle(Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.gutter - Spacing.sm, alignment: .trailing)
                    .offset(y: -6)
                    .accessibilityHidden(true)
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
        Text(item.title)
            .font(Fonts.mono(10))
            .foregroundStyle(Colors.text.opacity(0.8))
            .lineLimit(2)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Colors.eventDot.opacity(0.3))
            .overlay(alignment: .leading) { Rectangle().fill(Colors.eventDot.opacity(0.8)).frame(width: 2) }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Event: \(item.title), \(AgendaFormat.time(item.occurrence))")
    }

    /// A task due this day at a set time and not yet planned: an outline at its due time.
    /// Moving it creates a block (`PlanDraft.place`); its due time is never changed.
    private func timedTask(_ item: AgendaItem, width: CGFloat) -> some View {
        let minutes = Double(PlanLayout.defaultMinutes)
        let visual = VStack(alignment: .leading, spacing: 1) {
            Text(AgendaFormat.time(item.displayDate))
                .font(Fonts.mono(9))
                .foregroundStyle(Colors.accent)
            Text(item.title)
                .font(Fonts.mono(11))
                .foregroundStyle(Colors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .frame(width: width, height: height(minutes: minutes), alignment: .topLeading)
        .background(Colors.background)
        .overlay { Rectangle().strokeBorder(Colors.accent, lineWidth: 1) }
        .clipped()
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
            if shownMinutes < 30 {
                // A quarter hour is 15 pt: one line, start time then title.
                (Text(AgendaFormat.time(block.start)).font(Fonts.mono(9)).foregroundColor(Colors.background.opacity(0.8))
                 + Text("  \(title)").font(Fonts.mono(10, weight: .semibold)).foregroundColor(Colors.background))
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(range)
                        .font(Fonts.mono(9))
                        .foregroundStyle(Colors.background.opacity(0.8))
                    Text(title)
                        .font(Fonts.mono(11, weight: .semibold))
                        .foregroundStyle(Colors.background)
                        .lineLimit(shownMinutes >= 45 ? 2 : 1)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.leading, Spacing.xs)
        .padding(.trailing, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 1 pt shorter than its slot, so back-to-back blocks read as separate blocks.
        .frame(width: width, height: max(blockHeight - 1, 1))
        .background(Colors.accent)
        .clipped()
        // The resize grip: a short bar on the bottom edge, at the trailing side so it never runs
        // through the title. Pressing along the bottom edge and dragging resizes.
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Colors.background.opacity(0.6))
                .frame(width: 16, height: 2)
                .padding(.trailing, 6)
                .padding(.bottom, 2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            // Remove: a sibling button, not nested in another button.
            Button { withAnimation(.easeOut(duration: 0.15)) { draft?.remove(id: block.id) } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Colors.background)
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
            .font(Fonts.mono(11))
            .strikethrough(true, color: Colors.textSecondary)
            .foregroundStyle(Colors.textSecondary)
        return HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Colors.accent.opacity(0.8))
                .padding(.top, 3)
            if block.minutes < 30 {
                title.lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(range)
                        .font(Fonts.mono(9))
                        .foregroundStyle(Colors.textSecondary.opacity(0.8))
                    title.lineLimit(block.minutes >= 45 ? 2 : 1)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: width, height: max(blockHeight - 1, 1))
        .background(Colors.accent.opacity(0.12))
        .overlay { Rectangle().strokeBorder(Colors.accent.opacity(0.4), lineWidth: 1) }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("done: \(done.title), \(range)")
    }

    // MARK: Lift and drag (blocks, timed tasks)

    /// Where a lifted item is drawn, from the finger's current position and the scroll offset
    /// (so it stays under the finger while the timeline auto-scrolls).
    private func liftedY(id: String) -> CGFloat? {
        guard let lift, lift.id == id else { return nil }
        return lift.globalY - contentMinY - lift.grabOffset
    }

    /// What a press-and-drag on a timeline item does.
    private struct LiftTarget {
        let id: String
        /// The item's top in timeline content coordinates.
        let top: CGFloat
        /// Blocks only: their length and drawn height. A press on the bottom edge resizes.
        var resizable: (minutes: Int, height: CGFloat)?
        /// Called on release with the new start and whether the finger is over the tray.
        let onDrop: (Date, Bool) -> Bool
    }

    /// Press briefly, then drag: a plain swipe over a block still scrolls the timeline. One
    /// gesture per item, so a move and a resize never compete for the same touch (a separate
    /// grip gesture won SwiftUI's fuzzy hit-test even for presses well above it, seen in the
    /// simulator): on a block, a press on its bottom edge resizes, anywhere else moves.
    ///
    /// On iOS 18+ this is a UIKit long-press recognizer: it fails as soon as the finger moves
    /// before the press is held, so the scroll view's pan takes the swipe. A SwiftUI
    /// `LongPressGesture.sequenced(before: DragGesture)` on the item (as `.gesture` or
    /// `.simultaneousGesture`) stopped every swipe that started on a block from scrolling the
    /// timeline (seen in the iOS 26 simulator). iOS 17 keeps the SwiftUI gesture.
    private func liftable<Content: View>(_ content: Content, _ target: LiftTarget) -> some View {
        Group {
            if #available(iOS 18.0, *) {
                content.gesture(LiftRecognizer(
                    onBegan: { liftBegan(target, at: $0) },
                    onChanged: { liftMoved(target, to: $0) },
                    onEnded: { liftEnded(target, at: $0, cancelled: $1) }
                ))
            } else {
                content.gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                        .updating($liftGestureActive) { _, active, _ in active = true }
                        .onChanged { value in
                            guard case .second(true, let drag?) = value else { return }
                            if lift?.id == target.id || resize?.id == target.id {
                                liftMoved(target, to: drag.location)
                            } else {
                                liftBegan(target, at: drag.startLocation)
                                liftMoved(target, to: drag.location)
                            }
                        }
                        .onEnded { value in
                            guard case .second(true, let drag?) = value else { endLift(); return }
                            liftEnded(target, at: drag.location, cancelled: false)
                        }
                )
            }
        }
    }

    /// `point` is in global coordinates.
    private func liftBegan(_ target: LiftTarget, at point: CGPoint) {
        let grab = point.y - contentMinY - target.top
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let resizable = target.resizable,
           grab >= resizable.height - min(Self.gripZone, resizable.height / 3) {
            resize = Resize(id: target.id, startY: point.y, baseMinutes: resizable.minutes,
                            minutes: CGFloat(resizable.minutes))
        } else {
            lift = Lift(id: target.id, grabOffset: grab, globalY: point.y)
        }
    }

    private func liftMoved(_ target: LiftTarget, to point: CGPoint) {
        if let current = resize, current.id == target.id {
            resize?.minutes = CGFloat(current.baseMinutes) + (point.y - current.startY) / Self.hourHeight * 60
        } else if lift?.id == target.id {
            lift?.globalY = point.y
        }
    }

    private func liftEnded(_ target: LiftTarget, at point: CGPoint, cancelled: Bool) {
        defer { endLift() }
        guard !cancelled else { return }
        if let current = resize, current.id == target.id {
            resizeBlock(id: target.id, toMinutes: Int(Double(current.minutes).rounded()))
            return
        }
        guard let lift, lift.id == target.id else { return }
        let overTray = trayFrame.contains(point)
        let topY = point.y - contentMinY - lift.grabOffset
        if !target.onDrop(time(atY: topY), overTray) { refuse() }
    }

    private func endLift() {
        lift = nil
        resize = nil
        autoScroll?.cancel()
        autoScroll = nil
    }

    private static func inBottomZone(_ y: CGFloat, viewport: CGRect) -> Bool {
        y > viewport.maxY - edgeZone && y <= viewport.maxY
    }

    /// Scrolls the timeline a quarter hour at a time while a lifted item is held within
    /// `edgeZone` of its top or bottom edge. Stops when the finger leaves the zone or drops.
    private func updateAutoScroll(globalY: CGFloat?, proxy: ScrollViewProxy) {
        guard let globalY, viewportFrame.height > 0 else {
            autoScroll?.cancel(); autoScroll = nil; return
        }
        let direction: Int
        if globalY < viewportFrame.minY + Self.edgeZone { direction = -1 }
        // The bottom zone ends at the timeline's own bottom edge: below it is the tray, where a
        // hovering block is about to be dropped (removed), not scrolled.
        else if Self.inBottomZone(globalY, viewport: viewportFrame) { direction = 1 }
        else { direction = 0 }
        guard direction != 0 else { autoScroll?.cancel(); autoScroll = nil; return }
        guard autoScroll == nil else { return }
        autoScroll = Task { @MainActor in
            while !Task.isCancelled, let current = lift?.globalY {
                let up = current < viewportFrame.minY + Self.edgeZone
                let down = Self.inBottomZone(current, viewport: viewportFrame)
                guard up || down else { break }
                let visibleTop = viewportFrame.minY - contentMinY
                let topSlot = Int((visibleTop / Self.slotHeight).rounded())
                if up {
                    guard topSlot > 0 else { break }
                    withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(Self.slotID(topSlot - 1), anchor: .top) }
                } else {
                    // The first slot not wholly visible below: anchoring its bottom edge to the
                    // viewport's always moves at least one slot. (`topSlot + visibleSlots`
                    // could land on the slot already at the bottom when the viewport is not a
                    // whole number of slots tall, and the scroll then stalled; seen in the
                    // simulator.)
                    let bottomSlot = Int(((visibleTop + viewportFrame.height) / Self.slotHeight).rounded(.up))
                    guard bottomSlot < slotCount else { break }
                    withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(Self.slotID(bottomSlot), anchor: .bottom) }
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
            autoScroll = nil
        }
    }

    // MARK: Tray

    /// True while a plan block is lifted: dropping it on the tray removes it.
    private var liftingBlock: Bool {
        guard let id = lift?.id else { return false }
        return draft?.blocks.contains { $0.id == id } == true
    }

    /// Tabs, then the three panes in a paged `TabView` (swipe sideways, or tap a tab), then
    /// page dots. The pager's horizontal pan and a chip's system drag (a long press) do not
    /// compete: a quick sideways swipe pages, a press-and-hold lifts the chip.
    private var tray: some View {
        VStack(spacing: 0) {
            trayTabs
            TabView(selection: $pane) {
                ForEach(TrayPane.allCases, id: \.self) { pane in
                    trayPane(pane).tag(pane)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
            ForEach(TrayPane.allCases, id: \.self) { tab in
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
            ForEach(TrayPane.allCases, id: \.self) { dot in
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
    private func place(_ item: AgendaItem, at start: Date) -> Bool {
        var placed = false
        withAnimation(.easeOut(duration: 0.15)) {
            placed = draft?.place(item, at: start) ?? false
        }
        if !placed { refuse() }
        return placed
    }

    private func apply(_ pick: TimePick, at start: Date) {
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
    private func resizeBlock(id: String, toMinutes requested: Int) {
        let step = PlanLayout.snapMinutes
        let wanted = max(PlanLayout.minMinutes, Int((Double(requested) / Double(step)).rounded()) * step)
        draft?.resize(id: id, toMinutes: requested)
        if let result = draft?.blocks.first(where: { $0.id == id }), result.minutes != wanted { refuse() }
    }

    /// A refused place or move leaves the draft unchanged; this is the only feedback.
    private func refuse() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// A block or timed task being dragged.
private struct Lift: Equatable {
    let id: String
    /// Finger's distance below the item's top edge when it was lifted.
    let grabOffset: CGFloat
    var globalY: CGFloat
}

/// Press-and-hold, then drag (iOS 18+). A `UILongPressGestureRecognizer` keeps reporting
/// `.changed` as the finger moves after the hold, and fails if the finger moves first, which
/// leaves the swipe to the scroll view. Locations are global.
@available(iOS 18.0, *)
private struct LiftRecognizer: UIGestureRecognizerRepresentable {
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint, Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.25
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = context.converter.location(in: .global)
        switch recognizer.state {
        case .began: onBegan(point)
        case .changed: onChanged(point)
        case .ended: onEnded(point, false)
        case .cancelled, .failed: onEnded(point, true)
        default: break
        }
    }
}

/// A block whose bottom edge is being dragged.
private struct Resize: Equatable {
    let id: String
    let startY: CGFloat
    let baseMinutes: Int
    var minutes: CGFloat
}

/// What the time picker sheet is choosing a time for.
private enum TimePick: Identifiable {
    case place(AgendaItem, initial: Date)
    case move(String, initial: Date)

    var id: String {
        switch self {
        case .place(let item, _): return "place-\(item.id)"
        case .move(let id, _): return "move-\(id)"
        }
    }

    var title: String {
        switch self {
        case .place: return "Add to plan"
        case .move: return "Move"
        }
    }

    var initial: Date {
        switch self {
        case .place(_, let date), .move(_, let date): return date
        }
    }
}

/// The non-drag path (VoiceOver, or a tap): pick a start time on the planned day, rounded to
/// the quarter hour (`PlanLayout.snap`), then place or move the item there.
private struct PlanTimePicker: View {
    let title: String
    let day: Date
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    private static let calendar = Calendar(identifier: .gregorian)

    init(title: String, initial: Date, day: Date, onPick: @escaping (Date) -> Void) {
        self.title = title
        self.day = day
        self.onPick = onPick
        _time = State(initialValue: PlanLayout.snap(initial))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                DatePicker("Start", selection: $time, displayedComponents: .hourAndMinute)
                    #if targetEnvironment(macCatalyst)
                    .datePickerStyle(.compact)
                    #else
                    .datePickerStyle(.wheel)
                    #endif
                    .labelsHidden()
                Text("Rounded to the nearest 15 minutes.")
                    .font(Fonts.mono(11))
                    .foregroundStyle(Colors.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(Colors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbar {
                SquareToolbarButton(systemImage: "checkmark", label: title, placement: .confirmationAction,
                                    isProminent: true) {
                    onPick(startOnDay())
                    dismiss()
                }
                SquareToolbarButton(systemImage: "xmark", label: "Cancel", placement: .cancellationAction) { dismiss() }
            }
        }
        .presentationDetents([.medium])
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
    }

    /// The picked hour and minute on the planned day, snapped to the quarter hour.
    private func startOnDay() -> Date {
        let parts = Self.calendar.dateComponents([.hour, .minute], from: time)
        let start = Self.calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0,
                                       of: Self.calendar.startOfDay(for: day)) ?? day
        return PlanLayout.snap(start)
    }
}
