import Foundation

public enum ICSSerializer {
    public static func serialize(event: Event) -> String {
        var lines = ["BEGIN:VEVENT", "UID:\(event.id)", "SUMMARY:\(escape(event.title))"]
        lines.append("DTSTART\(dateParam(event.isAllDay)):\(ICSDateFormat.format(event.start, allDay: event.isAllDay))")
        if let end = event.end {
            lines.append("DTEND\(dateParam(event.isAllDay)):\(ICSDateFormat.format(end, allDay: event.isAllDay))")
        }
        if let notes = event.notes { lines.append("DESCRIPTION:\(escape(notes))") }
        if let location = event.location { lines.append("LOCATION:\(escape(location))") }
        // A URI value: no TEXT escaping (a comma or semicolon is part of the URL). CR/LF are
        // stripped so a pasted value can never start a new property line.
        if let url = event.url {
            lines.append("URL:\(url.filter { !$0.isNewline })")
        }
        if let recurrence = event.recurrence { lines.append("RRULE:\(RRuleCodec.encode(recurrence))") }
        for exdate in event.exceptionDates {
            lines.append("EXDATE\(dateParam(event.isAllDay)):\(ICSDateFormat.format(exdate, allDay: event.isAllDay))")
        }
        for record in event.outcomes {
            let name = record.outcome == .attended ? "X-STARK-ATTENDED" : "X-STARK-SKIPPED"
            lines.append("\(name)\(dateParam(event.isAllDay)):\(ICSDateFormat.format(record.date, allDay: event.isAllDay))")
        }
        lines.append("END:VEVENT")
        return lines.joined(separator: "\r\n")
    }

    public static func serialize(reminder: Reminder) -> String {
        var lines = ["BEGIN:VTODO", "UID:\(reminder.id)", "SUMMARY:\(escape(reminder.title))"]
        if let due = reminder.dueDate { lines.append("DUE:\(ICSDateFormat.format(due, allDay: false))") }
        if let notes = reminder.notes { lines.append("DESCRIPTION:\(escape(notes))") }
        if let priority = reminder.priority { lines.append("PRIORITY:\(priority)") }
        lines.append("STATUS:\(reminder.isCompleted ? "COMPLETED" : "NEEDS-ACTION")")
        if let completed = reminder.completedDate { lines.append("COMPLETED:\(ICSDateFormat.format(completed, allDay: false))") }
        if let recurrence = reminder.recurrence { lines.append("RRULE:\(RRuleCodec.encode(recurrence))") }
        for exdate in reminder.exceptionDates {
            lines.append("EXDATE:\(ICSDateFormat.format(exdate, allDay: false))")
        }
        lines.append("END:VTODO")
        return lines.joined(separator: "\r\n")
    }

    public static func serialize(events: [Event], reminders: [Reminder]) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Stark//EN"]
        lines.append(contentsOf: events.map(serialize(event:)))
        lines.append(contentsOf: reminders.map(serialize(reminder:)))
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func dateParam(_ allDay: Bool) -> String { allDay ? ";VALUE=DATE" : "" }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
