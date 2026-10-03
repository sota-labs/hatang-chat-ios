import Foundation

/// Where the SDK reads the current time and how it waits. Tests pass a manual clock so timers (backoff,
/// pings, request timeouts, typing, background close) run on virtual time.
public protocol HatangClock: Sendable {
    /// The current instant.
    func now() -> Date

    /// Suspends for `duration`; throws `CancellationError` when the calling task is cancelled.
    func sleep(for duration: Duration) async throws
}

/// The system clock and `Task.sleep`.
public struct SystemClock: HatangClock {
    public init() {}

    public func now() -> Date { Date() }

    public func sleep(for duration: Duration) async throws {
        if duration <= .zero {
            try Task.checkCancellation()
            return
        }
        try await Task.sleep(for: duration)
    }
}

extension HatangClock where Self == SystemClock {
    /// The system clock.
    public static var system: SystemClock { SystemClock() }
}

extension Duration {
    /// Whole milliseconds.
    var inMilliseconds: Int64 {
        let (s, atto) = components
        return s * 1000 + atto / 1_000_000_000_000_000
    }
}

extension Date {
    /// Milliseconds since 1970.
    var epochMillis: Int64 { Int64((timeIntervalSince1970 * 1000).rounded(.down)) }
}
