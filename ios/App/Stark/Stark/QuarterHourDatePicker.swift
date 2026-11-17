// ios/App/Stark/Stark/QuarterHourDatePicker.swift
import SwiftUI
import UIKit
import StarkKit

/// A date/time picker whose minute wheel offers only :00, :15, :30 and :45. SwiftUI's
/// `DatePicker` has no minute step, so this wraps `UIDatePicker` with `minuteInterval = 15`.
///
/// The binding is written ONLY when the user changes the picker (its `.valueChanged` action),
/// never from `updateUIView`, so an existing item at an odd minute (10:07) keeps its exact time
/// until the owner edits it, even though the pill shows it floored (10:00). Changing only the
/// day keeps the odd time too. External changes (the
/// end following the start, the All day toggle) are pushed into the picker without echoing back.
struct QuarterHourDatePicker: View {
    enum Components { case date, time, dateAndTime }
    enum Style { case compact, wheel }

    let title: String
    @Binding var selection: Date
    var minimumDate: Date?
    let components: Components
    var style: Style = .compact

    init(_ title: String, selection: Binding<Date>, minimumDate: Date? = nil,
         components: Components, style: Style = .compact) {
        self.title = title
        _selection = selection
        self.minimumDate = minimumDate
        self.components = components
        self.style = style
    }

    var body: some View {
        switch resolvedStyle {
        case .compact:
            // Looks like the stock DatePicker row: the label on the left, the pills on the right.
            LabeledContent(title) {
                picker
            }
        case .wheel:
            picker
        }
    }

    private var picker: some View {
        QuarterHourPickerRepresentable(title: title, selection: $selection, minimumDate: minimumDate,
                                       components: components, style: resolvedStyle)
    }

    /// The wheel does not exist on Mac Catalyst; it gets the compact pills there.
    private var resolvedStyle: Style {
        #if targetEnvironment(macCatalyst)
        return .compact
        #else
        return style
        #endif
    }
}

private struct QuarterHourPickerRepresentable: UIViewRepresentable {
    let title: String
    @Binding var selection: Date
    let minimumDate: Date?
    let components: QuarterHourDatePicker.Components
    let style: QuarterHourDatePicker.Style

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.minuteInterval = QuarterHour.minutes
        picker.preferredDatePickerStyle = style == .wheel ? .wheels : .compact
        picker.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)),
                         for: .valueChanged)
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        configure(picker)
        return picker
    }

    /// A compact UIDatePicker only knows its size from Auto Layout; without this SwiftUI gives it
    /// almost none (an empty pill). It takes the width it is offered (the row's room right of the
    /// label): sized to its compressed width, UIKit sometimes switches the date pill to the short
    /// "11/18/26" style.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        let fitting = uiView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        guard let width = proposal.width, width.isFinite, width > fitting.width else { return fitting }
        return CGSize(width: width, height: fitting.height)
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.selection = $selection
        configure(picker)
    }

    /// Pushes the current state into the picker. Setting `date` programmatically sends no
    /// `.valueChanged`, so nothing here writes back to the binding.
    private func configure(_ picker: UIDatePicker) {
        let mode: UIDatePicker.Mode = switch components {
        case .date: .date
        case .time: .time
        case .dateAndTime: .dateAndTime
        }
        if picker.datePickerMode != mode {
            picker.datePickerMode = mode
            picker.invalidateIntrinsicContentSize()
        }
        if picker.minimumDate != minimumDate { picker.minimumDate = minimumDate }
        if picker.date != selection { picker.setDate(selection, animated: false) }
        picker.tintColor = UIColor(Colors.accent)
        picker.accessibilityLabel = title
    }

    final class Coordinator: NSObject {
        var selection: Binding<Date>

        init(selection: Binding<Date>) { self.selection = selection }

        /// The user moved the picker: the only place the binding is written. The picker reports
        /// its shown (floored) time even when only the day was changed, so an odd time the owner
        /// did not touch is kept (`QuarterHour.keepingUntouchedTime`).
        @objc func valueChanged(_ picker: UIDatePicker) {
            let value = QuarterHour.keepingUntouchedTime(picked: picker.date,
                                                         previous: selection.wrappedValue,
                                                         calendar: picker.calendar ?? .current)
            if selection.wrappedValue != value { selection.wrappedValue = value }
        }
    }
}
