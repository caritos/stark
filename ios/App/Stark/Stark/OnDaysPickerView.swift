import SwiftUI

struct OnDaysPickerView: View {
    @Binding var selectedDays: Set<Int>

    var body: some View {
        List {
            // The real last day of whichever month it is (28-31), stored as -1 (issue #112).
            // Combines with numbered days ("the 15th and the last day").
            row(label: "Last day of the month", value: -1)
            ForEach(1...31, id: \.self) { day in
                row(label: "\(day)", value: day)
            }
        }
        .navigationTitle("On Days")
    }

    private func row(label: String, value: Int) -> some View {
        Button {
            toggle(value)
        } label: {
            HStack {
                Text(label).foregroundStyle(Colors.text)
                Spacer()
                if selectedDays.contains(value) {
                    Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                }
            }
        }
    }

    private func toggle(_ day: Int) {
        if selectedDays.contains(day) { selectedDays.remove(day) } else { selectedDays.insert(day) }
    }
}
