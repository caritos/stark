// ios/App/Stark/Stark/CalendarSidebar.swift
import SwiftUI
import StarkKit

/// Mac Catalyst's replacement for `ModeHandle`'s drag gesture: a sidebar list that selects
/// `CalendarMode` directly. `ModeHandle`'s drag/tap gesture has no pointer/hover affordance and
/// isn't a Mac-appropriate interaction (see the portability notes in the Mac Catalyst target
/// design doc), so on Mac the same `mode` state `ContentView` already owns is driven by picking
/// a row here instead. iPhone keeps using `ModeHandle`; this view is only ever built inside
/// `#if targetEnvironment(macCatalyst)` in `ContentView`.
struct CalendarSidebar: View {
    @Binding var mode: CalendarMode

    private static let modes: [CalendarMode] = [.week, .month, .year]

    var body: some View {
        List(selection: modeSelection) {
            ForEach(Self.modes, id: \.self) { candidate in
                Text(candidate.title)
                    .foregroundStyle(Colors.text)
                    .tag(candidate)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Stark")
    }

    /// `List(selection:)` requires an `Optional<CalendarMode>` binding (a sidebar list can have
    /// nothing selected); `mode` itself is always non-optional, so this adapts between the two
    /// without ever writing `nil` back into `mode`.
    private var modeSelection: Binding<CalendarMode?> {
        Binding(
            get: { mode },
            set: { newValue in
                guard let newValue else { return }
                mode = newValue
            }
        )
    }
}
