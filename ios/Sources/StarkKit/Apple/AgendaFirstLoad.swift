// ios/Sources/StarkKit/Apple/AgendaFirstLoad.swift
import Foundation

/// Whether the agenda is still waiting for its first Apple fetch after launch.
///
/// Stark keeps no items of its own, so until the first EventKit fetch lands the agenda would show
/// "No Events" under every day and then jump when the rows arrive. While waiting (only with full
/// access: without it the access screen shows at once), the agenda shows a quiet loading state
/// instead and is revealed only once it has been scrolled to today. A failed first fetch ends the
/// wait too, so a failure never leaves a spinner on screen.
public struct AgendaFirstLoad: Equatable, Sendable {
    /// True once any fetch has finished, landed or failed. Never goes back to false.
    public private(set) var hasFinishedOnce = false

    public init() {}

    /// A fetch finished (its result applied, or it failed).
    public mutating func fetchFinished() {
        hasFinishedOnce = true
    }

    /// The loading state shows: access is granted and no fetch has finished yet.
    public func isWaiting(access: AppleAccess) -> Bool {
        access == .granted && !hasFinishedOnce
    }

    /// The agenda list is kept invisible: still waiting, or the data is in but the list has not
    /// yet been scrolled to today (`isPositioned`), so its first frames never show the window's
    /// first day before the jump to today.
    public func hidesAgenda(access: AppleAccess, isPositioned: Bool) -> Bool {
        guard access == .granted else { return false }
        return !hasFinishedOnce || !isPositioned
    }
}
