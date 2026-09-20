// ios/App/Stark/Stark/EditItemView.swift
import SwiftUI
import StarkKit

struct EditItemView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    let item: AgendaItem
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            Text(item.title).foregroundStyle(Colors.text)

            if case .reminder(let reminder) = item.kind, !reminder.isCompleted {
                Button("Done") {
                    store.completeReminder(id: reminder.id, on: item.occurrence)
                    dismiss()
                }
            }

            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .confirmationDialog(deleteMessage, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                switch item.kind {
                case .event(let event): store.deleteEvent(id: event.id)
                case .reminder(let reminder): store.deleteReminder(id: reminder.id)
                }
                dismiss()
            }
        }
    }

    private var deleteMessage: String {
        item.isRecurring
            ? "This deletes all future occurrences."
            : "This cannot be undone."
    }
}
