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
            question: "Where are my events and to-dos kept?",
            answer: """
            In Apple Calendar and Reminders. What you add in Stark is created there (new events \
            in your default calendar, new to-dos in your default list; choose them in Settings > \
            Apple Calendar and Reminders, where you also choose which calendars and lists show; \
            the default ones always show), and editing, completing or deleting in Stark changes \
            them there. If you use iCloud, Apple syncs them to your other devices; Stark itself \
            sends nothing anywhere and adds no network connection. iOS asks for access the first \
            time you tap Allow Access on Stark's main screen, after Stark says what it is for. \
            Planner blocks for Apple reminders and attended/skipped marks on Apple events are kept \
            in a small file of Stark's own on this device. The day export (today and \
            yesterday) and the Weekly Review share include the Apple items they show.
            """
        ),
        Entry(
            question: "What about the items I made in Stark before?",
            answer: """
            They stay in Stark's own files on this device, and Stark still shows them and lets you \
            change them. Nothing was moved or deleted; a later update will offer to move them into \
            Apple Calendar and Reminders. Until then an item that exists in both places appears twice.
            """
        ),
        Entry(
            question: "Why can't I change some items?",
            answer: """
            Items on calendars you cannot change (such as holidays or a calendar shared with you \
            read-only) and events you were invited to are read-only in Stark. Open them in \
            Calendar or Reminders to change them.
            """
        ),
        Entry(
            question: "How do repeating reminders work?",
            answer: """
            As in Apple's Reminders: completing one moves it to its next date, and Apple keeps a \
            separate completed copy for each completion. Done on an overdue one records one \
            completion and moves it to its next date after now; missed dates in between are not \
            recorded. There is no "skip this occurrence" for reminders, and reopening a completed \
            copy does not move the reminder back. A monthly item on day 29, 30 or 31, or a yearly \
            one on February 29, is skipped in months without that day; choose "Last day of the \
            month" to land on the last day instead. To drop one date of a repeating event, open it \
            and tap Remove This Occurrence.
            """
        ),
        Entry(
            question: "Where are reminders without a date?",
            answer: """
            Not in the agenda. They are in Search and in the planner's NO DATE pane; once you plan \
            one onto a day it appears in that day's agenda. Add Date in the reminder sets today, \
            all day.
            """
        ),
        Entry(
            question: "Can I tag people, projects, or labels in a task?",
            answer: """
            Yes — just type the tag anywhere in the title or notes. +project and @context are \
            todo.txt's own standard tags; %label and ~person are free-form ones Stark also \
            understands, for whatever categories or people you want to track (e.g. "Call mom \
            ~mom %family"). As you type a tag, Stark suggests matching ones you've already used \
            in the items it has loaded, Apple items included, so you don't have to remember your \
            own spelling.
            """
        ),
        Entry(
            question: "How do I plan my day?",
            answer: """
            Tap the calendar-clock button next to TODAY or TOMORROW in the agenda to open Plan. \
            Drag tasks from the tray onto the timeline, resize a block with its bottom edge, \
            then tap the check to save. The tray includes your Apple reminders and a NO DATE \
            pane. Planning never changes a task's due date: a task you do not finish keeps its \
            original due date. The arrows in the header step to another day, so a whole week \
            can be planned, and past days are shown view only with what got done and what was \
            missed. Weekly Review counts Apple reminders in the week they were completed and \
            Stark's older ones in the week they were due.
            """
        ),
        Entry(
            question: "Can I turn an event into a task?",
            answer: """
            Yes. Open the event, use the Event/Reminder switch at the top and tap the check. The \
            event's end time is dropped, its location moves into the task's notes, and, for \
            Stark's older events, any attended/skipped marks are dropped (Stark asks first). It works the other way round \
            too: a task becomes an event, and its priority is dropped. For an Apple item Stark \
            creates the other kind and deletes the original, so its alerts, invitees and any \
            occurrences edited one by one are lost; Stark asks first when the event has invitees \
            (they may be notified), and an item whose repeat Stark can't copy can't be converted.
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
            are added immediately to Apple Calendar and Reminders, in your default calendar and \
            list, and Stark notes each added item in its small file so that sending the same \
            request again does not normally add it twice; an item Stark added to Apple and you then deleted there stays deleted. Claude Code cannot read your schedule from the phone for now: stark-claude \
            today is unavailable until a Mac tool exists. To reset pairing, tap Settings > \
            Claude Code > Reset pairing.
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
                    .listRowBackground(Colors.card)
                }
            }
            .listStyle(.insetGrouped)
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
    }
}
