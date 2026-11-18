// ios/App/Stark/Stark/FAQView.swift
import SwiftUI

/// A short, static list of frequently asked questions, embedded in the app itself (opened from
/// Settings) rather than linking out to the website's /support page — available without a
/// network connection unless the optional weather forecast is switched on. Add entries here as they come up; there is no
/// mechanism to fetch or update this remotely by design. Keep it in step with web/public/pages/faq.html.
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
            sends no calendar or reminder data anywhere. iOS asks for access the first \
            time you tap Allow Access on Stark's main screen, after Stark says what it is for. \
            Planner blocks for Apple reminders are kept in a small file of Stark's own on this \
            device. The day export (today and \
            yesterday) and the Weekly Review share include the Apple items they show.
            """
        ),
        Entry(
            question: "What about the items I made in Stark before?",
            answer: """
            Earlier versions of Stark kept them in files of its own and could copy them into \
            Apple Calendar and Reminders once. Stark now shows only Apple Calendar and Reminders \
            and no longer reads those files. They remain on this device, untouched, as a backup, \
            and are deleted only when you delete the app. Completed copies of repeating reminders \
            made in Stark were not copied into Apple, so that history is only in the old files.
            """
        ),
        Entry(
            question: "How does quick add work?",
            answer: """
            In Add, type a phrase such as "Lunch with Sarah at 1pm tomorrow", "Pay rent every \
            month" or "Remind me to call the bank Friday". It also understands time ranges such \
            as 1-2pm ("Lunch tomorrow 1-2pm"), "this Friday" and "next Friday" (that day in next week), and "every \
            weekday" or "every weekend". When Stark recognises a date, time, \
            repeat or reminder in it, a suggestion appears under the title. Tap the suggestion to \
            apply it; Stark never fills in a date by itself. It works on your device only, in \
            English, and nothing is sent anywhere.
            """
        ),
        Entry(
            question: "Why do birthdays show a cake and an age?",
            answer: """
            Events on Apple's Birthdays calendar show a cake before the name. The first time Stark \
            loads a birthday from a calendar you show, iOS asks whether Stark may read your \
            contacts; Contacts access is \
            optional. If you allow it, Stark reads only the birth year of the people in your \
            Birthdays calendar, on this device, to show "Turns N". The year is never stored or \
            sent anywhere by Stark. If you decline, Stark still shows the cake without the age.
            """
        ),
        Entry(
            question: "What are the Join button and the time zone card?",
            answer: """
            When an event's URL, location or notes hold a video-call link, Stark shows a Join \
            button for Zoom, Google Meet, Microsoft Teams, Webex and FaceTime links on the event, \
            and a small video icon on its row. The link is opened only when you tap it; Stark \
            never loads or checks the link. Only https links from those services count. There is \
            also a time zone card for events in another time zone, showing the time there and \
            your time. All-day events and events with no time zone show no card. Both are \
            read from the event on this device; nothing is sent anywhere.
            """
        ),
        Entry(
            question: "Can I save sets of calendars?",
            answer: """
            Yes. Tap the calendars button at the bottom of the screen (it reads "All Calendars") \
            to create sets of calendars and reminder lists, for example Work and Home, and to \
            switch between them from the All Calendars button; the button then shows the set's \
            name. A calendar you add later is not in an existing set until you edit the set, but \
            it shows under All Calendars. Sets are kept on this device and are not sent anywhere.
            """
        ),
        Entry(
            question: "Can Stark show the weather?",
            answer: """
            Yes. Weather is optional and off by default: turn it on in Settings. Then iOS asks \
            whether Stark may use your location while you use the app, and the agenda's day \
            headers show a forecast symbol with the high and low for the next days; the Day, Week and Month views show it too (a symbol and the high in Week, the symbol alone in Month). Stark sends \
            an approximate location rounded to about 11 km to MET Norway's public forecast \
            service and sends nothing else; the position is never stored. Weather is the only \
            thing Stark ever sends over the network. Turn it off and Stark stops asking.
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
            missed. Weekly Review counts reminders in the week they were completed.
            """
        ),
        Entry(
            question: "Can I turn an event into a task?",
            answer: """
            Yes. Open the event, use the Event/Reminder switch at the top and tap the check. The \
            event's end time is dropped and its location moves into the task's notes. It works \
            the other way round too: a task becomes an event, and its priority is dropped. For an Apple item Stark \
            creates the other kind and deletes the original, so its alerts, invitees and any \
            occurrences edited one by one are lost; Stark asks first when the event has invitees \
            (they may be notified), and an item whose repeat Stark can't copy can't be converted.
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
