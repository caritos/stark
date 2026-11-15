// ios/Sources/StarkKit/Apple/AppleModels.swift
import Foundation

/// A calendar or reminder list on the device. Plain values: StarkKit never imports EventKit.
public struct AppleCalendarInfo: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let accountName: String
    public let colorHex: String?
    public let isReminderList: Bool

    public init(id: String, title: String, accountName: String, colorHex: String?, isReminderList: Bool) {
        self.id = id
        self.title = title
        self.accountName = accountName
        self.colorHex = colorHex
        self.isReminderList = isReminderList
    }
}

/// Where an overlay agenda row came from. Nil on `AgendaItem` for Stark's own rows.
public struct AppleSource: Equatable, Sendable {
    public let calendarID: String
    public let calendarTitle: String
    public let colorHex: String?
    public let isReminder: Bool

    public init(calendarID: String, calendarTitle: String, colorHex: String?, isReminder: Bool) {
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.colorHex = colorHex
        self.isReminder = isReminder
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

    public init(id: String, title: String, notes: String?, location: String?, url: String?,
                start: Date, end: Date?, isAllDay: Bool, calendar: AppleCalendarInfo) {
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

    public init(id: String, title: String, notes: String?, due: Date?, dueHasTime: Bool,
                isCompleted: Bool, completedAt: Date?, priority: Int?, calendar: AppleCalendarInfo) {
        self.id = id
        self.title = title
        self.notes = notes
        self.due = due
        self.dueHasTime = dueHasTime
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.priority = priority
        self.calendar = calendar
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

    public init(events: [AppleCalendarEvent], reminders: [AppleReminder]) {
        self.events = events
        self.reminders = reminders
    }
}
