import SwiftUI

struct OnDaysPickerView: View {
    @Binding var selectedDays: Set<Int>

    var body: some View {
        List {
            ForEach(1...31, id: \.self) { day in
                Button {
                    toggle(day)
                } label: {
                    HStack {
                        Text("\(day)").foregroundStyle(Colors.text)
                        Spacer()
                        if selectedDays.contains(day) {
                            Image(systemName: "checkmark").foregroundStyle(Colors.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle("On Days")
    }

    private func toggle(_ day: Int) {
        if selectedDays.contains(day) { selectedDays.remove(day) } else { selectedDays.insert(day) }
    }
}
