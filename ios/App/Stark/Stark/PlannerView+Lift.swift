// ios/App/Stark/Stark/PlannerView+Lift.swift
import SwiftUI
import UIKit
import StarkKit

extension PlannerView {
    // MARK: Lift and drag (blocks, timed tasks)

    /// Where a lifted item is drawn, from the finger's current position and the scroll offset
    /// (so it stays under the finger while the timeline auto-scrolls).
    func liftedY(id: String) -> CGFloat? {
        guard let lift, lift.id == id else { return nil }
        return lift.globalY - contentMinY - lift.grabOffset
    }

    /// What a press-and-drag on a timeline item does.
    struct LiftTarget {
        let id: String
        /// The item's top in timeline content coordinates.
        let top: CGFloat
        /// Blocks only: their length and drawn height. A press on the bottom edge resizes.
        var resizable: (minutes: Int, height: CGFloat)?
        /// Called on release with the new start and whether the finger is over the tray.
        let onDrop: (Date, Bool) -> Bool
    }

    /// Press briefly, then drag: a plain swipe over a block still scrolls the timeline. One
    /// gesture per item, so a move and a resize never compete for the same touch (a separate
    /// grip gesture won SwiftUI's fuzzy hit-test even for presses well above it, seen in the
    /// simulator): on a block, a press on its bottom edge resizes, anywhere else moves.
    ///
    /// On iOS 18+ this is a UIKit long-press recognizer: it fails as soon as the finger moves
    /// before the press is held, so the scroll view's pan takes the swipe. A SwiftUI
    /// `LongPressGesture.sequenced(before: DragGesture)` on the item (as `.gesture` or
    /// `.simultaneousGesture`) stopped every swipe that started on a block from scrolling the
    /// timeline (seen in the iOS 26 simulator). iOS 17 keeps the SwiftUI gesture.
    func liftable<Content: View>(_ content: Content, _ target: LiftTarget) -> some View {
        Group {
            if #available(iOS 18.0, *) {
                content.gesture(LiftRecognizer(
                    onBegan: { liftBegan(target, at: $0) },
                    onChanged: { liftMoved(target, to: $0) },
                    onEnded: { liftEnded(target, at: $0, cancelled: $1) }
                ))
            } else {
                content.gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                        .updating($liftGestureActive) { _, active, _ in active = true }
                        .onChanged { value in
                            guard case .second(true, let drag?) = value else { return }
                            if lift?.id == target.id || resize?.id == target.id {
                                liftMoved(target, to: drag.location)
                            } else {
                                liftBegan(target, at: drag.startLocation)
                                liftMoved(target, to: drag.location)
                            }
                        }
                        .onEnded { value in
                            guard case .second(true, let drag?) = value else { endLift(); return }
                            liftEnded(target, at: drag.location, cancelled: false)
                        }
                )
            }
        }
    }

    /// `point` is in global coordinates.
    private func liftBegan(_ target: LiftTarget, at point: CGPoint) {
        let grab = point.y - contentMinY - target.top
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let resizable = target.resizable,
           grab >= resizable.height - min(Self.gripZone, resizable.height / 3) {
            resize = Resize(id: target.id, startY: point.y, baseMinutes: resizable.minutes,
                            minutes: CGFloat(resizable.minutes))
        } else {
            lift = Lift(id: target.id, grabOffset: grab, globalY: point.y)
        }
    }

    private func liftMoved(_ target: LiftTarget, to point: CGPoint) {
        if let current = resize, current.id == target.id {
            resize?.minutes = CGFloat(current.baseMinutes) + (point.y - current.startY) / Self.hourHeight * 60
        } else if lift?.id == target.id {
            lift?.globalY = point.y
        }
    }

    private func liftEnded(_ target: LiftTarget, at point: CGPoint, cancelled: Bool) {
        defer { endLift() }
        guard !cancelled else { return }
        if let current = resize, current.id == target.id {
            resizeBlock(id: target.id, toMinutes: Int(Double(current.minutes).rounded()))
            return
        }
        guard let lift, lift.id == target.id else { return }
        let overTray = trayFrame.contains(point)
        let topY = point.y - contentMinY - lift.grabOffset
        if !target.onDrop(time(atY: topY), overTray) { refuse() }
    }

    func endLift() {
        lift = nil
        resize = nil
        autoScroll?.cancel()
        autoScroll = nil
    }

    private static func inBottomZone(_ y: CGFloat, viewport: CGRect) -> Bool {
        y > viewport.maxY - edgeZone && y <= viewport.maxY
    }

    /// Scrolls the timeline a quarter hour at a time while a lifted item is held within
    /// `edgeZone` of its top or bottom edge. Stops when the finger leaves the zone or drops.
    func updateAutoScroll(globalY: CGFloat?, proxy: ScrollViewProxy) {
        guard let globalY, viewportFrame.height > 0 else {
            autoScroll?.cancel(); autoScroll = nil; return
        }
        let direction: Int
        if globalY < viewportFrame.minY + Self.edgeZone { direction = -1 }
        // The bottom zone ends at the timeline's own bottom edge: below it is the tray, where a
        // hovering block is about to be dropped (removed), not scrolled.
        else if Self.inBottomZone(globalY, viewport: viewportFrame) { direction = 1 }
        else { direction = 0 }
        guard direction != 0 else { autoScroll?.cancel(); autoScroll = nil; return }
        guard autoScroll == nil else { return }
        autoScroll = Task { @MainActor in
            while !Task.isCancelled, let current = lift?.globalY {
                let up = current < viewportFrame.minY + Self.edgeZone
                let down = Self.inBottomZone(current, viewport: viewportFrame)
                guard up || down else { break }
                let visibleTop = viewportFrame.minY - contentMinY
                let topSlot = Int((visibleTop / Self.slotHeight).rounded())
                if up {
                    guard topSlot > 0 else { break }
                    withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(Self.slotID(topSlot - 1), anchor: .top) }
                } else {
                    // The first slot not wholly visible below: anchoring its bottom edge to the
                    // viewport's always moves at least one slot. (`topSlot + visibleSlots`
                    // could land on the slot already at the bottom when the viewport is not a
                    // whole number of slots tall, and the scroll then stalled; seen in the
                    // simulator.)
                    let bottomSlot = Int(((visibleTop + viewportFrame.height) / Self.slotHeight).rounded(.up))
                    guard bottomSlot < slotCount else { break }
                    withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(Self.slotID(bottomSlot), anchor: .bottom) }
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
            autoScroll = nil
        }
    }
}
