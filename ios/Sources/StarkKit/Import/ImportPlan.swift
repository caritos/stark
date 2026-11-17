// ios/Sources/StarkKit/Import/ImportPlan.swift
import Foundation

/// One local item to create in Apple (phase 2 import), with what follows it to its new identifier.
public struct ImportStep: Equatable, Sendable {
    /// The local `Event.id` / `Reminder.id`; the import-ledger key.
    public var localID: String
    public var kind: AppleItemRef.Kind
    /// Set when `kind == .event`.
    public var event: NewEvent?
    /// Set when `kind == .reminder`.
    public var reminder: NewReminder?
    /// A repeating event's removed occurrences, deleted in Apple after the series is created.
    /// Always empty for reminders (their exception dates are history, folded into the due date
    /// and the reduced count).
    public var exceptionDates: [Date]
    /// The item's local plan blocks (matched by `reminderID`), copied to the sidecar on import.
    public var plans: [PlanBlock]
    /// An event's attended/skipped marks, copied to the sidecar on import.
    public var outcomes: [EventOutcomeRecord]
    public var title: String

    public init(localID: String, kind: AppleItemRef.Kind, event: NewEvent? = nil, reminder: NewReminder? = nil,
                exceptionDates: [Date] = [], plans: [PlanBlock] = [], outcomes: [EventOutcomeRecord] = [],
                title: String) {
        self.localID = localID
        self.kind = kind
        self.event = event
        self.reminder = reminder
        self.exceptionDates = exceptionDates
        self.plans = plans
        self.outcomes = outcomes
        self.title = title
    }
}

/// The preview's numbers. The four item counts do not overlap: `events` and the two reminder
/// counts are one-offs, `recurringMasters` is every repeating series (events and reminders), so
/// their sum is `steps.count`.
public struct ImportCounts: Equatable, Sendable {
    public var events: Int
    public var openReminders: Int
    public var completedReminders: Int
    public var recurringMasters: Int
    public var planBlocks: Int
    public var outcomes: Int

    public init(events: Int = 0, openReminders: Int = 0, completedReminders: Int = 0, recurringMasters: Int = 0,
                planBlocks: Int = 0, outcomes: Int = 0) {
        self.events = events
        self.openReminders = openReminders
        self.completedReminders = completedReminders
        self.recurringMasters = recurringMasters
        self.planBlocks = planBlocks
        self.outcomes = outcomes
    }

    /// Items the run will create.
    public var items: Int { events + openReminders + completedReminders + recurringMasters }
}

/// What an import would do: the ordered steps plus everything the preview reports.
public struct ImportPlan: Sendable {
    /// Events first (by start), then reminders (by due date, undated last); ties by local id.
    public var steps: [ImportStep]
    /// Items Apple cannot hold; they stay local, marked "not imported".
    public var unrepresentable: [(localID: String, title: String, reason: String)]
    /// Titles of repeating reminders with nothing left to do (count used up, or ended); kept in
    /// the `.ics` backup only.
    public var finishedSeries: [String]
    /// Completed copies of repeating reminders (`seriesID` set): history, not imported.
    public var skippedHistoryCount: Int
    /// Steps that look already present in Apple (informational; never removes a step).
    public var probableDuplicates: Int
    /// Titles of imported repeats on day 29-31 (or Feb 29) that Apple skips in short months.
    public var shortMonthRepeats: [String]
    public var counts: ImportCounts

    public init(steps: [ImportStep] = [], unrepresentable: [(localID: String, title: String, reason: String)] = [],
                finishedSeries: [String] = [], skippedHistoryCount: Int = 0, probableDuplicates: Int = 0,
                shortMonthRepeats: [String] = [], counts: ImportCounts = ImportCounts()) {
        self.steps = steps
        self.unrepresentable = unrepresentable
        self.finishedSeries = finishedSeries
        self.skippedHistoryCount = skippedHistoryCount
        self.probableDuplicates = probableDuplicates
        self.shortMonthRepeats = shortMonthRepeats
        self.counts = counts
    }

    /// Nothing left to create.
    public var isEmpty: Bool { steps.isEmpty }
}
