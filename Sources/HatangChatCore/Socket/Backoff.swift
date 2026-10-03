import Foundation

/// Reconnect delays: `min(max, base · 2^attempt) + random jitter`.
public struct Backoff: Sendable {
    /// Delay for attempt 0.
    public var base: Duration
    /// Cap before jitter.
    public var max: Duration
    /// Upper bound (exclusive) of the random extra.
    public var jitter: Duration
    /// Returns a random number in `0..<bound` milliseconds (tests pass a fixed one).
    public var random: @Sendable (Int64) -> Int64

    public init(
        base: Duration = .milliseconds(500),
        max: Duration = .seconds(30),
        jitter: Duration = .milliseconds(500),
        random: @escaping @Sendable (Int64) -> Int64 = { Int64.random(in: 0..<$0) }
    ) {
        self.base = base
        self.max = max
        self.jitter = jitter
        self.random = random
    }

    /// Delay before reconnect number `attempt` (0-based).
    public func next(_ attempt: Int) -> Duration {
        let exp = Swift.min(Swift.max(attempt, 0), 30)
        let ms = Swift.min(max.inMilliseconds, base.inMilliseconds * (Int64(1) << Int64(exp)))
        let jitterMs = jitter.inMilliseconds
        let j = jitterMs <= 0 ? 0 : random(jitterMs)
        return .milliseconds(ms + j)
    }
}
