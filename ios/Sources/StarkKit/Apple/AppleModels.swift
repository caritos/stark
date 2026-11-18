// ios/Sources/StarkKit/Apple/AppleModels.swift
import Foundation

/// A calendar or reminder list on the device. Plain values: StarkKit never imports EventKit.
public struct AppleCalendarInfo: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let accountName: String
    public let colorHex: String?
    public let isReminderList: Bool
    /// Stark may add, change and delete items in it (`EKCalendar.allowsContentModifications`;
    /// false for Birthdays and subscribed calendars).
    public let isWritable: Bool
    /// The calendar lives in the device-only source ("On My iPhone", `EKSourceType.local`) and never
    /// syncs to the owner's other devices.
    public let isLocalOnly: Bool
    /// The system Birthdays calendar (`EKCalendarType.birthday`).
    public let isBirthdayCalendar: Bool

    public init(id: String, title: String, accountName: String, colorHex: String?, isReminderList: Bool,
                isWritable: Bool = true, isLocalOnly: Bool = false, isBirthdayCalendar: Bool = false) {
        self.isBirthdayCalendar = isBirthdayCalendar
        self.isLocalOnly = isLocalOnly
        self.id = id
        self.title = title
        self.accountName = accountName
        self.colorHex = colorHex
        self.isReminderList = isReminderList
        self.isWritable = isWritable
    }
}

/// Where an overlay agenda row came from. Nil on `AgendaItem` for Stark's own rows.
public struct AppleSource: Equatable, Sendable {
    public let calendarID: String
    public let calendarTitle: String
    public let colorHex: String?
    public let isReminder: Bool
    /// A reminder's URL (Stark's `Reminder` has no URL field); nil for events, whose URL is on
    /// `Event.url`. Read it through `appleItemURL(_:)`.
    public let url: String?
    /// The row's calendar or list can be written to (`AppleCalendarInfo.isWritable`).
    public let isWritable: Bool
    /// The row is a repeating Apple reminder (`AppleReminder.isRecurring`); the synthetic
    /// `Reminder` carries no recurrence, so the row's repeat glyph reads this instead.
    public let isRecurringSeries: Bool
    /// The row is an event on the Birthdays calendar.
    public let isBirthday: Bool
    /// The contact's birth year, when known (`AppleSnapshot.birthYears`).
    public let birthYear: Int?
    /// A video-call link found in the event's URL, location or notes (events only).
    public let conferenceLink: ConferenceLink?
    /// `EKEvent.timeZone` identifier; nil for floating and all-day events and reminders.
    public let timeZoneID: String?

    public init(calendarID: String, calendarTitle: String, colorHex: String?, isReminder: Bool,
                url: String? = nil, isWritable: Bool = true, isRecurringSeries: Bool = false,
                isBirthday: Bool = false, birthYear: Int? = nil,
                conferenceLink: ConferenceLink? = nil, timeZoneID: String? = nil) {
        self.conferenceLink = conferenceLink
        self.timeZoneID = timeZoneID
        self.isBirthday = isBirthday
        self.birthYear = birthYear
        self.isRecurringSeries = isRecurringSeries
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.colorHex = colorHex
        self.isReminder = isReminder
        self.url = url
        self.isWritable = isWritable
    }
}

public struct AppleCalendarEvent: Equatable, Sendable {
    public let id: String
    public let title: String
    public let notes: String?
    public let location: String?
    public let url: String?
    public let start: Date
    public let end: Date?
    public let isAllDay: Bool
    public let calendar: AppleCalendarInfo
    /// Contacts identifier of a Birthdays-calendar event's person, nil elsewhere.
    public let birthdayContactID: String?
    /// `EKEvent.timeZone` identifier; nil for a floating or all-day event.
    public let timeZoneID: String?

    public init(id: String, title: String, notes: String?, location: String?, url: String?,
                start: Date, end: Date?, isAllDay: Bool, calendar: AppleCalendarInfo,
                birthdayContactID: String? = nil, timeZoneID: String? = nil) {
        self.timeZoneID = timeZoneID
        self.birthdayContactID = birthdayContactID
        self.id = id
        self.title = title
        self.notes = notes
        self.location = location
        self.url = url
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
    }
}

public struct AppleReminder: Equatable, Sendable {
    public let id: String
    public let title: String
    public let notes: String?
    public let due: Date?
    public let dueHasTime: Bool
    public let isCompleted: Bool
    public let completedAt: Date?
    public let priority: Int?
    public let calendar: AppleCalendarInfo
    public let url: String?
    /// The reminder repeats (`EKReminder.hasRecurrenceRules`). Apple advances a repeating
    /// reminder in place and leaves a completed copy per completion, so only for these does a
    /// later due date or a same-title completed copy mean an earlier occurrence was done
    /// (`DayPlanModel.appleDoneBlock`). The synthetic `Reminder` still carries no recurrence.
    public let isRecurring: Bool

    public init(id: String, title: String, notes: String?, due: Date?, dueHasTime: Bool,
                isCompleted: Bool, completedAt: Date?, priority: Int?, calendar: AppleCalendarInfo,
                url: String? = nil, isRecurring: Bool = false) {
        self.isRecurring = isRecurring
        self.id = id
        self.title = title
        self.notes = notes
        self.due = due
        self.dueHasTime = dueHasTime
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.priority = priority
        self.calendar = calendar
        self.url = url
    }
}

public enum AppleAccess: Equatable, Sendable {
    case notAsked, granted, denied, writeOnly

    /// The overlay needs full access to BOTH events and reminders. Any denial wins, then any
    /// write-only grant; `granted` only when both are granted; otherwise still `notAsked`.
    public static func combined(events: AppleAccess, reminders: AppleAccess) -> AppleAccess {
        if events == .denied || reminders == .denied { return .denied }
        if events == .writeOnly || reminders == .writeOnly { return .writeOnly }
        if events == .granted && reminders == .granted { return .granted }
        return .notAsked
    }
}

public struct AppleSnapshot: Equatable, Sendable {
    public let events: [AppleCalendarEvent]
    public let reminders: [AppleReminder]
    /// Contact id to birth year, for the Birthdays calendar's events.
    public let birthYears: [String: Int]

    public init(events: [AppleCalendarEvent], reminders: [AppleReminder], birthYears: [String: Int] = [:]) {
        self.birthYears = birthYears
        self.events = events
        self.reminders = reminders
    }

    /// No Apple items: the default for every engine's `apple:` parameter, so local behaviour is
    /// unchanged when the overlay is off.
    public static let empty = AppleSnapshot(events: [], reminders: [])

    /// Reminders with no due date (open or completed). The agenda never shows them; Search and the
    /// planner's "No date" pane do (`undatedAppleReminders`).
    public var undatedReminders: [AppleReminder] { reminders.filter { $0.due == nil } }
}

/// What the overlay does when access is re-read without asking (e.g. the user changed it in iOS
/// Settings and came back). The snapshot must be empty whenever access is not granted, and must
/// be fetched once access becomes granted with the switch on; nothing changes otherwise.
public enum AppleAccessChange: Equatable, Sendable {
    case none, reload, clear

    public static func action(previous: AppleAccess, current: AppleAccess, isEnabled: Bool) -> AppleAccessChange {
        // Switched off: the snapshot is already empty and must stay so.
        guard isEnabled, previous != current else { return .none }
        if current == .granted { return .reload }
        if previous == .granted { return .clear }
        return .none
    }
}
