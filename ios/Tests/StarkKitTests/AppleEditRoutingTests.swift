// ios/Tests/StarkKitTests/AppleEditRoutingTests.swift
import Testing
import Foundation
@testable import StarkKit

/// Task 9a: what a tapped row opens now that Stark writes Apple items, the edit sheet's
/// editable/read-only decision from the stored details, the Add screen's destination state, the
/// "reopened a completed copy" notice and the Search fetch range.
@Suite("AppleEditRouting")
struct AppleEditRoutingTests {
    private let when = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func source(writable: Bool, reminder: Bool = false, calendarID: String = "c1") -> AppleSource {
        AppleSource(calendarID: calendarID, calendarTitle: "Work", colorHex: nil, isReminder: reminder,
                    isWritable: writable)
    }

    private func appleEvent(writable: Bool) -> AgendaItem {
        AgendaItem(kind: .event(Event(id: "apple-EV1", title: "Standup", start: when)), occurrence: when,
                   displayDate: when, isOverdue: false, appleSource: source(writable: writable))
    }

    private func appleReminder(_ reminder: Reminder = Reminder(id: "apple-RM1", title: "Milk"),
                               writable: Bool = true, calendarID: String = "l1") -> AgendaItem {
        AgendaItem(kind: .reminder(reminder), occurrence: when, displayDate: when, isOverdue: false,
                   appleSource: source(writable: writable, reminder: true, calendarID: calendarID))
    }

    // MARK: Detail routing

    @Test("a writable Apple row opens the Apple editor with its ref; it is not read-only")
    func writableAppleRowIsEditable() {
        let item = appleEvent(writable: true)
        let detail = AgendaItemDetail(item)
        #expect(detail == .editableApple(item, AppleItemRef(kind: .event, identifier: "EV1")))
        #expect(detail.editable == nil)
        #expect(detail.id == item.id)
        #expect(!item.isReadOnly)
    }

    @Test("a row from a calendar Stark can't write stays read-only")
    func nonWritableAppleRowIsReadOnly() {
        let item = appleEvent(writable: false)
        #expect(AgendaItemDetail(item) == .readOnly(item))
        #expect(item.isReadOnly)
    }

    @Test("a writable Apple reminder routes with the reminder kind")
    func writableReminderRef() {
        let item = appleReminder()
        #expect(AgendaItemDetail(item) == .editableApple(item, AppleItemRef(kind: .reminder, identifier: "RM1")))
    }

    // MARK: Editor state from the stored details

    @Test("stored details decide: writable and not invitee-only edits, anything else is read-only")
    func editorStateFromDetails() {
        let event = Event(id: "apple-EV1", title: "Standup", start: when)
        let writable = ItemDetails(event: event, calendarID: "c1")
        #expect(AppleEditorState(details: writable) == .edit(writable))
        let locked = ItemDetails(event: event, calendarID: "c1", isWritable: false)
        #expect(AppleEditorState(details: locked) == .readOnly)
        let invitee = ItemDetails(event: event, calendarID: "c1", isInviteeOnly: true)
        #expect(AppleEditorState(details: invitee) == .readOnly)
    }

    @Test("the editor's row carries the stored item but keeps the tapped occurrence and source")
    func rowWithStoredItem() {
        let row = appleReminder()
        let stored = Reminder(id: "apple-RM1", title: "Milk", notes: "2 l", dueDate: when,
                              recurrence: RecurrenceRule(frequency: .weekly))
        let details = ItemDetails(reminder: stored, calendarID: "l1")
        let edited = row.withStoredItem(details)
        #expect(edited.kind == .reminder(stored))
        #expect(edited.occurrence == row.occurrence)
        #expect(edited.appleSource == row.appleSource)
        #expect(edited.isRecurring)
        #expect(edited.id == row.id)
    }

    @Test("a stored event carries the sidecar outcome for the tapped day")
    func storedEventWithOutcome() {
        let row = appleEvent(writable: true)
        let details = ItemDetails(event: Event(id: "apple-EV1", title: "Standup", start: when), calendarID: "c1")
        let edited = row.withStoredItem(details, outcome: .attended)
        #expect(edited.outcome == .attended)
    }

    // MARK: Rule-change confirmation

    @Test("only the edited-occurrences refusal asks for a confirmation")
    func ruleChangeConfirmation() {
        #expect(ItemRouterError.apple(.ruleChangeLosesEditedOccurrences).asksToConfirmRuleChange)
        #expect(!ItemRouterError.apple(.unrepresentable("x")).asksToConfirmRuleChange)
        #expect(!ItemRouterError.apple(.notWritable).asksToConfirmRuleChange)
        #expect(ItemRouterError.ruleChangeConfirmation.contains("Change anyway?"))
    }

    // MARK: Reopening a completed copy

    @Test("reopening the completed copy of a repeating Apple reminder explains the series stays put")
    func uncompleteNoticeForCopy() {
        let copy = appleReminder(Reminder(id: "apple-C1", title: "Water plants", dueDate: when, isCompleted: true))
        let master = AppleReminder(id: "M1", title: "Water plants", notes: nil, due: when.addingTimeInterval(86_400),
                                   dueHasTime: false, isCompleted: false, completedAt: nil, priority: nil,
                                   calendar: AppleCalendarInfo(id: "l1", title: "Home", accountName: "iCloud",
                                                               colorHex: nil, isReminderList: true),
                                   isRecurring: true)
        let snapshot = AppleSnapshot(events: [], reminders: [master])
        #expect(UncompleteNotice.text(for: copy, snapshot: snapshot) != nil)
        // Another list, a one-off with the same title, or a Stark item: no notice.
        let elsewhere = appleReminder(Reminder(id: "apple-C2", title: "Water plants", dueDate: when, isCompleted: true),
                                      calendarID: "other")
        #expect(UncompleteNotice.text(for: elsewhere, snapshot: snapshot) == nil)
        let oneOffMaster = AppleSnapshot(events: [], reminders: [AppleReminder(
            id: "M2", title: "Water plants", notes: nil, due: when, dueHasTime: false, isCompleted: false,
            completedAt: nil, priority: nil, calendar: master.calendar)])
        #expect(UncompleteNotice.text(for: copy, snapshot: oneOffMaster) == nil)
        let stark = AgendaItem(kind: .reminder(Reminder(id: "r1", title: "Water plants", dueDate: when, isCompleted: true)),
                               occurrence: when, displayDate: when, isOverdue: false)
        #expect(UncompleteNotice.text(for: stark, snapshot: snapshot) == nil)
    }

    // MARK: Add destination

    private func info(_ id: String, list: Bool = false) -> AppleCalendarInfo {
        AppleCalendarInfo(id: id, title: id, accountName: "iCloud", colorHex: nil, isReminderList: list)
    }

    @Test("the Add screen needs access, then a writable destination; the default is preselected")
    func addDestinationState() {
        #expect(AddDestination.state(hasAccess: false, choices: [info("a")], defaultID: "a") == .needsAccess)
        #expect(AddDestination.state(hasAccess: true, choices: [], defaultID: nil) == .noneWritable)
        #expect(AddDestination.state(hasAccess: true, choices: [info("a"), info("b")], defaultID: "b")
            == .ready(selected: "b"))
        // A default that is no longer offered selects nothing: Save stays off until one is picked.
        #expect(AddDestination.state(hasAccess: true, choices: [info("a")], defaultID: "gone")
            == .ready(selected: nil))
        #expect(AddDestination.message(.needsAccess, isEvent: true) != nil)
        #expect(AddDestination.message(.noneWritable, isEvent: false)?.contains("list") == true)
        #expect(AddDestination.message(.ready(selected: "a"), isEvent: true) == nil)
    }

    // MARK: Search fetch range

    @Test("Search registers two years either side of today with the shared fetch window")
    func searchRange() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10))!
        let range = SearchWindow.range(around: today, calendar: cal)
        #expect(range.lowerBound == cal.date(from: DateComponents(year: 2024, month: 11, day: 15))!)
        #expect(range.upperBound > cal.date(from: DateComponents(year: 2028, month: 11, day: 15, hour: 23))!)
        #expect(range.upperBound < cal.date(from: DateComponents(year: 2028, month: 11, day: 16))!)

        var window = AppleFetchWindow()
        window.set(.agenda, today...today.addingTimeInterval(86_400))
        window.set(.search, range)
        #expect(window.covering == range)
        window.set(.search, nil)
        #expect(window.covering == today...today.addingTimeInterval(86_400))
    }

    @Test("converting an Apple event with attendees asks first; without attendees or for a reminder it doesn't")
    func convertConfirmation() {
        let event = Event(id: "apple-EV1", title: "Review", start: when)
        #expect(ItemDetails(event: event, calendarID: "c1", hasAttendees: true).convertAsksFirst)
        #expect(!ItemDetails(event: event, calendarID: "c1").convertAsksFirst)
        #expect(!ItemDetails(reminder: Reminder(id: "apple-R", title: "Milk"), calendarID: "l1").convertAsksFirst)
    }
}
