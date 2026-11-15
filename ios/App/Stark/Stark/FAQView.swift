// ios/App/Stark/Stark/FAQView.swift
import SwiftUI

/// A short, static list of frequently asked questions, embedded in the app itself (opened from
/// Settings) rather than linking out to the website's /support page — available without a
/// network connection, like the rest of the app. Add entries here as they come up; there is no
/// mechanism to fetch or update this remotely by design (matches the app's local-first stance).
struct FAQView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private static let entries: [Entry] = [
        Entry(
            question: "Can I tag people, projects, or labels in a task?",
            answer: """
            Yes — just type the tag anywhere in the title or notes. +project and @context are \
            todo.txt's own standard tags; %label and ~person are free-form ones Stark also \
            understands, for whatever categories or people you want to track (e.g. "Call mom \
            ~mom %family"). As you type a tag, Stark suggests matching ones you've already used \
            elsewhere, so you don't have to remember your own spelling.
            """
        ),
        Entry(
            question: "How do I plan my day?",
            answer: """
            Tap the calendar-clock button next to TODAY or TOMORROW in the agenda to open Plan. \
            Drag tasks from the tray onto the timeline, resize a block with its bottom edge, \
            then tap the check to save. Planning never changes a task's due date: a task you do \
            not finish keeps its original due date. The arrows in the header step to another \
            day, so a whole week can be planned, and past days are shown view only with what \
            got done and what was missed.
            """
        ),
        Entry(
            question: "Can I turn an event into a task?",
            answer: """
            Yes. Open the event, use the Event/Reminder switch at the top and tap the check. The \
            event's end time is dropped, its location and URL move into the task's notes, and any \
            attended/skipped marks are dropped (Stark asks first). It works the other way round \
            too: a task becomes an event, and its priority is dropped.
            """
        ),
        Entry(
            question: "Does Stark use my Apple Calendar and Reminders?",
            answer: """
            Yes. Stark shows your Calendar events and Reminders in the agenda, the month and \
            year dots and Search, and saves what you add, edit, complete or delete in Stark to \
            Calendar and Reminders. iOS asks for access the first time you tap Allow Access on \
            Stark's main screen, after Stark says what it is for. New events go to your default \
            calendar and new to-dos to your default list; choose them in Settings > Apple \
            Calendar and Reminders, where you also choose which calendars and lists show (the \
            default ones always show). If you use iCloud, it syncs these items like any other \
            calendar item; Stark itself sends nothing anywhere and adds no network connection. \
            Reminders without a date are not shown in the agenda. The day export, for today and \
            yesterday, includes the Apple items shown that day. Stark's own older items stay \
            stored separately, and an item that exists in both places appears twice.
            """
        ),
        Entry(
            question: "What is the Claude Code bridge?",
            answer: """
            An optional way to add tasks and events from Claude Code on your Mac. It does \
            nothing until you pair it (Settings > Claude Code). Stark makes no network \
            connection for this: the Mac talks to your phone over your USB or Wi-Fi link to \
            the phone. A stark://add link is only accepted when it is signed with the pairing \
            secret. The secret is kept in this phone's Keychain (not in backups) and, once you \
            pair, in your Mac's login Keychain; Stark never sends it anywhere else. Requests \
            are added immediately when you tell Claude to add them. When you ask Claude for \
            your schedule, the Mac reads a temporary copy of your Stark data over the cable or \
            Wi-Fi link to the phone, the copy is deleted afterwards, and Claude Code sees that \
            day's items. To reset pairing, tap Settings > Claude Code > Reset pairing.
            """
        ),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.entries) { entry in
                    Section {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(entry.question)
                                .fontWeight(.semibold)
                                .foregroundStyle(Colors.text)
                            Text(entry.answer)
                                .font(.footnote)
                                .foregroundStyle(Colors.textSecondary)
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                    .listRowBackground(Colors.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Colors.background)
            .listRowSeparatorTint(Colors.separator)
            .navigationTitle("FAQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SquareToolbarButton(systemImage: "xmark", label: "Close", placement: .cancellationAction) { dismiss() }
            }
        }
        .tint(Colors.accent)
        .preferredColorScheme(.dark)
    }
}
