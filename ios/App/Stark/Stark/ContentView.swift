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
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAdd = false
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
    /// The day last reported by `AgendaView.onDayInView` (issue #101) — read only by
    /// `MonthGridView`'s `scrollPagingDate`, to page the month grid as the agenda scrolls. A fresh
    /// `GridPagingRequest` every time (even for a repeated date) so scroll always wins over an
    /// independent chevron browse — see `GridPagingRequest`'s doc comment in `MonthGridView.swift`.
    @State private var scrollPagingDate: GridPagingRequest?

    init() {
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
        .preferredColorScheme(.dark)
    }

    /// The grid, drag bar (iPhone only — Mac drives `mode` from `CalendarSidebar` instead),
    /// separator and agenda, or the year overlay in year mode; plus every modifier that used to
    /// hang off the old single `NavigationStack` body (background, toolbar, sheets, load-on-
    /// appear, foreground/day-rollover handling). Identical between platforms except the missing
    /// `ModeHandle` row on Mac.
    private var screenContent: some View {
        VStack(spacing: 0) {
            if let error = store.error {
                Button {
                    store.error = nil
                } label: {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Colors.text)
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Colors.accent)
                }
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
                    AgendaView(today: today, anchor: agendaAnchor, scrollRequest: scrollRequest, onSelect: { selectedItem = $0 }, onDayInView: dayScrolledIntoView)
                }
                // Hidden (not removed) in year mode: tearing the agenda down would lose its
                // scroll position and, on coming back, scroll to today instead of the day
                // picked in the year. Not tappable or readable by VoiceOver while hidden.
                .opacity(mode == .year ? 0 : 1)
                .allowsHitTesting(mode != .year)
                .accessibilityHidden(mode == .year)

                if mode == .year {
                    YearView(today: today, selectedDate: selectedDate, mode: $mode) { date in
                        selectDate(date)
                        withAnimation(.easeInOut(duration: 0.2)) { mode = .month }
                    }
                    .transition(.opacity)
                }
            }
        }
        .background(Colors.background)
        // A floating action button (Fantastical-style) instead of a nav-bar "Add" button,
        // which read as too much real-estate on the iPhone's title bar. Square, not circular —
        // this app has no rounded corners anywhere else (Braun/Bauhaus), so a circular FAB
        // would be the one exception. Overlaid on the whole screen (not just the agenda), so
        // it stays reachable and visible even in year mode, above the YearView overlay.
        .overlay(alignment: .bottomTrailing) { addButton }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showAdd) { AddItemView() }
        .sheet(item: $selectedItem) { item in EditItemView(item: item) }
        .task {
            // Load the wider window (includes the overdue lookback), not the display window.
            let range = AgendaWindow.loadRange(around: Date())
            store.start(windowStart: range.lowerBound, windowEnd: range.upperBound)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.retryPendingWrites()
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

    /// Square (hard-edged, matching the rest of the app), accent-filled, no shadow or glass
    /// effect — flat like `FlatToolbarButton`. 56pt is the usual floating-action-button minimum
    /// touch target, padded off the corner so it never sits flush against the screen edge.
    private var addButton: some View {
        Button {
            showAdd = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Colors.background)
                .frame(width: 56, height: 56)
                .background(Colors.accent)
        }
        .buttonStyle(.plain)
        .padding(Spacing.lg)
        .accessibilityLabel("Add")
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
        agendaAnchor = newAnchor
        selectedDate = newAnchor
        scrollRequest = ScrollRequest(date: newAnchor)
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
    /// that exists.
    private func selectDate(_ date: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let tapped = calendar.startOfDay(for: date)
        let window = AgendaWindow.range(around: agendaAnchor)
        // Day granularity: the window runs from the start of its first day to the last second
        // of its last, while a tapped day is a noon timestamp, so compare whole days.
        let firstDay = calendar.startOfDay(for: window.lowerBound)
        let lastDay = calendar.startOfDay(for: window.upperBound)
        if tapped < firstDay || tapped > lastDay {
            store.loadMonths(covering: AgendaWindow.range(around: date))
            agendaAnchor = date
        }
        selectedDate = date
        scrollRequest = ScrollRequest(date: date)
    }
}
