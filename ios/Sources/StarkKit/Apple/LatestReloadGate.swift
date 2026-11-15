// ios/Sources/StarkKit/Apple/LatestReloadGate.swift
import Foundation

/// Sequences overlapping reloads of one snapshot (the Apple overlay).
///
/// - Only the newest reload's result is applied: an older fetch that finishes late is dropped, so
///   it can never overwrite a newer snapshot.
/// - A caller of `run` returns only once the newest reload in flight has finished (applied,
///   failed, or dropped by going inactive), not merely its own fetch. A caller that moves the
///   window after `await run(...)` therefore never shows the new range before the data that
///   actually lands. The follow is bounded: after its own fetch a caller awaits at most
///   `maxFollows` newer reloads, one after the other, then returns even if more keep arriving.
/// - `active: false` (overlay off or access not granted) drops anything in flight, calls `clear`
///   and returns at once without fetching; waiters on dropped reloads return when their fetch ends.
@MainActor
public final class LatestReloadGate {
    private let maxFollows: Int
    private var generation = 0
    /// The newest reload still worth waiting for; nil after going inactive.
    private var latest: (generation: Int, task: Task<Void, Never>)?

    public init(maxFollows: Int = 3) {
        self.maxFollows = maxFollows
    }

    public func run<T>(
        active: Bool,
        fetch: @escaping @MainActor () async throws -> T,
        apply: @escaping @MainActor (T) -> Void,
        failed: @escaping @MainActor (Error) -> Void,
        clear: @MainActor () -> Void
    ) async {
        guard active else {
            invalidate()
            clear()
            return
        }
        generation += 1
        let mine = generation
        let task = Task { @MainActor [weak self] in
            do {
                let result = try await fetch()
                guard let self, mine == self.generation else { return }
                apply(result)
            } catch {
                failed(error)
            }
        }
        latest = (mine, task)
        await task.value
        var awaited = mine
        var follows = 0
        while follows < maxFollows, let next = latest, next.generation > awaited {
            follows += 1
            awaited = next.generation
            await next.task.value
        }
        if latest?.generation == mine { latest = nil }
    }

    /// Drops every reload in flight (its result will not be applied) without starting one.
    public func invalidate() {
        generation += 1
        latest = nil
    }
}
