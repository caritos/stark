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
