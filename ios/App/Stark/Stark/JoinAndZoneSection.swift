// ios/App/Stark/Stark/JoinAndZoneSection.swift
import SwiftUI
import StarkKit

/// A "Join Zoom" button and, for an event set in another time zone, the time zone card. Shown on
/// the Apple event detail and at the top of the edit sheet. The link is opened only on tap and is
/// never fetched; the card is read-only (Edit never changes an event's time zone). Draws nothing
/// for an event with neither.
struct JoinAndZoneSection: View {
    @Environment(\.openURL) private var openURL
    /// The agenda row as shown (its occurrence's own times), not the stored series master.
    let item: AgendaItem

    var body: some View {
        let link = item.conferenceLink
        let card = item.timeZoneCard(phoneZone: .current, locale: .current)
        if link != nil || card != nil {
            Section {
                if let link {
                    Button { openURL(link.url) } label: {
                        Label(link.title, systemImage: "video.fill")
                            .foregroundStyle(Colors.accent)
                    }
                    .accessibilityLabel(link.accessibilityLabel)
                    .accessibilityHint("Opens the meeting link")
                }
                if let card {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TIME ZONE")
                            .font(Fonts.mono(11))
                            .foregroundStyle(Colors.textSecondary)
                        Text("\(card.zoneName) · \(card.eventRange)")
                            .foregroundStyle(Colors.text)
                        Text("Your time \(card.yourRange)")
                            .font(.footnote)
                            .foregroundStyle(Colors.textSecondary)
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Time zone \(card.zoneName), \(card.eventRange). Your time \(card.yourRange)")
                }
            }
            .listRowBackground(Colors.card)
        }
    }
}
