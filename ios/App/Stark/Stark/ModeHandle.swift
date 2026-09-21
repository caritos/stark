// ios/App/Stark/Stark/ModeHandle.swift
import SwiftUI
import StarkKit

/// The drag bar between the calendar grid and the agenda: a flat 40 x 4 bar centred in a
/// full-width strip. It is visuals plus one gesture; the rule for what a drag does lives in
/// `CalendarMode.afterDrag` (StarkKit, tested), so nothing here decides anything. Drag up
/// collapses, down expands, and the switch happens once, on release, animated (the grid does not
/// follow the finger). It is a separate strip, not an overlay, so it never covers the grid above
/// or the agenda below.
///
/// In year mode, where the bar sits at the bottom of the year grid, tapping it also returns to
/// month; in the other modes a tap does nothing.
struct ModeHandle: View {
    @Binding var mode: CalendarMode

    private static let stripHeight: CGFloat = 20
    private static let barSize = CGSize(width: 40, height: 4)

    var body: some View {
        Rectangle()
            .fill(Colors.checkboxBorder)
            .frame(width: Self.barSize.width, height: Self.barSize.height)
            .frame(maxWidth: .infinity, minHeight: Self.stripHeight, maxHeight: Self.stripHeight)
            // The whole strip is draggable, not just the 4 pt bar.
            .contentShape(Rectangle())
            .onTapGesture {
                if mode == .year { move(to: .month) }
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        move(to: mode.afterDrag(
                            translation: value.translation.height,
                            predictedEnd: value.predictedEndTranslation.height
                        ))
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calendar view")
            .accessibilityValue(mode.title)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(to: mode.expanded)
                case .decrement: move(to: mode.collapsed)
                @unknown default: break
                }
            }
    }

    private func move(to target: CalendarMode?) {
        guard let target, target != mode else { return }
        withAnimation(.easeInOut(duration: 0.2)) { mode = target }
    }
}
