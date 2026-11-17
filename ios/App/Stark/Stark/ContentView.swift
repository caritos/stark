//
//  ContentView.swift
//  Stark
//
//  Created by Eladio Caritos on 9/17/26.
//

import SwiftUI
import StarkKit

/// One screen: the calendar grid on top (one week row when collapsed, the month grid otherwise),
/// a drag bar that switches between the week, month and year modes, and the day-grouped agenda
/// filling the rest. In year mode the year view (twelve mini-months, with its own drag bar) covers
/// the grid and the agenda; the agenda stays in the hierarchy underneath, hidden, so it keeps its
/// scroll position and pending completions and can scroll to a day picked in the year.
struct ContentView: View {
    @EnvironmentObject private var store: PlannerStore
    @EnvironmentObject private var pending: PendingCompletions
    @Environment(AppleOverlayModel.self) private var overlay
    @Environment(DefaultDestinationModel.self) private var destinations
    @Environment(NoticeCenter.self) private var notices
    @Environment(ImportModel.self) private var importModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAdd = false
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showCalendars = false
    @State private var showViewMenu = false
    @State private var selectedItem: AgendaItem?
    @State private var selectedDate: Date
    @State private var scrollRequest: ScrollRequest?
    /// The date the agenda's display window (`AgendaWindow.range(around:)`) is centred on:
    /// today, until a grid tap outside that window re-centres it.
    @State private var agendaAnchor: Date
    /// The "today" the screen was last drawn for. It is state, and handed to the grid and the
    /// agenda, so that when the calendar day changes (see `followCalendarDay`) they re-render
    /// and highlight the new today rather than reading `Date()` once and going stale.
    @State private var today: Date
    /// How much calendar the grid shows. Always starts as the month grid; not persisted.
    @State private var mode: CalendarMode = .month
    /// The full-screen Month or Quarter (view menu) shown over the DayTicker. A screen state, not
    /// a `CalendarMode`: the mode underneath stays week or month, so leaving it returns to it.
    @State private var full: FullScreenCalendar = .none
    /// The day last reported by `AgendaView.onDayInView` (issue #101) — read only by
    /// `MonthGridView`'s `scrollPagingDate`, to page the month grid as the agenda scrolls. A fresh
    /// `GridPagingRequest` every time (even for a repeated date) so scroll always wins over an
    /// independent chevron browse — see `GridPagingRequest`'s doc comment in `MonthGridView.swift`.
    @State private var scrollPagingDate: GridPagingRequest?
    /// The day the planner (timeboxing) is open for, presented full screen; nil when closed.
    @State private var planRequest: PlanRequest?
    /// Bumped on every agenda window move, so a move still waiting for its Apple fetch is
    /// dropped when a newer one (or a tap inside the window) comes first.
    @State private var windowMoveToken = 0

    private let bridge: ClaudeBridge
    private let secrets: SecretStore
    /// False until the default calendar and list have been resolved (`destinations.refresh()`); a
    /// bridge URL that arrives earlier (cold launch) waits in `pendingBridgeURLs`, or it would be
    /// rejected for want of a destination. Drained once, right after. The local store's state does
    /// not matter: bridge items go to Apple and their idempotency lives in the sidecar ledger.
    @State private var bridgeReady = false
    @State private var pendingBridgeURLs: [URL] = []
    /// Set by Add's "Open Settings": Settings opens once the Add sheet has gone.
    @State private var openSettingsAfterAdd = false

    init(bridge: ClaudeBridge, secrets: SecretStore) {
        self.bridge = bridge
        self.secrets = secrets
        // One instant for all three, so a launch right at midnight can't split them across days.
        let now = Date()
        _selectedDate = State(initialValue: now)
        _agendaAnchor = State(initialValue: now)
        _today = State(initialValue: now)
    }

    var body: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            NavigationSplitView {
                CalendarSidebar(mode: $mode)
            } detail: {
                screenContent
            }
            #else
            NavigationStack {
                screenContent
            }
            #endif
        }
        .tint(Colors.accent)
        // The design is dark-only (Colors.* are dark-theme tokens); without this, system
        // sheets and Forms would render light with near-white text.
        .onOpenURL { url in
            if bridgeReady {
                handleBridge(url)
            } else {
                pendingBridgeURLs.append(url)
            }
        }
    }

    /// The grid, drag bar (iPhone only — Mac drives `mode` from `CalendarSidebar` instead),
    /// separator and agenda, or the year overlay in year mode; plus every modifier that used to
    /// hang off the old single `NavigationStack` body (background, toolbar, sheets, load-on-
    /// appear, foreground/day-rollover handling). Identical between platforms except the missing
    /// `ModeHandle` row on Mac.
    private var screenContent: some View {
        VStack(spacing: 0) {
            if let notice = notices.text {
                Button {
                    notices.dismiss()
                } label: {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Colors.text)
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Colors.separator)
                }
            }
            if let error = store.error {
                Button {
                    store.error = nil
                } label: {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Colors.accent)
                }
            }
            // Without full access Stark cannot show or keep Apple items: say why and ask (or point
            // to iOS Settings) instead of showing an empty calendar. Stark's own local items stay
            // visible below.
            if overlay.access != .granted {
                AccessRequiredView()
            } else if let problem = destinations.error {
                Button {
                    showSettings = true
                } label: {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Colors.accent)
                }
                .accessibilityHint("Opens Settings.")
            }
            ZStack {
                VStack(spacing: 0) {
                    MonthGridView(today: today, mode: mode, selectedDate: selectedDate, onSelectDate: selectDate, scrollPagingDate: scrollPagingDate)
                    #if !targetEnvironment(macCatalyst)
                    ModeHandle(mode: $mode)
                    #endif
                    Rectangle()
                        .fill(Colors.separator)
                        .frame(height: 1)
                    AgendaView(today: today, anchor: agendaAnchor, scrollRequest: scrollRequest, onSelect: { selectedItem = $0 }, onDayInView: dayScrolledIntoView,
                               onPlan: { planRequest = PlanRequest(day: $0) })
                }
                // Hidden (not removed) in year mode: tearing the agenda down would lose its
                // scroll position and, on coming back, scroll to today instead of the day
                // picked in the year. Not tappable or readable by VoiceOver while hidden.
                .opacity(coversAgenda ? 0 : 1)
                .allowsHitTesting(!coversAgenda)
                .accessibilityHidden(coversAgenda)

                if mode == .year {
                    YearView(today: today, selectedDate: selectedDate, mode: $mode) { date in
                        selectDate(date)
                        withAnimation(.easeInOut(duration: 0.2)) { mode = .month }
                    }
                    .transition(.opacity)
                } else if full == .month {
                    // Same slot and rules as the year: the agenda stays underneath, hidden, and a
                    // day tap lands on the DayTicker scrolled to that day.
                    FullMonthView(today: today, selectedDate: selectedDate, onSelectDate: leaveFullScreen)
                        .transition(.opacity)
                } else if full == .quarter {
                    FullQuarterView(today: today, selectedDate: selectedDate, onSelectDate: leaveFullScreen)
                        .transition(.opacity)
                } else if full == .day {
                    FullDayView(today: today, selectedDate: selectedDate, onSelectDate: leaveFullScreen,
                                onOpenItem: { selectedItem = $0 })
                        .transition(.opacity)
                } else if full == .week {
                    FullWeekView(today: today, selectedDate: selectedDate, onSelectDate: leaveFullScreen,
                                 onOpenItem: { selectedItem = $0 })
                        .transition(.opacity)
                }
            }
        }
        .background(Colors.background)
        // Year mode (the Mac sidebar) leaves the full Month or Quarter; the menu's own choices
        // already set both together.
        .onChange(of: mode) { _, newMode in if newMode == .year { full = .none } }
        // Fantastical-style floating bottom bar instead of a nav-bar "Add" button. Overlaid on the
        // whole screen (not just the agenda), so it stays reachable in year mode too. The agenda
        // and the year view reserve `FloatingBottomBar.clearance` so their last rows clear it.
        .overlay(alignment: .bottom) {
            FloatingBottomBar(mode: mode,
                              full: full,
                              showViewMenu: $showViewMenu,
                              viewMenu: {
                                  ViewMenu(current: CalendarViewMenu.current(for: mode, full: full),
                                           onChoose: { choice in
                                               showViewMenu = false
                                               withAnimation(.easeInOut(duration: 0.2)) {
                                                   let target = CalendarViewMenu.target(after: choice, current: mode)
                                                   mode = target.mode
                                                   full = target.full
                                               }
                                           },
                                           onSettings: {
                                               showViewMenu = false
                                               // Present Settings after the popover has gone.
                                               Task {
                                                   try? await Task.sleep(nanoseconds: 300_000_000)
                                                   showSettings = true
                                               }
                                           })
                              },
                              onCalendars: { showCalendars = true },
                              onSearch: { showSearch = true },
                              onAdd: { showAdd = true })
        }
        // No navigation title and, since the bottom bar replaced the toolbar Add button above, no
        // toolbar content either -- an empty nav bar was still reserving its full height,
        // showing as a band of dead space above the month grid. Hidden entirely; this screen
        // never pushes further destinations from itself (Add/Edit are sheets, not pushes), so
        // nothing relies on the bar being there.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAdd, onDismiss: {
            if openSettingsAfterAdd {
                openSettingsAfterAdd = false
                showSettings = true
            }
        }) {
            AddItemView(onOpenSettings: {
                openSettingsAfterAdd = true
                showAdd = false
            })
        }
        .sheet(isPresented: $showSearch) { SearchView() }
        .sheet(isPresented: $showCalendars) { CalendarsSheet() }
        .sheet(isPresented: $showSettings) {
            SettingsView(secrets: secrets).interactiveDismissDisabled(importModel.isRunning)
        }
        .sheet(item: $selectedItem) { item in AgendaItemDetailSheet(item: item, today: today) }
        .fullScreenCover(item: $planRequest) { request in PlannerView(day: request.day, today: today) }
        .task {
            // Load the wider window (includes the overdue lookback), not the display window.
            let range = AgendaWindow.loadRange(around: Date())
            store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
            // Hide items already imported into Apple and mark the ones that can't be, before the
            // first Apple fetch (so an imported item never shows twice for long).
            await importModel.refreshStatus()
            // Empty (and no EventKit call) until access was granted from `AccessRequiredView`.
            await overlay.reload(for: .agenda, display: AgendaWindow.range(around: agendaAnchor), today: today)
            await destinations.refresh()
            bridgeReady = true
            let waiting = pendingBridgeURLs
            pendingBridgeURLs = []
            for url in waiting { handleBridge(url) }
        }
        // Granted from the access screen, or in iOS Settings while Stark was in the background.
        .onChange(of: overlay.access) { _, access in
            if access == .granted { Task { await destinations.refresh() } }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.retryPendingWrites()
                Task { await overlay.refresh(today: today) }
                followCalendarDay()
            } else {
                // The undo window's timer doesn't survive the app being suspended or
                // killed, so commit any still-pending completions on the way out.
                pending.flush()
            }
        }
        // Midnight, or the clock / timezone changed, while the app is in the foreground.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            followCalendarDay()
        }
    }

    /// The year or any full-screen calendar (Day, Week, Month, Quarter) covers the grid and agenda (which stay alive
    /// underneath).
    private var coversAgenda: Bool { mode == .year || full != .none }

    /// A day tapped in the full Month or Quarter (or Day's weekday): select it and return to the DayTicker there.
    private func leaveFullScreen(to date: Date) {
        selectDate(date)
        // The mode does not change here (unlike leaving the year), so page the month grid to the
        // tapped day's month explicitly.
        scrollPagingDate = GridPagingRequest(date: date)
        withAnimation(.easeInOut(duration: 0.2)) { full = .none }
    }

    /// The bridge handles URLs one at a time in arrival order, so these tasks may overlap.
    private func handleBridge(_ url: URL) {
        Task {
            let outcome = await bridge.handle(url)
            if let text = outcome.notice { notices.show(text) }
            // EKEventStoreChanged is not reliable after a save (write spike f).
            if case .added = outcome { await overlay.refreshAfterWrite() }
        }
    }

    /// The calendar may have moved on (app foregrounded, midnight passed, clock or timezone
    /// changed). On a new day, `today` always advances; the window only follows if it was still
    /// centred on the old today (`AgendaWindow.refreshedAnchor` decides) — a window the user
    /// deliberately re-centred elsewhere is left alone. Following loads the months the new window
    /// needs *before* switching to it, then selects and scrolls to the new today.
    private func followCalendarDay() {
        let now = Date()
        guard !Calendar(identifier: .gregorian).isDate(now, inSameDayAs: today) else { return }
        let newAnchor = AgendaWindow.refreshedAnchor(current: agendaAnchor, lastSeenToday: today, now: now)
        let wasFollowing = newAnchor != agendaAnchor
        today = now
        guard wasFollowing else { return }
        store.loadMonths(covering: AgendaWindow.loadRange(around: newAnchor))
        moveAgendaWindow(to: newAnchor) {
            agendaAnchor = newAnchor
            selectedDate = newAnchor
            scrollRequest = ScrollRequest(date: newAnchor)
        }
    }

    /// Re-centres the agenda window on `anchor` once the Apple overlay has fetched the new display
    /// range (the store's months must already be loaded), so the window never shows a range
    /// before its Apple items are in. `move` sets the anchor and the scroll request together.
    /// With the overlay off or not granted the snapshot cannot change, so `move` runs at once,
    /// exactly as before the overlay; the new range is still recorded for a later reload.
    private func moveAgendaWindow(to anchor: Date, move: @escaping () -> Void) {
        windowMoveToken += 1
        let token = windowMoveToken
        let range = AgendaWindow.range(around: anchor)
        guard overlay.isActive else {
            move()
            Task { await overlay.reload(for: .agenda, display: range, today: today) }
            return
        }
        Task {
            await overlay.reload(for: .agenda, display: range, today: today)
            guard token == windowMoveToken else { return }
            move()
        }
    }

    /// A day scrolled into view at the top of the agenda list (`AgendaView.onDayInView`,
    /// issue #101). Always updates the highlighted/selected day — which alone makes week mode
    /// page, since `MonthGridView` already derives its week row from `selectedDate` — and
    /// separately reports it as `scrollPagingDate`, which `MonthGridView` uses to page the month
    /// grid (month mode only). Never issues a new `scrollRequest`: the agenda is already scrolled
    /// there by the user, so re-scrolling it here would fight the user's own scroll.
    private func dayScrolledIntoView(_ date: Date) {
        selectedDate = date
        scrollPagingDate = GridPagingRequest(date: date)
    }

    /// A day was tapped in the month grid: scroll the agenda to that day's header. A day outside
    /// the agenda's current display window has no section yet, so first re-centre the window on
    /// it, loading the months the new window covers *before* switching, or items in months not
    /// yet read would silently vanish. A day already inside the window never re-centres.
    ///
    /// The re-centre and the scroll request are set in the same transaction, so `AgendaView`
    /// sees the new window and the request together and its (deferred) scroll targets a header
    /// that exists. With the Apple overlay on, that transaction waits for the overlay's fetch
    /// (`moveAgendaWindow`).
    private func selectDate(_ date: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let tapped = calendar.startOfDay(for: date)
        let window = AgendaWindow.range(around: agendaAnchor)
        // Day granularity: the window runs from the start of its first day to the last second
        // of its last, while a tapped day is a noon timestamp, so compare whole days.
        let firstDay = calendar.startOfDay(for: window.lowerBound)
        let lastDay = calendar.startOfDay(for: window.upperBound)
        selectedDate = date
        if tapped < firstDay || tapped > lastDay {
            store.loadMonths(covering: AgendaWindow.range(around: date))
            moveAgendaWindow(to: date) {
                agendaAnchor = date
                scrollRequest = ScrollRequest(date: date)
            }
        } else {
            // Supersedes a re-centre still waiting for its Apple fetch.
            windowMoveToken += 1
            scrollRequest = ScrollRequest(date: date)
        }
    }
}

/// Which day the planner was opened for (`.fullScreenCover(item:)` needs an `Identifiable`).
private struct PlanRequest: Identifiable {
    let day: Date
    var id: Date { day }
}
