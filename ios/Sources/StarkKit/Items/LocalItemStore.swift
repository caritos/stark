// ios/Sources/StarkKit/Items/LocalItemStore.swift
import Foundation

/// The `PlannerStore` operations the views call, extracted so `ItemRouter` can be tested with a
/// fake. The signatures are `PlannerStore`'s own (without their default arguments); the conformance
/// below adds nothing, so the store behaves exactly as before.
@MainActor
public protocol LocalItemStore: AnyObject {
    func addEvent(_ event: Event)
    func addReminder(_ reminder: Reminder)
    func updateEvent(_ event: Event)
    func updateReminder(_ reminder: Reminder)
    func deleteEvent(id: String)
    func deleteReminder(id: String)
    func completeReminder(id: String, on date: Date, today: Date, now: Date)
    func uncompleteReminder(id: String)
    func skipEvent(id: String, on date: Date)
    func skipReminder(id: String, on date: Date, today: Date)
    func setEventOutcome(id: String, on date: Date, outcome: EventOutcome?, now: Date)
    func convertEvent(id: String, to reminder: Reminder) -> Bool
    func convertReminder(id: String, to event: Event) -> Bool
    func plans(on day: Date) -> [PlanBlock]
    func replacePlans(on day: Date, with blocks: [PlanBlock]) -> Bool
}

extension PlannerStore: LocalItemStore {}

/// Where new Apple items go: the default calendar for events and the default list for reminders,
/// nil when none is chosen or available. The app's destination model conforms.
@MainActor
public protocol DefaultDestinations {
    var calendarID: String? { get }
    var listID: String? { get }
}
