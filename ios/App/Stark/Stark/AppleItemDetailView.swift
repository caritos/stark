// ios/App/Stark/Stark/AppleItemDetailView.swift
import SwiftUI
import StarkKit

/// What a tapped agenda / Search / Weekly Review row opens: Stark's edit sheet, the Apple editor
/// (a row in a writable calendar or list), or the read-only Apple detail. The routing is
/// `AgendaItemDetail` (StarkKit), so a read-only item can never be handed to `EditItemView`.
struct AgendaItemDetailSheet: View {
    let item: AgendaItem
    /// The real today, for an overdue reminder's "N days overdue" suffix; nil shows none.
    var today: Date? = nil

    var body: some View {
        switch AgendaItemDetail(item) {
        case .edit(let editable): EditItemView(item: editable)
        case .editableApple(let row, let ref): AppleItemEditor(row: row, ref: ref, today: today)
        case .readOnly(let readOnly): AppleItemDetailView(item: readOnly, today: today)
        }
    }
}

/// Opens a writable Apple item for editing: loads the REAL stored item (`ItemRouter.details`, with
/// its repeat rule and write permission; never the overlay's stand-in) and, for an event, its
/// attended/skipped mark for the tapped day. A spinner shows until it arrives; a failure shows its
/// message and a Close button. An item the owner can't edit after all (an invitee-only event, a
/// calendar that turned read-only) opens the read-only detail (`AppleEditorState`).
struct AppleItemEditor: View {
    @Environment(\.itemRouter) private var router
    @Environment(\.dismiss) private var dismiss
    let row: AgendaItem
    let ref: AppleItemRef
    var today: Date? = nil

    private enum Phase {
        case loading
        case failed(String)
        case loaded(AppleEditorState, AgendaItem)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                placeholder {
                    ProgressView()
                        .tint(Colors.accent)
                        .accessibilityLabel("Loading the item")
                }
            case .failed(let message):
                placeholder {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Colors.text)
                        .padding(Spacing.md)
                }
            case .loaded(.edit(let details), let item):
                EditItemView(item: item, details: details)
            case .loaded(.readOnly, let item):
                AppleItemDetailView(item: item, today: today)
            }
        }
        .task { await load() }
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            VStack {
                Spacer()
                content()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Colors.background)
            .navigationTitle(ref.kind == .event ? "Event" : "Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbar {
                SquareToolbarButton(systemImage: "xmark", label: "Close", placement: .cancellationAction) { dismiss() }
            }
        }
        .tint(Colors.accent)
    }

    private func load() async {
        guard case .loading = phase else { return }
        guard let router else {
            phase = .failed("This item couldn't be loaded for editing. Close it and try again.")
            return
        }
        let id = ItemOrigin.modelID(for: ref)
        do {
            let details = try await router.details(id: id, kind: ref.kind)
            // The mark is Stark's own (sidecar); an unreadable sidecar only hides it.
            var outcome: EventOutcome?
            if ref.kind == .event { outcome = (try? await router.eventOutcome(id: id, on: row.occurrence)) ?? nil }
            let state = AppleEditorState(details: details)
            // The read-only detail keeps the row as the agenda showed it (the occurrence's times).
            phase = .loaded(state, state == .readOnly ? row : row.withStoredItem(details, outcome: outcome))
        } catch {
            phase = .failed(error.routerMessage)
        }
    }
}

/// Read-only detail for an Apple Calendar / Reminders overlay item: title, date and time,
/// location, URL, notes and the calendar it comes from. It has no edit, complete, skip, plan or
/// convert controls and never touches `PlannerStore`; the only action opens the item in Apple's
/// own app (`appleOpenURL`).
struct AppleItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let item: AgendaItem
    var today: Date? = nil

    private var source: AppleSource? { item.appleSource }

    private var notes: String? {
        let text: String?
        switch item.kind {
        case .event(let event): text = event.notes
        case .reminder(let reminder): text = reminder.notes
        }
        return text.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var location: String? {
        guard case .event(let event) = item.kind, let location = event.location, !location.isEmpty else { return nil }
        return location
    }

    private var urlText: String? { appleItemURL(item) }

    /// Only an http/https link with a host is offered as a tappable link (as in `EditItemView`).
    private var webLink: URL? {
        guard let urlText,
              let link = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = link.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = link.host(percentEncoded: false), !host.isEmpty
        else { return nil }
        return link
    }

    /// The day line, e.g. "Monday, Nov 16". An overdue reminder's time line already names its
    /// missed date, so it gets no separate day line.
    private var dayLine: String? {
        if item.isOverdue { return nil }
        // An undated reminder's occurrence is a sentinel, never shown.
        if item.isUndatedApple { return AgendaItem.noDateText }
        return "\(AgendaFormat.weekdayName(item.occurrence)), \(AgendaFormat.monthDay(item.occurrence))"
    }

    private var openTitle: String {
        source?.isReminder == true ? "Open in Reminders" : "Open in Calendar"
    }

    var body: some View {
        // The agenda row's own time line, so the detail reads exactly like the row (an overdue
        // reminder keeps the accent "Sep 19 at 6:00 AM · 3 days overdue").
        let timeLine = AgendaRowView(item: item, today: today).timeLine
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(item.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(item.isCompleted ? Colors.textSecondary : Colors.text)
                            .strikethrough(item.isCompleted)
                        if let dayLine {
                            Text(dayLine)
                                .font(Fonts.mono(13))
                                .foregroundStyle(Colors.textSecondary)
                        }
                        if let timeLine {
                            Text(timeLine.text)
                                .font(Fonts.mono(13))
                                .foregroundStyle(timeLine.isAccent ? Colors.accent : Colors.textSecondary)
                        }
                        if item.isCompleted {
                            Text("Completed")
                                .font(Fonts.mono(13))
                                .foregroundStyle(Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
                .listRowBackground(Colors.background)

                if location != nil || urlText != nil || notes != nil {
                    Section {
                        if let location { field("Location", location) }
                        if let webLink {
                            field("URL") {
                                Link(urlText ?? webLink.absoluteString, destination: webLink)
                                    .foregroundStyle(Colors.accent)
                            }
                        } else if let urlText {
                            field("URL", urlText)
                        }
                        if let notes { field("Notes", notes) }
                    }
                    .listRowBackground(Colors.background)
                }

                if let source {
                    Section {
                        field(source.isReminder ? "List" : "Calendar") {
                            AppleSourceLabel(source: source, font: .body)
                        }
                        Text("Read only. Change it in \(source.isReminder ? "Reminders" : "Calendar").")
                            .font(.footnote)
                            .foregroundStyle(Colors.textSecondary)
                    }
                    .listRowBackground(Colors.background)
                }

                if let link = appleOpenURL(for: item) {
                    Section {
                        // Not verified on a device yet (plan Task 9): remove if it does not open the app.
                        Button(openTitle) { openURL(link) }
                            .foregroundStyle(Colors.accent)
                    }
                    .listRowBackground(Colors.background)
                }
            }
            // Flat list rows (not inset-grouped rounded cards) to keep hard edges.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Colors.background)
            .listRowSeparatorTint(Colors.separator)
            .navigationTitle(source?.isReminder == true ? "Reminder" : "Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbar {
                SquareToolbarButton(systemImage: "xmark", label: "Close", placement: .cancellationAction) { dismiss() }
            }
        }
        .tint(Colors.accent)
    }

    private func field(_ label: String, _ value: String) -> some View {
        field(label) {
            Text(value)
                .foregroundStyle(Colors.text)
                .textSelection(.enabled)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Fonts.mono(11))
                .foregroundStyle(Colors.textSecondary)
            content()
        }
        .padding(.vertical, Spacing.xs)
    }
}
