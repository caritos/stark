// ios/Tests/StarkKitTests/ItemDeletePromptTests.swift
import Testing
import Foundation
@testable import StarkKit

@Suite("ItemDeletePrompt")
struct ItemDeletePromptTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func eventDetails(unrepresentable: Bool = false, attendees: Bool = false,
                              inviteeOnly: Bool = false) -> ItemDetails {
        ItemDetails(event: Event(id: "apple-E1", title: "Board", start: start), calendarID: "cal",
                    isInviteeOnly: inviteeOnly, hasUnrepresentableRepeat: unrepresentable,
                    hasAttendees: attendees)
    }

    @Test("Stark's own items keep their wording")
    func localItems() {
        #expect(ItemDeletePrompt.message(isRecurring: false, appleApp: nil, details: nil) == "This cannot be undone.")
        #expect(ItemDeletePrompt.message(isRecurring: true, appleApp: nil, details: nil)
                == "This deletes all future occurrences.")
        #expect(ItemDeletePrompt.isSeries(isRecurring: true, details: nil))
        #expect(!ItemDeletePrompt.isSeries(isRecurring: false, details: nil))
    }

    @Test("an Apple one-off and a representable series name the app")
    func appleItems() {
        #expect(ItemDeletePrompt.message(isRecurring: false, appleApp: "Calendar", details: eventDetails())
                == "This deletes it from Calendar.")
        #expect(ItemDeletePrompt.message(isRecurring: true, appleApp: "Reminders", details: nil)
                == "This deletes every occurrence from Reminders.")
    }

    @Test("a repeat Stark can't represent is still a series: delete names every occurrence and one occurrence can be removed")
    func unrepresentableRepeatIsASeries() {
        let details = eventDetails(unrepresentable: true)
        #expect(ItemDeletePrompt.isSeries(isRecurring: false, details: details))
        #expect(ItemDeletePrompt.message(isRecurring: false, appleApp: "Calendar", details: details)
                == "This deletes every occurrence from Calendar.")
        #expect(EventOutcomeActions(outcome: nil, isRecurring: ItemDeletePrompt.isSeries(isRecurring: false, details: details))
                    .showsRemoveOccurrence)
    }

    @Test("an event the owner organises with invitees says they may be notified; an invitee-only one does not")
    func attendees() {
        #expect(ItemDeletePrompt.message(isRecurring: false, appleApp: "Calendar", details: eventDetails(attendees: true))
                == "This deletes it from Calendar. It has invitees, who may be notified.")
        #expect(ItemDeletePrompt.message(isRecurring: true, appleApp: "Calendar", details: eventDetails(attendees: true))
                == "This deletes every occurrence from Calendar. It has invitees, who may be notified.")
        #expect(ItemDeletePrompt.message(isRecurring: false, appleApp: "Calendar",
                                         details: eventDetails(attendees: true, inviteeOnly: true))
                == "This deletes it from Calendar.")
    }
}
