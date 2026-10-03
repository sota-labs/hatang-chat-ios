import Foundation

/// Socket status as seen by the engine.
enum SocketStatus: Sendable, Hashable {
    /// Opening a connection (or waiting to retry).
    case connecting
    /// Authenticated: `ready` arrived.
    case open
    /// No connection.
    case closed
}

/// Small reconnecting WebSocket client (port of `ChatSocket` in `@hatang/chat-protocol`): auth-first,
/// request/ack correlation with a timeout, exponential backoff and a keep-alive ping.
///
/// The methods are synchronous and thread-safe (state lives behind a lock). Callbacks are delivered in
/// order on one task, each awaited before the next.
final class ChatSocket: @unchecked Sendable {
    typealias Auth = @Sendable () async throws -> JSONObject

    struct Handlers: Sendable {
        var onFrame: @Sendable (ServerFrame) async -> Void
        var onStatus: @Sendable (SocketStatus) async -> Void = { _ in }
        var onAuthError: @Sendable (any Error) async -> Void = { _ in }
        var onClose: @Sendable (_ code: Int, _ reason: String) async -> Void = { _, _ in }
    }

    private enum Event: Sendable {
        case frame(ServerFrame)
        case status(SocketStatus)
        case authError(any Error)
        case close(Int, String)
    }

    private struct Pending {
        let continuation: CheckedContinuation<ServerFrame, any Error>
        let timer: Task<Void, Never>
    }

    private struct State {
        var conn: (any SocketConnection)?
        var reader: Task<Void, Never>?
        var attempt = 0
        var generation = 0
        var closedByUser = true
        var seq = 0
        var ping: Task<Void, Never>?
        var reconnect: Task<Void, Never>?
        var queue: [String] = []
        var pending: [String: Pending] = [:]
        var ready = false
    }

    /// Socket URL (already carrying `site`, `app` and `install`).
    let url: String
    /// How long a `request` waits for its reply.
    let requestTimeout: Duration
    /// Keep-alive cadence once ready.
    let pingInterval: Duration

    private let connector: any SocketConnector
    private let auth: Auth
    private let backoff: Backoff
    private let logger: HatangLogger
    private let clock: any HatangClock
    private let state = Locked(State())
    private let events: AsyncStream<Event>.Continuation

    init(
        url: String,
        connector: any SocketConnector,
        auth: @escaping Auth,
        handlers: Handlers,
        backoff: Backoff = Backoff(),
        requestTimeout: Duration = .seconds(10),
        pingInterval: Duration = .seconds(25),
        logger: HatangLogger = .silent,
        clock: any HatangClock = SystemClock()
    ) {
        self.url = url
        self.connector = connector
        self.auth = auth
        self.backoff = backoff
        self.requestTimeout = requestTimeout
        self.pingInterval = pingInterval
        self.logger = logger
        self.clock = clock
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        events = continuation
        Task {
            for await e in stream {
                switch e {
                case .frame(let f): await handlers.onFrame(f)
                case .status(let s): await handlers.onStatus(s)
                case .authError(let err): await handlers.onAuthError(err)
                case .close(let code, let reason): await handlers.onClose(code, reason)
                }
            }
        }
    }

    deinit {
        events.finish()
    }

    /// Authenticated and able to send.
    var ready: Bool { state.current.ready }

    /// A connection is open or being opened (i.e. `close` was not called).
    var active: Bool { !state.current.closedByUser }

    /// Opens the connection (no-op while already active).
    func connect() {
        let gen = state.withLock { s -> Int? in
            guard s.closedByUser else { return nil }
            s.closedByUser = false
            s.generation += 1
            return s.generation
        }
        guard let gen else { return }
        Task { await self.open(gen) }
    }

    /// Closes the connection and stops reconnecting. Pending requests fail with `closed`.
    func close() {
        let (conn, pending) = state.withLock { s -> ((any SocketConnection)?, [Pending]) in
            s.closedByUser = true
            s.reconnect?.cancel()
            s.reconnect = nil
            s.ping?.cancel()
            s.ping = nil
            let c = s.conn
            s.conn = nil
            s.generation += 1
            s.ready = false
            s.reader?.cancel()
            s.reader = nil
            let p = Array(s.pending.values)
            s.pending = [:]
            if c != nil { events.yield(.status(.closed)) }
            return (c, p)
        }
        if let conn {
            let logger = self.logger
            Task {
                await conn.close(code: 1000, reason: "client closed")
                logger.debug("socket closed by client")
            }
        }
        fail(pending, HatangError.closed)
    }

    /// Fire-and-forget. Frames sent before `ready` are queued until auth completes.
    func send(_ frame: ClientFrame, id: String? = nil) {
        let raw = encodeFrame(frame, id: id)
        state.withLock { s in
            if s.ready, let c = s.conn {
                c.send(raw)
            } else {
                s.queue.append(raw)
            }
        }
    }

    /// Sends `frame` and waits for the frame that echoes its id (an ack, or an `error` which throws a
    /// `HatangError`). Throws `timeout` after `timeout` and `closed` when the socket closes first.
    func request(_ frame: ClientFrame, timeout: Duration? = nil) async throws -> ServerFrame {
        let wait = timeout ?? requestTimeout
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<ServerFrame, any Error>) in
            let id = state.withLock { s -> String in
                let id = String(clock.now().epochMillis, radix: 36) + String(s.seq, radix: 36)
                s.seq += 1
                let clock = self.clock
                let timer = Task { [weak self] in
                    do { try await clock.sleep(for: wait) } catch { return }
                    self?.expire(id)
                }
                s.pending[id] = Pending(continuation: c, timer: timer)
                return id
            }
            send(frame, id: id)
        }
    }

    // MARK: - Internals

    private func expire(_ id: String) {
        let p = state.withLock { $0.pending.removeValue(forKey: id) }
        p?.continuation.resume(throwing: HatangError.timeout)
    }

    private func isStale(_ gen: Int) -> Bool {
        state.withLock { $0.generation != gen || $0.closedByUser }
    }

    private func open(_ gen: Int) async {
        events.yield(.status(.connecting))
        let c: any SocketConnection
        do {
            c = try await connector.connect(url: url)
        } catch {
            if isStale(gen) { return }
            logger.warn("socket connect failed: \(error)")
            afterClose(gen, code: 1006, reason: "connect failed")
            return
        }
        let current = state.withLock { s -> Bool in
            guard s.generation == gen, !s.closedByUser else { return false }
            s.conn = c
            return true
        }
        guard current else {
            await c.close(code: 1000, reason: "stale")
            return
        }
        let reader = Task { [weak self] in
            for await raw in c.messages {
                self?.onMessage(gen, raw)
            }
            if Task.isCancelled { return }
            self?.afterClose(gen, code: c.closeCode ?? 1005, reason: c.closeReason ?? "")
        }
        state.withLock { s in
            if s.generation == gen { s.reader = reader }
        }
        let d: JSONObject
        do {
            d = try await auth()
        } catch {
            if isStale(gen) { return }
            events.yield(.authError(error))
            await c.close(code: CloseCodes.clientAuthError, reason: "auth failed")
            return
        }
        if isStale(gen) { return }
        c.send(encodeFrame(ClientFrame("auth", d)))
    }

    private func onMessage(_ gen: Int, _ raw: String) {
        guard let f = tryDecodeFrame(raw) else { return }
        let reply = state.withLock { s -> (Pending, ServerFrame)? in
            guard s.generation == gen else { return nil }
            if case .ready = f {
                s.ready = true
                s.attempt = 0
                events.yield(.status(.open))
                startPing(&s)
                let q = s.queue
                s.queue = []
                if let c = s.conn { q.forEach(c.send) }
            }
            var reply: (Pending, ServerFrame)?
            if let id = f.id, let p = s.pending.removeValue(forKey: id) {
                p.timer.cancel()
                reply = (p, f)
            }
            events.yield(.frame(f))
            return reply
        }
        guard let (p, f) = reply else { return }
        if case .error(let e) = f {
            p.continuation.resume(throwing: HatangError(code: e.code, message: e.message))
        } else {
            p.continuation.resume(returning: f)
        }
    }

    private func afterClose(_ gen: Int, code: Int, reason: String) {
        let pending = state.withLock { s -> [Pending]? in
            guard s.generation == gen else { return nil }
            s.ready = false
            s.ping?.cancel()
            s.ping = nil
            s.conn = nil
            s.reader = nil
            let p = Array(s.pending.values)
            s.pending = [:]
            events.yield(.close(code, reason))
            events.yield(.status(.closed))
            if s.closedByUser { return p }
            // 4005: the server handed over a new session token; come back at once.
            let wait: Duration = code == CloseCodes.sessionReplaced ? .zero : backoff.next(s.attempt)
            s.attempt += 1
            logger.debug("socket closed (\(code) \(reason)); reconnect in \(wait.inMilliseconds) ms")
            s.reconnect?.cancel()
            let clock = self.clock
            s.reconnect = Task { [weak self] in
                do { try await clock.sleep(for: wait) } catch { return }
                guard let self else { return }
                let next = self.state.withLock { s -> Int? in
                    s.reconnect = nil
                    guard !s.closedByUser else { return nil }
                    s.generation += 1
                    return s.generation
                }
                if let next { await self.open(next) }
            }
            return p
        }
        if let pending { fail(pending, HatangError.closed) }
    }

    private func fail(_ pending: [Pending], _ error: HatangError) {
        for p in pending {
            p.timer.cancel()
            p.continuation.resume(throwing: error)
        }
    }

    private func startPing(_ s: inout State) {
        s.ping?.cancel()
        let clock = self.clock
        let interval = pingInterval
        s.ping = Task { [weak self] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: interval) } catch { return }
                self?.send(ClientFrame.ping())
            }
        }
    }
}
