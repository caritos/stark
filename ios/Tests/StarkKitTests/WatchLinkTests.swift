import Foundation
import Testing
@testable import StarkKit

@Suite("WatchLink")
struct WatchLinkTests {
    @Test("an envelope round-trips through JSON for both command kinds")
    func envelopeRoundTripsThroughJSON() throws {
        let sent = Date(timeIntervalSinceReferenceDate: 815_000_000.25)
        let draft = WatchAddDraft(kind: .event, title: "Lunch", start: sent.addingTimeInterval(3600),
                                  end: sent.addingTimeInterval(7200), isAllDay: false,
                                  recurrence: RecurrenceRule(frequency: .weekly), summary: "Tomorrow at 1:00 PM")
        let envelopes = [
            WatchEnvelope(id: UUID(), sentAt: sent,
                          command: .complete(identifier: "R1", externalID: "ext-R1", occurrence: sent)),
            WatchEnvelope(id: UUID(), sentAt: sent,
                          command: .complete(identifier: "R2", externalID: nil, occurrence: sent)),
            WatchEnvelope(id: UUID(), sentAt: sent, command: .add(draft)),
        ]
        for envelope in envelopes {
            let data = try WatchLinkCoding.encode(envelope)
            #expect(try WatchLinkCoding.decode(WatchEnvelope.self, from: data) == envelope)
        }
        let replies = [
            WatchReplyEnvelope(id: UUID(), reply: .done(notice: "Added to Home · iCloud", warning: nil)),
            WatchReplyEnvelope(id: UUID(), reply: .failed("nope")),
        ]
        for reply in replies {
            let data = try WatchLinkCoding.encode(reply)
            #expect(try WatchLinkCoding.decode(WatchReplyEnvelope.self, from: data) == reply)
        }
    }
}
