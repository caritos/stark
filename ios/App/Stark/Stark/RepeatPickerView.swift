// ios/App/Stark/Stark/RepeatPickerView.swift
import SwiftUI
import StarkKit

enum RepeatPreset: String, CaseIterable, Identifiable {
    case never = "Never"
    case everyDay = "Every Day"
    case everyWeek = "Every Week"
    case every2Weeks = "Every 2 Weeks"
    case everyMonth = "Every Month"
    case everyYear = "Every Year"
    case custom = "Custom"

    var id: String { rawValue }

    var rule: RecurrenceRule? {
        switch self {
        case .never: return nil
        case .everyDay: return RecurrenceRule(frequency: .daily)
        case .everyWeek: return RecurrenceRule(frequency: .weekly)
        case .every2Weeks: return RecurrenceRule(frequency: .weekly, interval: 2)
        case .everyMonth: return RecurrenceRule(frequency: .monthly)
        case .everyYear: return RecurrenceRule(frequency: .yearly)
        case .custom: return nil
        }
    }
}

struct RepeatPickerView: View {
    @Binding var recurrence: RecurrenceRule?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(RepeatPreset.allCases) { preset in
                if preset == .custom {
                    NavigationLink(preset.rawValue) {
                        CustomRepeatView(recurrence: $recurrence)
                    }
                    .foregroundStyle(Colors.text)
                } else {
                    Button {
                        recurrence = preset.rule
                        dismiss()
                    } label: {
                        HStack {
                            Text(preset.rawValue).foregroundStyle(Colors.text)
                            Spacer()
                            if preset.rule == recurrence {
                                Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Repeat")
    }
}
