// ios/Sources/StarkKit/Items/ItemDeletePrompt.swift
import Foundation

/// What the edit sheet's Delete confirmation says, and whether the item counts as a series (which
/// also offers "Remove This Occurrence" for an event).
public enum ItemDeletePrompt {
    /// The item repeats: its own rule, or an Apple repeat Stark can't represent (that rule reads as
    /// nil, so `isRecurring` is false, but Apple still deletes the whole series).
    public static func isSeries(isRecurring: Bool, details: ItemDetails?) -> Bool {
        isRecurring || details?.hasUnrepresentableRepeat == true
    }

    /// `appleApp` is "Calendar" or "Reminders" for an Apple item, nil for Stark's own. An event
    /// the owner organises with invitees adds that they may be notified (deleting it in Apple can
    /// send them a cancellation, depending on the account).
    public static func message(isRecurring: Bool, appleApp: String?, details: ItemDetails?) -> String {
        let series = isSeries(isRecurring: isRecurring, details: details)
        guard let appleApp else {
            return series ? "This deletes all future occurrences." : "This cannot be undone."
        }
        var text = series ? "This deletes every occurrence from \(appleApp)." : "This deletes it from \(appleApp)."
        if let details, details.event != nil, details.hasAttendees, !details.isInviteeOnly {
            text += " It has invitees, who may be notified."
        }
        return text
    }
}
