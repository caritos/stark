// ios/App/Stark/Stark/PlannerSupport.swift
import SwiftUI
import UIKit
import StarkKit

/// A block or timed task being dragged.
struct Lift: Equatable {
    let id: String
    /// Finger's distance below the item's top edge when it was lifted.
    let grabOffset: CGFloat
    var globalY: CGFloat
}

/// Press-and-hold, then drag (iOS 18+). A `UILongPressGestureRecognizer` keeps reporting
/// `.changed` as the finger moves after the hold, and fails if the finger moves first, which
/// leaves the swipe to the scroll view. Locations are global.
@available(iOS 18.0, *)
struct LiftRecognizer: UIGestureRecognizerRepresentable {
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint, Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.25
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = context.converter.location(in: .global)
        switch recognizer.state {
        case .began: onBegan(point)
        case .changed: onChanged(point)
        case .ended: onEnded(point, false)
        case .cancelled, .failed: onEnded(point, true)
        default: break
        }
    }
}

/// A block whose bottom edge is being dragged.
struct Resize: Equatable {
    let id: String
    let startY: CGFloat
    let baseMinutes: Int
    var minutes: CGFloat
}

/// What the time picker sheet is choosing a time for.
enum TimePick: Identifiable {
    case place(AgendaItem, initial: Date)
    case move(String, initial: Date)

    var id: String {
        switch self {
        case .place(let item, _): return "place-\(item.id)"
        case .move(let id, _): return "move-\(id)"
        }
    }

    var title: String {
        switch self {
        case .place: return "Add to plan"
        case .move: return "Move"
        }
    }

    var initial: Date {
        switch self {
        case .place(_, let date), .move(_, let date): return date
        }
    }
}

/// The non-drag path (VoiceOver, or a tap): pick a start time on the planned day, rounded to
/// the quarter hour (`PlanLayout.snap`), then place or move the item there.
struct PlanTimePicker: View {
    let title: String
    let day: Date
    let onPick: (Date) -> Void

    @Environment(\.dismiss) var dismiss
    @State var time: Date

    static let calendar = Calendar(identifier: .gregorian)

    init(title: String, initial: Date, day: Date, onPick: @escaping (Date) -> Void) {
        self.title = title
        self.day = day
        self.onPick = onPick
        _time = State(initialValue: PlanLayout.snap(initial))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                // Quarter hours only, as `PlanLayout.snap` rounds to; compact on Mac Catalyst.
                QuarterHourDatePicker("Start", selection: $time, components: .time, style: .wheel)
                Text("Rounded to the nearest 15 minutes.")
                    .font(Fonts.mono(11))
                    .foregroundStyle(Colors.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(Colors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Colors.background, for: .navigationBar)
            .toolbar {
                SquareToolbarButton(systemImage: "checkmark", label: title, placement: .confirmationAction,
                                    isProminent: true) {
                    onPick(startOnDay())
                    dismiss()
                }
                SquareToolbarButton(systemImage: "xmark", label: "Cancel", placement: .cancellationAction) { dismiss() }
            }
        }
        .presentationDetents([.medium])
        .tint(Colors.accent)
    }

    /// The picked hour and minute on the planned day, snapped to the quarter hour.
    private func startOnDay() -> Date {
        let parts = Self.calendar.dateComponents([.hour, .minute], from: time)
        let start = Self.calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0,
                                       of: Self.calendar.startOfDay(for: day)) ?? day
        return PlanLayout.snap(start)
    }
}
