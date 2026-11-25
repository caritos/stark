import Foundation

/// Serialises and coalesces rebuilds: requests made before a build starts share it (after `delay`),
/// a request during a build causes exactly one follow-up build after it, and two builds never run
/// at once, so the last build to finish is always the newest.
public final class BuildCoalescer: @unchecked Sendable {
    private let delay: Duration
    private let build: @Sendable () async -> Void
    private let lock = NSLock()
    private var running = false
    private var again = false

    public init(delay: Duration = .seconds(1), build: @escaping @Sendable () async -> Void) {
        self.delay = delay
        self.build = build
    }

    public func request() {
        lock.lock()
        if running { again = true; lock.unlock(); return }
        running = true
        lock.unlock()
        Task { [self] in
            while true {
                try? await Task.sleep(for: delay)
                lock.lock(); again = false; lock.unlock()
                await build()
                lock.lock()
                if !again { running = false; lock.unlock(); return }
                lock.unlock()
            }
        }
    }
}
