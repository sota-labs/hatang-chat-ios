import Foundation

/// One open WebSocket. `URLSessionSocketConnector` makes real ones; tests use an in-memory fake.
public protocol SocketConnection: AnyObject, Sendable {
    /// Text frames from the server, read by one consumer. The stream finishes when the socket closes; read
    /// `closeCode` and `closeReason` after that.
    var messages: AsyncStream<String> { get }

    /// The close code once closed (nil while open or when none was sent).
    var closeCode: Int? { get }

    /// The close reason once closed.
    var closeReason: String? { get }

    /// Sends a text frame (in call order).
    func send(_ data: String)

    /// Closes the socket with an optional code and reason.
    func close(code: Int?, reason: String?) async
}

/// Opens a socket to `url`; throws when the connection cannot be established.
public protocol SocketConnector: Sendable {
    /// Opens a socket to `url` (`ws://` or `wss://`).
    func connect(url: String) async throws -> any SocketConnection
}

/// Real sockets over `URLSessionWebSocketTask`. No Origin header is sent (app sockets do not need one).
public struct URLSessionSocketConnector: SocketConnector {
    /// `User-Agent` sent with the upgrade request.
    public var userAgent: String?
    /// How long the opening handshake may take.
    public var connectTimeout: Duration

    public init(userAgent: String? = nil, connectTimeout: Duration = .seconds(15)) {
        self.userAgent = userAgent
        self.connectTimeout = connectTimeout
    }

    public func connect(url: String) async throws -> any SocketConnection {
        guard let u = URL(string: url) else { throw HatangError.network("Bad socket URL \(url)") }
        var req = URLRequest(url: u)
        req.timeoutInterval = Double(connectTimeout.inMilliseconds) / 1000
        if let userAgent { req.setValue(userAgent, forHTTPHeaderField: "user-agent") }
        let conn = URLSessionSocketConnection(request: req)
        try await conn.open()
        return conn
    }
}

/// A `URLSessionWebSocketTask` with the close code captured from the delegate (custom codes such as 4003
/// come through as raw values).
final class URLSessionSocketConnection: NSObject, SocketConnection, URLSessionWebSocketDelegate, @unchecked Sendable {
    private struct State {
        var opened = false
        var finished = false
        var code: Int?
        var reason: String?
        var openContinuation: CheckedContinuation<Void, any Error>?
    }

    let messages: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let state = Locked(State())
    private let request: URLRequest
    private var session: URLSession!
    private var task: URLSessionWebSocketTask!

    init(request: URLRequest) {
        self.request = request
        (messages, continuation) = AsyncStream.makeStream(of: String.self)
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = max(request.timeoutInterval, 1)
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        task = session.webSocketTask(with: request)
    }

    var closeCode: Int? { state.current.code }
    var closeReason: String? { state.current.reason }

    func open() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                state.withLock { $0.openContinuation = c }
                task.resume()
            }
        } onCancel: {
            self.task.cancel()
        }
        Task { await self.receiveLoop() }
    }

    private func receiveLoop() async {
        while true {
            do {
                let m = try await task.receive()
                switch m {
                case .string(let s): continuation.yield(s)
                case .data(let d): continuation.yield(String(decoding: d, as: UTF8.self))
                @unknown default: break
                }
            } catch {
                break
            }
        }
        // The delegate usually reports the close first; give it a moment when it has not.
        let code = task.closeCode.rawValue
        if code != 0 {
            finish(code: code, reason: task.closeReason.map { String(decoding: $0, as: UTF8.self) } ?? "")
        } else {
            try? await Task.sleep(for: .seconds(2))
            finish(code: 1006, reason: "")
        }
    }

    private func finish(code: Int, reason: String) {
        let first = state.withLock { s -> Bool in
            guard !s.finished else { return false }
            s.finished = true
            s.code = code
            s.reason = reason
            return true
        }
        guard first else { return }
        continuation.finish()
        session.finishTasksAndInvalidate()
    }

    func send(_ data: String) {
        task.send(.string(data)) { _ in }
    }

    func close(code: Int?, reason: String?) async {
        let c = code ?? 1000
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: c) ?? .normalClosure
        task.cancel(with: closeCode, reason: reason.map { Data($0.utf8) })
        finish(code: c, reason: reason ?? "")
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        let c = state.withLock { s -> CheckedContinuation<Void, any Error>? in
            s.opened = true
            defer { s.openContinuation = nil }
            return s.openContinuation
        }
        c?.resume()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish(code: closeCode.rawValue, reason: reason.map { String(decoding: $0, as: UTF8.self) } ?? "")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let c = state.withLock { s -> CheckedContinuation<Void, any Error>? in
            defer { s.openContinuation = nil }
            return s.openContinuation
        }
        if let c {
            let message = error?.localizedDescription ?? "The socket closed before it opened"
            c.resume(throwing: HatangError.network(message))
        }
        let code = webSocketTaskCode
        finish(code: code != 0 ? code : 1006, reason: error?.localizedDescription ?? "")
    }

    private var webSocketTaskCode: Int { task.closeCode.rawValue }
}
