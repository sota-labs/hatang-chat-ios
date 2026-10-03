import Foundation
@testable import HatangChatCore

/// An in-memory `SocketConnection` the test drives: read what the client sent, push frames, close with a
/// code.
final class FakeSocketConnection: SocketConnection, @unchecked Sendable {
    private struct State {
        var sent: [String] = []
        var code: Int?
        var reason: String?
        var closed = false
    }

    let messages: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let state = Locked(State())

    init() {
        (messages, continuation) = AsyncStream.makeStream(of: String.self)
    }

    var sentRaw: [String] { state.current.sent }
    var sent: [JSONObject] { sentRaw.compactMap { JSONValue.parse($0)?.objectValue } }
    var sentTypes: [String] { sent.map(\.t) }
    var isClosed: Bool { state.current.closed }
    var closeCode: Int? { state.current.code }
    var closeReason: String? { state.current.reason }

    func lastOfType(_ t: String) -> JSONObject? { sent.last { $0.t == t } }

    /// The payload of the last frame of type `t` (empty when none).
    func lastD(_ t: String) -> JSONObject { lastOfType(t)?.d ?? [:] }

    func count(_ t: String) -> Int { sentTypes.filter { $0 == t }.count }

    func send(_ data: String) {
        state.withLock { $0.sent.append(data) }
    }

    func close(code: Int?, reason: String?) async {
        let first = state.withLock { s -> Bool in
            guard !s.closed else { return false }
            s.closed = true
            s.code = code ?? 1000
            s.reason = reason
            return true
        }
        if first { continuation.finish() }
    }

    func push(_ frame: JSONObject) {
        continuation.yield(frame.text)
    }

    func pushRaw(_ raw: String) {
        continuation.yield(raw)
    }

    /// The server closes the socket with `code`.
    func serverClose(_ code: Int, _ reason: String = "") {
        let first = state.withLock { s -> Bool in
            guard !s.closed else { return false }
            s.closed = true
            s.code = code
            s.reason = reason
            return true
        }
        if first { continuation.finish() }
    }

    /// A `ready` frame with an empty conversation.
    static func readyFrame(id: String? = nil) -> JSONObject {
        var f = json("""
        {"t":"ready","d":{
          "visitor":{"id":"vis_1","site_id":"site_1","client":"app"},
          "conversation":null,"timeline":[],
          "availability":{"online":true,"within_hours":true,"next_open_at":null,"agents_online":1}}}
        """)
        if let id { f["id"] = .string(id) }
        return f
    }
}

/// A connector that hands out fresh fake connections in order (and can fail).
final class FakeConnector: SocketConnector, @unchecked Sendable {
    private struct State {
        var connections: [FakeSocketConnection] = []
        var urls: [String] = []
        var failNext = false
        var failCount = 0
    }

    private let state = Locked(State())

    var connections: [FakeSocketConnection] { state.current.connections }
    var urls: [String] { state.current.urls }
    var failCount: Int { state.current.failCount }
    var last: FakeSocketConnection { connections.last! }

    var failNext: Bool {
        get { state.current.failNext }
        set { state.withLock { $0.failNext = newValue } }
    }

    func connect(url: String) async throws -> any SocketConnection {
        try state.withLock { s in
            s.urls.append(url)
            if s.failNext {
                s.failNext = false
                s.failCount += 1
                throw HatangError.network("connect refused")
            }
            let c = FakeSocketConnection()
            s.connections.append(c)
            return c
        }
    }
}
