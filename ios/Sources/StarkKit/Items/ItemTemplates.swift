// ios/Sources/StarkKit/Items/ItemTemplates.swift
import Foundation

/// Which kind of item a template makes. (The app's own `ItemKind` lives in the app target.)
public enum TemplateKind: String, Codable, Equatable, Hashable, Sendable {
    case event, reminder
}

extension ReminderPriority: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = ReminderPriority(rawValue: raw) ?? .none
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// What the Add form holds when the owner saves a template. Carries no start or end date: a
/// template never stores a date or time of day, only a length.
public struct TemplateSnapshot: Equatable, Sendable {
    public var kind: TemplateKind
    public var title: String
    /// End minus start in minutes (events); ignored for reminders and all-day items.
    public var durationMinutes: Int?
    public var allDay: Bool
    public var notes: String?
    public var url: String?
    public var priority: ReminderPriority
    public var recurrence: RecurrenceRule?
    public var destinationID: String?

    public init(kind: TemplateKind, title: String, durationMinutes: Int?, allDay: Bool, notes: String?,
                url: String?, priority: ReminderPriority, recurrence: RecurrenceRule?, destinationID: String?) {
        self.kind = kind
        self.title = title
        self.durationMinutes = durationMinutes
        self.allDay = allDay
        self.notes = notes
        self.url = url
        self.priority = priority
        self.recurrence = recurrence
        self.destinationID = destinationID
    }
}

/// A saved starting point for a new item. Never holds a date.
public struct ItemTemplate: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: TemplateKind
    public var title: String
    public var durationMinutes: Int?
    public var allDay: Bool
    public var notes: String?
    public var url: String?
    public var priority: ReminderPriority
    /// Stored without its end (`withoutEnd`).
    public var recurrence: RecurrenceRule?
    public var destinationID: String?

    public init(id: UUID = UUID(), name: String, kind: TemplateKind, title: String, durationMinutes: Int?,
                allDay: Bool, notes: String?, url: String?, priority: ReminderPriority,
                recurrence: RecurrenceRule?, destinationID: String?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.title = title
        self.durationMinutes = durationMinutes
        self.allDay = allDay
        self.notes = notes
        self.url = url
        self.priority = priority
        self.recurrence = recurrence
        self.destinationID = destinationID
    }
}

public enum TemplateError: Error, Equatable, Sendable {
    case emptyName, nameTooLong, duplicateName, tooMany, emptyTitle, notFound

    public var message: String {
        switch self {
        case .emptyName: return "Give the template a name."
        case .nameTooLong: return "Use 30 characters or fewer."
        case .duplicateName: return "Another template already has that name."
        case .tooMany: return "You can keep up to 50 templates. Delete one first."
        case .emptyTitle: return "Type a title before saving a template."
        case .notFound: return "That template no longer exists."
        }
    }
}

/// The saved templates (value type, like `CalendarSets`).
public struct ItemTemplates: Equatable, Sendable {
    public static let maxNameLength = 30
    public static let maxTemplates = 50
    static let currentVersion = 1

    public private(set) var templates: [ItemTemplate]

    public init(templates: [ItemTemplate] = []) {
        self.templates = templates
    }

    private func validated(_ name: String, excluding id: UUID?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw TemplateError.emptyName }
        if trimmed.count > Self.maxNameLength { throw TemplateError.nameTooLong }
        let clash = templates.contains {
            $0.id != id && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
        if clash { throw TemplateError.duplicateName }
        return trimmed
    }

    @discardableResult
    public mutating func add(name: String, from form: TemplateSnapshot, id: UUID = UUID()) throws -> ItemTemplate {
        let clean = try validated(name, excluding: nil)
        guard let title = FormFields.trimmedOrNil(form.title) else { throw TemplateError.emptyTitle }
        if templates.count >= Self.maxTemplates { throw TemplateError.tooMany }
        let isEvent = form.kind == .event
        let template = ItemTemplate(
            id: id, name: clean, kind: form.kind, title: title,
            durationMinutes: isEvent && !form.allDay ? form.durationMinutes.map { max($0, 0) } : nil,
            allDay: form.allDay,
            notes: form.notes.flatMap(FormFields.trimmedOrNil),
            url: isEvent ? form.url.flatMap(FormFields.trimmedOrNil) : nil,
            priority: isEvent ? .none : form.priority,
            recurrence: form.recurrence?.withoutEnd,
            destinationID: form.destinationID)
        templates.append(template)
        return template
    }

    public mutating func rename(_ id: UUID, to name: String) throws {
        guard let i = templates.firstIndex(where: { $0.id == id }) else { throw TemplateError.notFound }
        templates[i].name = try validated(name, excluding: id)
    }

    public mutating func delete(_ id: UUID) {
        templates.removeAll { $0.id == id }
    }

    public func templates(for kind: TemplateKind) -> [ItemTemplate] {
        templates.filter { $0.kind == kind }
    }

    private struct Envelope: Codable {
        var version: Int
        var templates: [ItemTemplate]
    }

    private struct VersionOnly: Decodable {
        var version: Int
    }

    /// Missing, corrupt or newer-version data decodes to no templates (never throws).
    public static func decode(_ data: Data?) -> ItemTemplates {
        guard let data,
              let v = try? JSONDecoder().decode(VersionOnly.self, from: data),
              v.version == currentVersion,
              let env = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return ItemTemplates() }
        return ItemTemplates(templates: env.templates)
    }

    public func encoded() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(Envelope(version: Self.currentVersion, templates: templates))) ?? Data()
    }
}

/// What applying a template sets on the Add form. The start is never touched; `end` is computed
/// from the form's current start.
public struct TemplateFormValues: Equatable, Sendable {
    public var title: String
    public var notes: String?
    public var url: String?
    public var priority: ReminderPriority
    public var recurrence: RecurrenceRule?
    public var allDay: Bool
    public var end: Date
    /// nil when the saved calendar/list is gone (keep the default).
    public var destinationID: String?

    public init(_ template: ItemTemplate, start: Date, offeredDestinationIDs: Set<String>) {
        title = template.title
        notes = template.notes
        url = template.url
        priority = template.priority
        recurrence = template.recurrence
        allDay = template.allDay
        if let minutes = template.durationMinutes, !template.allDay {
            end = start.addingTimeInterval(TimeInterval(minutes) * 60)
        } else {
            end = start.addingTimeInterval(EventSchedule.defaultDuration)
        }
        destinationID = template.destinationID.flatMap { offeredDestinationIDs.contains($0) ? $0 : nil }
    }
}
