import Foundation
@testable import HatangChatCore

/// A request as the stub saw it.
struct RecordedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data

    var path: String { url.path }
    var query: [String: String] {
        var q: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { q[item.name] = item.value ?? "" }
        return q
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }

    var json: JSONObject { JSONValue.parse(body)?.objectValue ?? [:] }
    var bodyText: String { String(decoding: body, as: UTF8.self) }
}

/// What the stub answers.
enum StubReply: Sendable {
    case response(status: Int, body: Data, headers: [String: String])
    case failure(URLError.Code)

    static func json(_ text: String, status: Int = 200) -> StubReply {
        .response(status: status, body: Data(text.utf8), headers: ["content-type": "application/json"])
    }

    static func json(_ o: JSONObject, status: Int = 200) -> StubReply {
        json(o.text, status: status)
    }

    static func text(_ text: String, status: Int) -> StubReply {
        .response(status: status, body: Data(text.utf8), headers: [:])
    }
}

/// A scripted HTTP server behind `URLProtocol`: each server gets its own session (routed by a header).
final class StubServer: @unchecked Sendable {
    typealias Handler = @Sendable (RecordedRequest) async -> StubReply

    private static let servers = Locked<[String: StubServer]>([:])
    static let routeHeader = "x-stub-server"

    let id = UUID().uuidString
    let session: URLSession
    private let state = Locked<(requests: [RecordedRequest], queue: [StubReply])>(([], []))
    private let handler = Locked<Handler?>(nil)

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [StubServer.routeHeader: id]
        session = URLSession(configuration: config)
        StubServer.servers.withLock { $0[id] = self }
    }

    deinit {
        let id = self.id
        StubServer.servers.withLock { _ = $0.removeValue(forKey: id) }
    }

    static func server(for request: URLRequest) -> StubServer? {
        guard let id = request.value(forHTTPHeaderField: routeHeader) else { return nil }
        return servers.withLock { $0[id] }
    }

    /// Requests seen so far.
    var requests: [RecordedRequest] { state.current.requests }

    /// Answers in order (before the handler).
    func enqueue(_ reply: StubReply) {
        state.withLock { $0.queue.append(reply) }
    }

    func setHandler(_ h: @escaping Handler) {
        handler.withLock { $0 = h }
    }

    func requests(path suffix: String, method: String? = nil) -> [RecordedRequest] {
        requests.filter { $0.path.hasSuffix(suffix) && (method == nil || $0.method == method) }
    }

    fileprivate func handle(_ r: RecordedRequest) async -> StubReply {
        let queued = state.withLock { s -> StubReply? in
            s.requests.append(r)
            return s.queue.isEmpty ? nil : s.queue.removeFirst()
        }
        if let queued { return queued }
        if let h = handler.current { return await h(r) }
        return .json(#"{"statusCode":404,"name":"not_found","message":"no route"}"#, status: 404)
    }
}

private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private var work: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let req = request
        guard let server = StubServer.server(for: req) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let body = req.httpBody ?? Self.read(req.httpBodyStream)
        var headers: [String: String] = [:]
        for (k, v) in req.allHTTPHeaderFields ?? [:] where k != StubServer.routeHeader { headers[k] = v }
        let recorded = RecordedRequest(method: req.httpMethod ?? "GET", url: req.url!, headers: headers, body: body)
        let me = UncheckedBox(value: self)
        work = Task {
            let reply = await server.handle(recorded)
            if Task.isCancelled { return }
            let p = me.value
            switch reply {
            case .failure(let code):
                p.client?.urlProtocol(p, didFailWithError: URLError(code))
            case .response(let status, let data, let headers):
                let resp = HTTPURLResponse(url: recorded.url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
                p.client?.urlProtocol(p, didReceive: resp, cacheStoragePolicy: .notAllowed)
                p.client?.urlProtocol(p, didLoad: data)
                p.client?.urlProtocolDidFinishLoading(p)
            }
        }
    }

    override func stopLoading() {
        work?.cancel()
    }

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}
