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
///   TODAY (or TOMORROW) and FUTURE (`DayPlanModel.trayPast`/`trayToday`/`trayFuture`), plus a
///   NO DATE pane while there are undated Apple reminders (`TrayPane.panes(for:)`), switched by
///   the tab row or by swiping sideways (a paged `TabView`). It opens on the day's own pane.
///
/// Every change goes into a `PlanDraft` (StarkKit), which owns the rules (15 minute snapping,
/// no overlap between blocks, nothing crossing midnight); nothing is written until the check
/// button calls `ItemRouter.replacePlans(on:with:)` (Apple reminders' blocks to Stark's sidecar,
/// Stark's own to the local store). The view only converts positions to times.
///
/// Apple items (phase 1, spec Decision 2): the overlay's snapshot supplies Apple events and
/// reminders (`DayPlanModel.make(apple:)`), `PlanCache` the Apple blocks (read synchronously,
/// passed once through `PlannerPlans`), and while the planner is open it registers the viewed
/// day's range with the shared Apple fetch window (`.planner`). Done on a block completes
/// through the router with the block's occurrence.
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
    @State var day: Date
    /// The real today, handed down by `ContentView` (views never read `Date()` themselves).
    let today: Date

    init(day: Date, today: Date) {
        self.today = today
        _day = State(initialValue: Calendar(identifier: .gregorian).startOfDay(for: day))
    }

    @EnvironmentObject var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.itemRouter) private var router
    @Environment(AppleOverlayModel.self) var overlay
    @Environment(PlanCache.self) private var planCache

    @State var draft: PlanDraft?
    /// The model is rebuilt only when the draft or the store changes, never per drag frame.
    @State var model: DayPlanModel?
    @State private var confirmDiscard = false
    /// How many days the discard dialog is about to throw away (set when ✕ opens it).
    @State private var discardDayCount = 0
    /// The failed-save message ("Could not save the plan for Wed Nov 4"), shown as a banner.
    @State var saveError: String?
    @State var timePick: TimePick?
    /// The open block whose action menu (Done / Move / Remove) is showing.
    @State var actionBlock: PlanBlock?
    /// Unsaved drafts of the days stepped away from, restored on stepping back.
    @State private var session = PlanSession()
    /// The tray pane on screen; the planner opens on the planned day's own pane.
    @State var pane: TrayPane = .today
    /// True while the check button is writing (the router is async): a second tap starts nothing.
    @State private var isSaving = false

    // Drag state (blocks and timed tasks).
    @State var lift: Lift?
    @State var resize: Resize?
    @State var contentMinY: CGFloat = 0
    @State var viewportFrame: CGRect = .zero
    @State var trayFrame: CGRect = .zero
    @State var autoScroll: Task<Void, Never>?
    @State var dropTargeted = false
    /// iOS 17 only: true while a SwiftUI lift gesture is in progress. SwiftUI never calls
    /// `.onEnded` for a cancelled gesture (an alert, Control Center), but it always resets this,
    /// so its reset is where a cancelled lift is cleaned up.
    @GestureState var liftGestureActive = false

    static let calendar = Calendar(identifier: .gregorian)
    static let hourHeight: CGFloat = 60
    static let slotMinutes = PlanLayout.snapMinutes
    static var slotHeight: CGFloat { hourHeight * CGFloat(slotMinutes) / 60 }
    static let gutter: CGFloat = 60
    /// Room for the tab row, the hint, two rows of chips and the page dots.
    static let trayHeight: CGFloat = 250
    static let edgeZone: CGFloat = 48
    /// How far up from a block's bottom edge a press starts a resize instead of a move.
    static let gripZone: CGFloat = 12

    var dayStart: Date { Self.calendar.startOfDay(for: day) }
    var dayEnd: Date { Self.calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400) }
    /// Quarter-hour slots in this calendar day (96 normally, 92 or 100 on a DST change day).
    var slotCount: Int { Int(dayEnd.timeIntervalSince(dayStart) / 60) / Self.slotMinutes }
    var contentHeight: CGFloat { CGFloat(slotCount) * Self.slotHeight }

    var body: some View {
        NavigationStack {
            Group {
                if isEditable {
                    VStack(spacing: 0) {
                        header
                        if let notice = planCache.state.plannerNotice { lockedNotice(notice) }
                        if let storeError = store.error, storeError != planCache.state.plannerNotice {
                            storeErrorBanner(storeError)
                        }
                        if let saveError { saveErrorBanner(saveError) }
                        if let model, !model.allDayEvents.isEmpty {
                            banner(model.allDayEvents)
                        }
                        // Non-interactive and dimmed while a save is writing (an edit made then
                        // would not be in the save; the planner also stays open if one slips in)
                        // and until Apple reminders' plans were read once (`PlanCacheState`).
                        VStack(spacing: 0) {
                            Rectangle().fill(Colors.separator).frame(height: 0.5)
                            timeline
                            Rectangle().fill(Colors.separator).frame(height: 0.5)
                            tray
                        }
                        .allowsHitTesting(!isLocked)
                        .opacity(isLocked ? 0.5 : 1)
                        .accessibilityHidden(isLocked)
                    }
                } else {
                    VStack(spacing: 0) {
                        header
                        if let storeError = store.error { storeErrorBanner(storeError) }
                        if let saveError { saveErrorBanner(saveError) }
                        pastDay
                    }
                }
            }
            .background(Colors.card)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.card, for: .navigationBar)
            .toolbar {
                if isEditable && isSaving {
                    ToolbarItem(placement: .confirmationAction) {
                        ProgressView()
                            .tint(Colors.accent)
                            .frame(width: 40, height: 40)
                            .accessibilityLabel("Saving plan")
                    }
                } else if isEditable {
                    SquareToolbarButton(systemImage: "checkmark", label: "Save plan", placement: .confirmationAction,
                                        isProminent: true, isDisabled: unsavedDayCount == 0 || isLocked) { save() }
                } else {
                    // Keeps the chevrons where they were while stepping into the past.
                    SquareToolbarPlaceholder(placement: .confirmationAction)
                }
                SquareToolbarButton(systemImage: "xmark", label: "Close", placement: .cancellationAction,
                                    isDisabled: isSaving) { close() }
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
        .task(id: day) {
            loadDay()
            // Apple data for the viewed day: its range in the shared fetch window, and the
            // sidecar's blocks. Both changes rebuild through `appleDataChanged`.
            await overlay.reload(for: .planner, display: PlannerDays.loadRange(for: day, calendar: Self.calendar),
                                 today: today)
            await planCache.refresh()
        }
        // Released on close so the overlay goes back to the other screens' windows.
        .onDisappear {
            Task { await overlay.reload(for: .planner, display: nil, today: Date()) }
        }
        .onChange(of: today) { _, _ in todayChanged() }
        .onChange(of: draft?.blocks) { _, _ in rebuildModel() }
        .onChange(of: store.reminders) { _, _ in rebuildModel() }
        .onChange(of: store.events) { _, _ in rebuildModel() }
        .onChange(of: overlay.snapshot) { _, _ in appleDataChanged() }
        .onChange(of: planCache.applePlans) { _, _ in appleDataChanged() }
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
    /// Stark's own blocks come from the store, Apple reminders' from `PlanCache`, each once.
    private func makeModel(blocks: [PlanBlock]?) -> DayPlanModel {
        let inputs = PlannerPlans.forModel(day: day, local: store.plans, apple: planCache.applePlans,
                                           draftBlocks: blocks, calendar: Self.calendar)
        let saved = PlannerPlans.all(local: store.plans, apple: planCache.applePlans)
        return DayPlanModel.make(day: day, events: store.events, reminders: store.reminders,
                                 plans: inputs.plans, today: today,
                                 plannedElsewhere: session.plannedElsewhere(of: day, saved: saved, today: today),
                                 apple: overlay.snapshot, sidecarPlans: inputs.sidecarPlans)
    }

    /// Shows `new`, moving the tray selection off a pane it no longer has (NO DATE after its last
    /// reminder was planned) to the day's own pane IN THE SAME UPDATE: set afterwards, the paged
    /// `TabView` has already clamped the selection to its last page (FUTURE, seen in the simulator).
    private func setModel(_ new: DayPlanModel) {
        let shown = TrayPane.shown(pane, among: TrayPane.panes(for: new))
        if shown != pane { pane = shown }
        model = new
    }

    /// A fresh draft from the saved plans (both stores) for the viewed, editable day.
    private func freshDraft() {
        let saved = makeModel(blocks: nil)
        draft = PlanDraft(model: saved, saved: PlannerPlans.saved(on: day, local: store.plans(on: day),
                                                                   apple: planCache.applePlans, calendar: Self.calendar))
        setModel(saved)
    }

    /// The Apple snapshot or the sidecar's blocks changed (the fetch for this day landed, a write
    /// elsewhere): a draft the owner has not touched is rebuilt from the saved plans, so Apple
    /// blocks that arrived late become editable; an edited draft keeps its edits (Apple blocks it
    /// never showed are still written back, as `PlanDraft.retained`).
    private func appleDataChanged() {
        guard isEditable, let current = draft else { return }
        if !current.hasChanges && session.draft(for: day) == nil && lift == nil && resize == nil {
            freshDraft()
        } else {
            rebuildModel()
        }
    }

    /// The tray's panes: the dated three, plus NO DATE while there are undated Apple reminders.
    var trayPanes: [TrayPane] {
        model.map { TrayPane.panes(for: $0) } ?? TrayPane.allCases
    }

    // MARK: Day stepping

    private var isEditable: Bool { PlannerDays.isEditable(day, today: today, calendar: Self.calendar) }

    /// No touches, stepping or saving: while a save writes, and until Apple reminders' plan blocks
    /// were read once (a draft built before has none, so saving it would wipe the day's Apple
    /// blocks; `PlanCacheState.allowsPlanEdits`).
    private var isLocked: Bool { isSaving || !planCache.state.allowsPlanEdits }

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
            setModel(makeModel(blocks: kept.blocksToSave))
        } else {
            freshDraft()
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

    /// The Day view's header: "November 16, 2026" (year in red) with the ‹ › chevrons, then the
    /// day word (TODAY / TOMORROW / weekday, blue on today) and, on an editable day, the
    /// done/planned summary, or VIEW ONLY on a past day.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                titleText
                    .font(Fonts.mono(30, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.leading, Spacing.md)
                    .padding(.trailing, Spacing.sm)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                chevron("‹", label: "Previous day") { step(-1) }
                chevron("›", label: "Next day") { step(1) }
            }
            .padding(.trailing, Spacing.sm)
            .frame(minHeight: 48)
            HStack(spacing: Spacing.sm) {
                Text(dayWord)
                    .font(Fonts.mono(15, weight: .semibold))
                    .foregroundStyle(Self.calendar.isDate(day, inSameDayAs: today) ? Colors.accent : Colors.textSecondary)
                if let detail = headerDetail {
                    Text(detail)
                        .font(Fonts.mono(13))
                        .foregroundStyle(Colors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.leading, Self.gutter)
            .frame(minHeight: 28, alignment: .leading)
            .padding(.bottom, Spacing.xs)
            .accessibilityElement(children: .combine)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var titleText: Text {
        Text(AgendaFormat.monthName(day) + " \(Self.calendar.component(.day, from: day)), ")
            .foregroundColor(Colors.text)
            + Text(String(Self.calendar.component(.year, from: day))).foregroundColor(Colors.yearRed)
    }

    /// VIEW ONLY on a past day; the done/planned summary on an editable one, when there is one.
    private var headerDetail: String? {
        guard isEditable else { return "VIEW ONLY" }
        return DayPlanModel.summary(done: model?.doneCount ?? 0, planned: draft?.blocks.count ?? 0)
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(Fonts.mono(22))
                .foregroundStyle(isLocked ? Colors.textSecondary : Colors.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityLabel(label)
    }

    /// A past day: the `DayHistory` numbers above the read-only timeline. No tray, no gestures.
    private var pastDay: some View {
        let history = DayHistory.make(day: day, events: store.events, reminders: store.reminders,
                                      plans: store.plans, today: today,
                                      apple: overlay.snapshot, sidecarPlans: planCache.applePlans)
        let week = DayHistory.weekStats(containing: day, reminders: store.reminders, plans: store.plans, today: today,
                                        apple: overlay.snapshot, sidecarPlans: planCache.applePlans)
        return VStack(spacing: 0) {
            PastDayHeader(history: history, weekStats: week)
            PastDayView(day: day, history: history)
        }
    }

    /// Done from the block menu: completes the block's OCCURRENCE through the router (EventKit,
    /// where a repeating reminder moves to its next date), then the block becomes a done block
    /// in the draft; the due date and the plan itself are untouched, and unsaved draft edits
    /// survive. A failed Apple write leaves the block open and shows the reason in the banner.
    func completeBlock(_ block: PlanBlock) {
        guard draft?.blocks.contains(where: { $0.id == block.id }) == true, let router else { return }
        Task {
            do {
                try await router.complete(id: block.reminderID, on: block.occurrence)
            } catch {
                saveError = error.routerMessage
                return
            }
            withAnimation(.easeOut(duration: 0.15)) { _ = draft?.markDone(id: block.id) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            rebuildModel()
        }
    }

    private func rebuildModel() {
        guard let draft else { return }
        // Everything the save would write, so the done blocks stay in the rebuilt model.
        setModel(makeModel(blocks: draft.blocksToSave))
    }

    var dayWord: String {
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

    /// A block's task title: Stark's own reminder, else the Apple reminder (`apple-<identifier>`).
    func title(ofReminder id: String) -> String {
        if let title = store.reminders.first(where: { $0.id == id })?.title { return title }
        if case .apple(let ref) = ItemOrigin(id: id, kind: .reminder),
           let title = overlay.snapshot.reminders.first(where: { $0.id == ref.identifier })?.title {
            return title
        }
        return "Task"
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

    /// ✓: writes every changed, still-editable day (never a past day) through the router (Apple
    /// reminders' blocks to the sidecar, Stark's own to the store). If every write succeeds the
    /// planner closes; otherwise it stays open with all drafts kept and a banner naming the
    /// failed days (and the last reason), and a retry rewrites the same blocks (a replace).
    /// While it writes, the timeline and tray take no touches; should an edit still land in that
    /// window, the planner stays open with it (`PlanSession.hasEdits(since:)`) instead of closing.
    private func save() {
        guard !isSaving, planCache.state.allowsPlanEdits, let router else { return }
        syncSession()
        endLift()
        actionBlock = nil
        timePick = nil
        isSaving = true
        let written = session
        Task {
            var reason: String?
            let failed = await written.saveAll(today: today, writing: { day, blocks in
                do {
                    try await router.replacePlans(on: day, with: blocks)
                    return true
                } catch {
                    reason = error.routerMessage
                    return false
                }
            })
            isSaving = false
            if failed.isEmpty {
                syncSession()
                if session.hasEdits(since: written, today: today) {
                    saveError = "Saved. Changes made while saving are not saved yet: tap the check again."
                } else {
                    saveError = nil
                    dismiss()
                }
            } else {
                let days = failed.map { Self.titleFormatter.string(from: $0) }.joined(separator: ", ")
                saveError = "Could not save the plan for \(days)" + (reason.map { ". \($0)" } ?? "")
            }
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
        rebuildModel()
        guard !isEditable else { return }
        endLift()
        actionBlock = nil
        timePick = nil
        draft = nil
        model = nil
    }
}
