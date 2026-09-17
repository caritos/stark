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

            if case .reminder(let reminder, let occurrence) = item, !reminder.isCompleted {
                Button("Done") {
                    store.completeReminder(id: reminder.id, on: occurrence)
                    dismiss()
                }
            }

            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .confirmationDialog(deleteMessage, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                switch item {
                case .event(let event, _): store.deleteEvent(id: event.id)
                case .reminder(let reminder, _): store.deleteReminder(id: reminder.id)
                }
                dismiss()
            }
        }
    }

    private var isRecurring: Bool {
        switch item {
        case .event(let e, _): return e.recurrence != nil
        case .reminder(let r, _): return r.recurrence != nil
        }
    }

    private var deleteMessage: String {
        isRecurring
            ? "This deletes all future occurrences."
            : "This cannot be undone."
    }
}
