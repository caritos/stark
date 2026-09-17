import Testing
import Foundation
@testable import StarkKit

@Suite("Models")
struct ModelsTests {
    @Test("Event defaults to no recurrence, no exceptions, not all-day")
    func eventDefaults() {
        let event = Event(title: "Standup", start: Date())
        #expect(event.recurrence == nil)
        #expect(event.exceptionDates.isEmpty)
        #expect(event.isAllDay == false)
    }

    @Test("Reminder defaults to incomplete with no priority")
    func reminderDefaults() {
        let reminder = Reminder(title: "Call dentist")
        #expect(reminder.isCompleted == false)
        #expect(reminder.completedDate == nil)
        #expect(reminder.priority == nil)
    }
}
