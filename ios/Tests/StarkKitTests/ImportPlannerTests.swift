// ios/Tests/StarkKitTests/ImportPlannerTests.swift
import Testing
import Foundation
@testable import StarkKit

/// `ImportPlanner.plan`: local items in, ordered import steps and the preview's numbers out.
/// Every date is built with the local calendar so the suite holds in any time zone.
struct ImportPlannerTests {
    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// 2026-11-17 10:00 local.
    private var today: Date { date(2026, 11, 17, 10) }

    private func day(_ offset: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        let start = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: today))!
        return cal.date(bySettingHour: h, minute: min, second: 0, of: start)!
    }

    private func plan(events: [Event] = [], reminders: [Reminder] = [], plans: [PlanBlock] = [],
                      alreadyImported: Set<String> = [], apple: [AgendaItem] = []) -> ImportPlan {
        ImportPlanner.plan(events: events, reminders: reminders, plans: plans, alreadyImported: alreadyImported,
                           apple: apple, today: today, calendar: cal)
    }

    /// The single open row `buildAgendaItems` shows for a repeating reminder (overdue row first).
    private func shownOccurrence(of master: Reminder, with others: [Reminder] = []) -> Date? {
        let range = cal.startOfDay(for: today)...day(800)
        let rows = buildAgendaItems(events: [], reminders: [master] + others, in: range, today: today)
            .filter { if case .reminder(let r) = $0.kind { return r.id == master.id } else { return false } }
        return rows.first(where: \.isOverdue)?.occurrence ?? rows.map(\.occurrence).min()
    }

    private func completedCopy(of master: Reminder, on occurrence: Date) -> Reminder {
        Reminder(title: master.title, dueDate: occurrence, isCompleted: true, completedDate: occurrence,
                 completedAt: occurrence, seriesID: master.id)
    }

    // MARK: Events

    @Test func plainEventConvertsAllFields() {
        let event = Event(id: "e1", title: "Dentist", notes: "Bring card", start: day(3, 9), end: day(3, 10),
                          location: "Main St", url: "https://example.com")
        let result = plan(events: [event])
        #expect(result.steps.count == 1)
        let step = result.steps[0]
        #expect(step.localID == "e1")
        #expect(step.kind == .event)
        #expect(step.title == "Dentist")
        #expect(step.reminder == nil)
        #expect(step.event == NewEvent(title: "Dentist", notes: "Bring card", start: day(3, 9), end: day(3, 10),
                                       isAllDay: false, location: "Main St", url: "https://example.com"))
        #expect(result.counts.events == 1)
    }

    @Test func allDayAndMultiDayEventKeepShape() {
        let allDay = Event(id: "a", title: "Holiday", start: day(2), isAllDay: true)
        let multi = Event(id: "m", title: "Trip", start: day(5), end: day(8), isAllDay: true)
        let result = plan(events: [allDay, multi])
        let byID = Dictionary(uniqueKeysWithValues: result.steps.map { ($0.localID, $0) })
        #expect(byID["a"]?.event?.isAllDay == true)
        #expect(byID["a"]?.event?.start == day(2))
        #expect(byID["a"]?.event?.end == nil)
        #expect(byID["m"]?.event?.isAllDay == true)
        #expect(byID["m"]?.event?.start == day(5))
        #expect(byID["m"]?.event?.end == day(8))
    }

    @Test func eventWithExceptionDatesListsThem() {
        let rule = RecurrenceRule(frequency: .weekly)
        let exceptions = [day(7, 9), day(14, 9)]
        let event = Event(id: "w", title: "Standup", start: day(0, 9), end: day(0, 9, 15), recurrence: rule,
                          exceptionDates: exceptions)
        let result = plan(events: [event])
        #expect(result.steps.count == 1)
        #expect(result.steps[0].exceptionDates == exceptions)
        #expect(result.steps[0].event?.recurrence == rule)
        #expect(result.counts.recurringMasters == 1)
    }

    // MARK: One-off reminders

    @Test func openOneOffReminderKeepsDueAndPriority() {
        let timed = Reminder(id: "r1", title: "Call", notes: "re: bill", dueDate: day(1, 14, 30), priority: 1)
        let dateOnly = Reminder(id: "r2", title: "Laundry", dueDate: day(-3), priority: 5)
        let result = plan(reminders: [timed, dateOnly])
        let byID = Dictionary(uniqueKeysWithValues: result.steps.map { ($0.localID, $0) })
        #expect(byID["r1"]?.kind == .reminder)
        #expect(byID["r1"]?.reminder == NewReminder(title: "Call", notes: "re: bill", due: day(1, 14, 30),
                                                     dueHasTime: true, priority: 1))
        #expect(byID["r2"]?.reminder?.due == day(-3))
        #expect(byID["r2"]?.reminder?.dueHasTime == false)
        #expect(byID["r2"]?.reminder?.priority == 5)
        #expect(byID["r2"]?.reminder?.completedAt == nil)
        #expect(result.counts.openReminders == 2)
    }

    @Test func completedOneOffGetsCompletedAt() {
        let ticked = Reminder(id: "c1", title: "Pay rent", dueDate: day(-10), isCompleted: true,
                              completedDate: day(-10), completedAt: day(-9, 8, 15))
        let legacy = Reminder(id: "c2", title: "Old one", dueDate: day(-20), isCompleted: true,
                              completedDate: day(-20))
        let result = plan(reminders: [ticked, legacy])
        let byID = Dictionary(uniqueKeysWithValues: result.steps.map { ($0.localID, $0) })
        // The actual tick time, falling back to the completed occurrence when it was never recorded.
        #expect(byID["c1"]?.reminder?.completedAt == day(-9, 8, 15))
        #expect(byID["c2"]?.reminder?.completedAt == day(-20))
        #expect(byID["c1"]?.reminder?.due == day(-10))
        #expect(result.counts.completedReminders == 2)
        #expect(result.counts.openReminders == 0)
    }

    @Test func completedCopiesWithSeriesIDAreCountedNotImported() {
        let master = Reminder(id: "s", title: "Water plants", dueDate: day(-5, 9),
                              recurrence: RecurrenceRule(frequency: .daily),
                              exceptionDates: [day(-5, 9), day(-4, 9), day(-3, 9)])
        let copies = [day(-5, 9), day(-4, 9), day(-3, 9)].map { completedCopy(of: master, on: $0) }
        let result = plan(reminders: [master] + copies)
        #expect(result.skippedHistoryCount == 3)
        #expect(result.steps.map(\.localID) == ["s"])
        #expect(result.counts.completedReminders == 0)
    }

    // MARK: Repeating reminders

    @Test func repeatingReminderDueIsShownOccurrence() throws {
        // Overdue: completed three days ago, so the oldest miss after that (two days ago) is shown.
        let overdue = Reminder(id: "o", title: "Stretch", dueDate: day(-6, 7, 30),
                               recurrence: RecurrenceRule(frequency: .daily),
                               exceptionDates: [day(-3, 7, 30)])
        let copy = completedCopy(of: overdue, on: day(-3, 7, 30))
        // A weekly series missed for months: only the oldest miss INSIDE the lookback counts.
        let stale = Reminder(id: "st", title: "Review budget", dueDate: day(-200),
                             recurrence: RecurrenceRule(frequency: .weekly))
        // Nothing missed yet: the next occurrence.
        let upcoming = Reminder(id: "u", title: "Bins", dueDate: day(2),
                                recurrence: RecurrenceRule(frequency: .weekly))

        let result = plan(reminders: [overdue, copy, stale, upcoming])
        let byID = Dictionary(uniqueKeysWithValues: result.steps.map { ($0.localID, $0) })

        let overdueShown = try #require(shownOccurrence(of: overdue, with: [copy]))
        #expect(overdueShown == day(-2, 7, 30))
        #expect(byID["o"]?.reminder?.due == overdueShown)
        #expect(byID["o"]?.reminder?.dueHasTime == true)
        #expect(byID["o"]?.reminder?.recurrence == RecurrenceRule(frequency: .daily))

        let staleShown = try #require(shownOccurrence(of: stale))
        #expect(staleShown >= day(-AgendaWindow.overdueLookbackDays))
        #expect(staleShown < day(-AgendaWindow.overdueLookbackDays + 7))
        #expect(byID["st"]?.reminder?.due == staleShown)
        #expect(byID["st"]?.reminder?.dueHasTime == false)

        let upcomingShown = try #require(shownOccurrence(of: upcoming))
        #expect(upcomingShown == day(2))
        #expect(byID["u"]?.reminder?.due == upcomingShown)
        #expect(byID["u"]?.reminder?.dueHasTime == FormFields.dueHasTime(upcoming))
        #expect(result.counts.recurringMasters == 3)
    }

    @Test func fixedCountIsReducedByExceptionsAndCompletedCopies() {
        // COUNT 10 daily from five days ago: three completed (exdate + copy each), two skipped
        // (exdate only). Five occurrences are used up, so Apple gets the remaining five from today.
        var master = Reminder(id: "n", title: "Pill", dueDate: day(-5, 8),
                              recurrence: RecurrenceRule(frequency: .daily, count: 10))
        master.exceptionDates = (-5 ... -1).map { day($0, 8) }
        let copies = (-5 ... -3).map { completedCopy(of: master, on: day($0, 8)) }
        let result = plan(reminders: [master] + copies)
        #expect(result.steps.count == 1)
        #expect(result.steps[0].reminder?.due == day(0, 8))
        #expect(result.steps[0].reminder?.recurrence?.count == 5)
        #expect(result.skippedHistoryCount == 3)
        #expect(result.finishedSeries.isEmpty)
    }

    @Test func fixedCountKeepsAnOverdueMissAndEverythingAfterIt() {
        // COUNT 6 daily from four days ago, nothing done: the oldest miss is shown and all six remain.
        let master = Reminder(id: "m", title: "Drops", dueDate: day(-4, 8),
                              recurrence: RecurrenceRule(frequency: .daily, count: 6))
        let result = plan(reminders: [master])
        #expect(result.steps.first?.reminder?.due == day(-4, 8))
        #expect(result.steps.first?.reminder?.recurrence?.count == 6)
    }

    @Test func nonGregorianPhoneCalendarStillPinsTheGregorianDay() throws {
        // The same clamped "31st" series planned with a Hebrew calendar (a phone set to it): day and
        // month math must stay Gregorian, as buildAgendaItems and completeReminder do.
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = cal.timeZone
        let master = Reminder(id: "c", title: "Statement", dueDate: date(2026, 8, 31),
                              recurrence: RecurrenceRule(frequency: .monthly),
                              exceptionDates: [date(2026, 8, 31), date(2026, 9, 30), date(2026, 10, 31)])
        let copy = completedCopy(of: master, on: date(2026, 10, 31))
        let result = ImportPlanner.plan(events: [], reminders: [master, copy], plans: [], alreadyImported: [],
                                        apple: [], today: today, calendar: hebrew)
        let step = try #require(result.steps.first)
        #expect(step.reminder?.due == date(2026, 11, 30))
        #expect(step.reminder?.recurrence?.byMonthDay == [31])
        #expect(result.shortMonthRepeats == ["Statement"])

        let event = Event(id: "e", title: "Pay", start: date(2026, 10, 31, 9),
                          recurrence: RecurrenceRule(frequency: .monthly))
        let eventPlan = ImportPlanner.plan(events: [event], reminders: [], plans: [], alreadyImported: [],
                                           apple: [], today: today, calendar: hebrew)
        #expect(eventPlan.steps.first?.event?.recurrence?.byMonthDay == [31])
    }

    @Test func clampedMonthlyOccurrenceKeepsTheSeriesDay() throws {
        // "Every month on the 31st" whose next occurrence Stark clamps to Nov 30: the new series
        // starts on Nov 30 but still repeats on the 31st.
        let master = Reminder(id: "c", title: "Statement", dueDate: date(2026, 8, 31),
                              recurrence: RecurrenceRule(frequency: .monthly),
                              exceptionDates: [date(2026, 8, 31), date(2026, 9, 30), date(2026, 10, 31)])
        let copy = completedCopy(of: master, on: date(2026, 10, 31))
        let result = plan(reminders: [master, copy])
        let step = try #require(result.steps.first)
        #expect(step.reminder?.due == date(2026, 11, 30))
        #expect(step.reminder?.recurrence?.byMonthDay == [31])
        #expect(result.shortMonthRepeats == ["Statement"])
    }

    @Test func countReducedToZeroIsFinishedSeries() {
        var master = Reminder(id: "z", title: "Course", dueDate: day(-4, 8),
                              recurrence: RecurrenceRule(frequency: .daily, count: 3))
        master.exceptionDates = (-4 ... -2).map { day($0, 8) }
        let copies = (-4 ... -2).map { completedCopy(of: master, on: day($0, 8)) }
        let result = plan(reminders: [master] + copies)
        #expect(result.steps.isEmpty)
        #expect(result.finishedSeries == ["Course"])
    }

    @Test func endedUntilIsFinishedSeries() {
        let master = Reminder(id: "u", title: "Summer swim", dueDate: day(-300, 7),
                              recurrence: RecurrenceRule(frequency: .weekly, until: day(-150)))
        let result = plan(reminders: [master])
        #expect(result.steps.isEmpty)
        #expect(result.finishedSeries == ["Summer swim"])
        #expect(result.unrepresentable.isEmpty)
    }

    // MARK: Unrepresentable and short months

    @Test func unrepresentableRepeatIsListedWithReason() {
        // A yearly positional rule mixing a specific weekday with "any day": Apple has no such repeat.
        let rule = RecurrenceRule(frequency: .yearly, byPositionalDay: [
            PositionalDay(position: .first, dayType: .weekday(.monday)),
            PositionalDay(position: .last, dayType: .anyDay),
        ], byMonth: [.march])
        let reminder = Reminder(id: "x", title: "Odd one", dueDate: day(3), recurrence: rule)
        let event = Event(id: "xe", title: "Odd event", start: day(3, 9), recurrence: rule)
        let result = plan(events: [event], reminders: [reminder])
        #expect(result.steps.isEmpty)
        #expect(result.unrepresentable.map(\.localID).sorted() == ["x", "xe"])
        #expect(result.unrepresentable.allSatisfy { !$0.reason.isEmpty })
        #expect(result.unrepresentable.map(\.title).sorted() == ["Odd event", "Odd one"])
    }

    @Test func monthlyDay31AndYearlyFeb29AreListedAsShortMonthRepeats() {
        let monthly31 = Event(id: "m31", title: "Pay day", start: date(2026, 10, 31, 9),
                              recurrence: RecurrenceRule(frequency: .monthly))
        let monthlyByDay = Reminder(id: "m30", title: "Invoice", dueDate: day(3),
                                    recurrence: RecurrenceRule(frequency: .monthly, byMonthDay: [30]))
        let leap = Event(id: "f29", title: "Leap birthday", start: date(2024, 2, 29), isAllDay: true,
                         recurrence: RecurrenceRule(frequency: .yearly))
        let lastDay = Reminder(id: "last", title: "Close books", dueDate: date(2026, 11, 30),
                               recurrence: RecurrenceRule(frequency: .monthly, byPositionalDay: [
                                   PositionalDay(position: .last, dayType: .anyDay)]))
        let plain = Reminder(id: "p", title: "Rent", dueDate: date(2026, 12, 1),
                             recurrence: RecurrenceRule(frequency: .monthly))
        let result = plan(events: [monthly31, leap], reminders: [monthlyByDay, lastDay, plain])
        #expect(Set(result.shortMonthRepeats) == ["Pay day", "Invoice", "Leap birthday"])
        #expect(Set(result.steps.map(\.localID)) == ["m31", "m30", "f29", "last", "p"])
    }

    // MARK: Ledger and robustness

    @Test func alreadyImportedIdsAreOmitted() {
        let event = Event(id: "e", title: "Done before", start: day(1, 9))
        let master = Reminder(id: "s", title: "Series", dueDate: day(-2, 9),
                              recurrence: RecurrenceRule(frequency: .daily), exceptionDates: [day(-2, 9)])
        let copy = completedCopy(of: master, on: day(-2, 9))
        let open = Reminder(id: "r", title: "Still here", dueDate: day(1))
        let block = PlanBlock(reminderID: "s", occurrence: day(0, 9), start: day(0, 10), minutes: 30)
        let result = plan(events: [event], reminders: [master, copy, open], plans: [block],
                          alreadyImported: ["e", "s"])
        #expect(result.steps.map(\.localID) == ["r"])
        #expect(result.counts.events == 0)
        #expect(result.counts.planBlocks == 0)
    }

    @Test func emptyTitleAndEndBeforeStartDoNotCrash() {
        let event = Event(id: "e", title: "", start: day(2, 10), end: day(2, 9))
        let reminder = Reminder(id: "r", title: "   ", dueDate: day(1))
        let undated = Reminder(id: "u", title: "Someday")
        let result = plan(events: [event], reminders: [reminder, undated])
        #expect(result.steps.count == 3)
        let byID = Dictionary(uniqueKeysWithValues: result.steps.map { ($0.localID, $0) })
        #expect(byID["e"]?.event?.start == day(2, 10))
        #expect(byID["e"]?.event?.end == nil)
        #expect(byID["u"]?.reminder?.due == nil)
    }

    // MARK: Plans and outcomes

    @Test func planBlocksAndOutcomesFollowTheirItem() {
        let outcomes = [EventOutcomeRecord(date: day(-7, 9), outcome: .attended),
                        EventOutcomeRecord(date: day(-14, 9), outcome: .skipped)]
        let event = Event(id: "e", title: "Gym", start: day(-14, 9), recurrence: RecurrenceRule(frequency: .weekly),
                          outcomes: outcomes)
        let reminder = Reminder(id: "r", title: "Write", dueDate: day(1))
        let other = Reminder(id: "o", title: "Read", dueDate: day(2))
        let b1 = PlanBlock(id: "b1", reminderID: "r", occurrence: day(1), start: day(1, 9), minutes: 60)
        let b2 = PlanBlock(id: "b2", reminderID: "r", occurrence: day(1), start: day(1, 14), minutes: 30)
        let b3 = PlanBlock(id: "b3", reminderID: "o", occurrence: day(2), start: day(2, 9), minutes: 15)
        let orphan = PlanBlock(id: "b4", reminderID: "gone", occurrence: day(2), start: day(2, 11), minutes: 15)
        let result = plan(events: [event], reminders: [reminder, other], plans: [b1, b2, b3, orphan])
        let byID = Dictionary(uniqueKeysWithValues: result.steps.map { ($0.localID, $0) })
        #expect(byID["e"]?.outcomes == outcomes)
        #expect(byID["e"]?.plans.isEmpty == true)
        #expect(byID["r"]?.plans.map(\.id) == ["b1", "b2"])
        #expect(byID["o"]?.plans.map(\.id) == ["b3"])
        #expect(byID["r"]?.outcomes.isEmpty == true)
        #expect(result.counts.planBlocks == 3)
        #expect(result.counts.outcomes == 2)
    }

    // MARK: Probable duplicates

    private func appleEvent(_ title: String, at start: Date) -> AgendaItem {
        let event = Event(id: "apple-\(UUID().uuidString)", title: title, start: start)
        return AgendaItem(kind: .event(event), occurrence: start, displayDate: start, isOverdue: false,
                          appleSource: AppleSource(calendarID: "cal", calendarTitle: "Home", colorHex: nil, isReminder: false))
    }

    private func appleReminder(_ title: String, due: Date) -> AgendaItem {
        let reminder = Reminder(id: "apple-\(UUID().uuidString)", title: title, dueDate: due)
        return AgendaItem(kind: .reminder(reminder), occurrence: due, displayDate: due, isOverdue: false,
                          appleSource: AppleSource(calendarID: "list", calendarTitle: "Reminders", colorHex: nil, isReminder: true))
    }

    @Test func probableDuplicateMatchesTitleCaseInsensitiveStartWithinOneMinute() {
        let event = Event(id: "e", title: "Team Lunch", start: day(1, 12))
        let reminder = Reminder(id: "r", title: "buy milk", dueDate: day(2, 9))
        let unmatched = Reminder(id: "n", title: "Unique", dueDate: day(2, 9))
        let apple = [appleEvent("  team lunch ", at: day(1, 12).addingTimeInterval(45)),
                     appleReminder("Buy Milk", due: day(2, 9).addingTimeInterval(-60))]
        let result = plan(events: [event], reminders: [reminder, unmatched], apple: apple)
        #expect(result.probableDuplicates == 2)
        #expect(result.steps.count == 3)
    }

    @Test func doesNotMatchDifferentDay() {
        let event = Event(id: "e", title: "Team Lunch", start: day(1, 12))
        let apple = [appleEvent("Team Lunch", at: day(2, 12)),
                     appleEvent("Team Lunch", at: day(1, 12).addingTimeInterval(61))]
        let result = plan(events: [event], apple: apple)
        #expect(result.probableDuplicates == 0)
        #expect(result.steps.count == 1)
    }

    // MARK: Order

    @Test func stepsAreOrderedEventsFirstThenRemindersByDate() {
        let events = [Event(id: "e2", title: "B", start: day(5, 9)),
                      Event(id: "e1", title: "A", start: day(1, 9)),
                      Event(id: "e0", title: "Tie", start: day(1, 9))]
        let reminders = [Reminder(id: "r2", title: "Later", dueDate: day(4)),
                         Reminder(id: "r3", title: "No date"),
                         Reminder(id: "r1", title: "Sooner", dueDate: day(-1))]
        let first = plan(events: events, reminders: reminders)
        #expect(first.steps.map(\.localID) == ["e0", "e1", "e2", "r1", "r2", "r3"])
        let second = plan(events: events.reversed(), reminders: reminders.reversed())
        #expect(second.steps.map(\.localID) == first.steps.map(\.localID))
    }

    @Test func unrepresentableIDsMatchesThePlan() {
        let odd = RecurrenceRule(frequency: .weekly, count: 10, until: day(60))
        let master = Reminder(id: "wk", title: "Weekly", dueDate: day(-2), recurrence: RecurrenceRule(frequency: .weekly))
        let events = [
            Event(id: "xe", title: "Odd event", start: day(3, 9), recurrence: odd),
            Event(id: "ok", title: "Plain", start: day(3, 9)),
            Event(id: "done", title: "Imported odd", start: day(3, 9), recurrence: odd),
        ]
        let reminders = [
            Reminder(id: "x", title: "Odd one", dueDate: day(3), recurrence: odd),
            Reminder(id: "undated", title: "No due", recurrence: RecurrenceRule(frequency: .daily)),
            Reminder(id: "cm", title: "Completed master", dueDate: day(1), isCompleted: true,
                     recurrence: RecurrenceRule(frequency: .daily)),
            master,
            completedCopy(of: master, on: day(-9)),
            Reminder(id: "one", title: "One-off", dueDate: day(2)),
        ]
        let result = plan(events: events, reminders: reminders, alreadyImported: ["done"])
        let ids = ImportPlanner.unrepresentableIDs(events: events, reminders: reminders, alreadyImported: ["done"])
        #expect(ids == Set(result.unrepresentable.map(\.localID)))
        #expect(ids == ["xe", "x", "undated", "cm"])
    }

    // MARK: Short months are pinned so Apple skips them (controller ruling, Task 6 review)

    private func reminderRule(_ result: ImportPlan, _ id: String) -> RecurrenceRule? {
        result.steps.first { $0.localID == id }?.reminder?.recurrence
    }

    private func eventRule(_ result: ImportPlan, _ id: String) -> RecurrenceRule? {
        result.steps.first { $0.localID == id }?.event?.recurrence
    }

    @Test func monthlyDay31ReminderShownOnThe31stGetsAnExplicitDay() {
        let reminder = Reminder(id: "r31", title: "Pay rent", dueDate: date(2026, 12, 31, 9),
                                recurrence: RecurrenceRule(frequency: .monthly))
        let result = plan(reminders: [reminder])
        #expect(reminderRule(result, "r31")?.byMonthDay == [31])
        #expect(result.shortMonthRepeats == ["Pay rent"])
    }

    @Test func monthlyDay29And30RemindersGetAnExplicitDay() {
        let r29 = Reminder(id: "r29", title: "Day 29", dueDate: date(2026, 11, 29, 9),
                           recurrence: RecurrenceRule(frequency: .monthly))
        let r30 = Reminder(id: "r30", title: "Day 30", dueDate: date(2026, 11, 30, 9),
                           recurrence: RecurrenceRule(frequency: .monthly))
        let result = plan(reminders: [r29, r30])
        #expect(reminderRule(result, "r29")?.byMonthDay == [29])
        #expect(reminderRule(result, "r30")?.byMonthDay == [30])
    }

    @Test func yearlyFeb29ReminderGetsMonthAndDay() {
        let reminder = Reminder(id: "leap", title: "Leap day", dueDate: date(2028, 2, 29, 9),
                                recurrence: RecurrenceRule(frequency: .yearly))
        let rule = reminderRule(plan(reminders: [reminder]), "leap")
        #expect(rule?.byMonth == [.february])
        #expect(rule?.byMonthDay == [29])
    }

    @Test func repeatingEventsOnShortMonthDaysGetExplicitDays() {
        let monthly = Event(id: "e31", title: "Pay day", start: date(2026, 10, 31, 9),
                            recurrence: RecurrenceRule(frequency: .monthly))
        let monthly30 = Event(id: "e30", title: "Review", start: date(2026, 11, 30, 9),
                              recurrence: RecurrenceRule(frequency: .monthly))
        let leap = Event(id: "f29", title: "Leap birthday", start: date(2024, 2, 29), isAllDay: true,
                         recurrence: RecurrenceRule(frequency: .yearly))
        let plain = Event(id: "e15", title: "Mid month", start: date(2026, 11, 15, 9),
                          recurrence: RecurrenceRule(frequency: .monthly))
        let result = plan(events: [monthly, monthly30, leap, plain])
        #expect(eventRule(result, "e31")?.byMonthDay == [31])
        #expect(eventRule(result, "e30")?.byMonthDay == [30])
        #expect(eventRule(result, "f29")?.byMonth == [.february])
        #expect(eventRule(result, "f29")?.byMonthDay == [29])
        #expect(eventRule(result, "e15") == RecurrenceRule(frequency: .monthly))
    }

    @Test func lastDayOfMonthRuleIsUntouched() {
        let lastDay = RecurrenceRule(frequency: .monthly, byPositionalDay: [
            PositionalDay(position: .last, dayType: .anyDay)])
        let reminder = Reminder(id: "last", title: "Close books", dueDate: date(2026, 11, 30, 9), recurrence: lastDay)
        let event = Event(id: "lastE", title: "Month end", start: date(2026, 11, 30, 9), recurrence: lastDay)
        let result = plan(events: [event], reminders: [reminder])
        #expect(reminderRule(result, "last") == lastDay)
        #expect(eventRule(result, "lastE") == lastDay)
        #expect(result.shortMonthRepeats.isEmpty)
    }
}
