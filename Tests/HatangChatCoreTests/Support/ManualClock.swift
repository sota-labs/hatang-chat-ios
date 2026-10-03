import Foundation
@testable import HatangChatCore

/// Virtual time: `sleep` waits until `advance` moves past its deadline. Starts at a fixed instant.
final class ManualClock: HatangClock, @unchecked Sendable {
    private struct Sleeper {
        let id: Int
        let deadline: Int64
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var nowMs: Int64
        var sleepers: [Sleeper] = []
        var nextId = 0
    }

    private let state: Locked<State>
    let startMs: Int64

    init(startMs: Int64 = 1_790_000_000_000) {
        self.startMs = startMs
        state = Locked(State(nowMs: startMs))
    }

    /// Milliseconds since the start.
    var elapsed: Int64 { state.current.nowMs - startMs }

    func now() -> Date {
        Date(timeIntervalSince1970: Double(state.current.nowMs) / 1000)
    }

    func sleep(for duration: Duration) async throws {
        let ms = duration.inMilliseconds
        if ms <= 0 {
            try Task.checkCancellation()
            await Task.yield()
            return
        }
        let id = state.withLock { s -> Int in
            s.nextId += 1
            return s.nextId
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                let cancelled = state.withLock { s -> Bool in
                    if Task.isCancelled { return true }
                    s.sleepers.append(Sleeper(id: id, deadline: s.nowMs + ms, continuation: c))
                    return false
                }
                if cancelled { c.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let s = state.withLock { s -> Sleeper? in
                guard let i = s.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return s.sleepers.remove(at: i)
            }
            s?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time on by `ms`, waking sleepers in deadline order and letting each one's follow-up run.
    func advance(_ ms: Int64) async {
        // Timers are started by tasks that may not have reached their `sleep` yet.
        await settle()
        let target = state.current.nowMs + ms
        while true {
            let next = state.withLock { s -> Sleeper? in
                guard let i = s.sleepers.indices.filter({ s.sleepers[$0].deadline <= target })
                    .min(by: { (s.sleepers[$0].deadline, s.sleepers[$0].id) < (s.sleepers[$1].deadline, s.sleepers[$1].id) })
                else { return nil }
                let sl = s.sleepers.remove(at: i)
                s.nowMs = max(s.nowMs, sl.deadline)
                return sl
            }
            guard let next else { break }
            next.continuation.resume()
            await settle()
        }
        state.withLock { $0.nowMs = max($0.nowMs, target) }
        await settle()
    }
}
