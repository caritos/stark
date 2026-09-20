// ios/App/Stark/Stark/AgendaRow.swift
import SwiftUI
import StarkKit

/// One agenda row. Minimal on purpose: completed => leading "✓" + strikethrough title;
/// overdue => trailing "due <missed date>" in the accent color instead of the date.
struct AgendaRowView: View {
    let item: AgendaItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if item.isCompleted {
                Text("✓")
                    .foregroundStyle(Colors.textSecondary)
            }
            Text(item.title)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? Colors.textSecondary : Colors.text)
            Spacer()
            if item.isOverdue {
                Text("due \(item.occurrence.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(Colors.accent)
            } else {
                Text(item.displayDate.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(Colors.textSecondary)
            }
        }
    }
}
