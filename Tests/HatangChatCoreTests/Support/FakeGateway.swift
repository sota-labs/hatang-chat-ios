import Foundation
@testable import HatangChatCore

struct BootstrapCall: Equatable {
    let token: String?
    let locale: String?
}

struct MessagesCall: Equatable {
    let before: Int?
    let after: Int?
    let limit: Int?
}

struct UploadCall: Equatable {
    let filename: String
    let contentType: String
    let size: Int
}

struct OfflineCall: Equatable {
    let message: String
    let name: String?
    let email: String?
}

/// A scripted gateway behind `StubServer`: bootstrap answers from the shared `bootstrap.json` fixture,
/// everything is recorded. The engine talks to it through the real `WidgetAPI`.
final class FakeGateway: @unchecked Sendable {
    private struct State {
        var bootstrapEdit: (@Sendable (JSONObject) -> JSONObject)?
        var bootstrapError: StubReply?
        var freshToken = "tok_fresh"
        var conversationPages: [JSONObject] = [["conversations": [], "has_more": false]]
        var messagesItems: [JSONValue] = []
        var uploadError: StubReply?
        var uploadGate: AsyncStream<Void>?
        var uploadCount = 0
    }

    let server = StubServer()
    private let state = Locked(State())
    private let gate = Locked<AsyncStream<Void>.Continuation?>(nil)

    lazy var api = WidgetAPI(baseURL: "https://gw.test", siteId: "site_1", appKey: "hak_test", userAgent: "test", session: server.session)

    init() {
        server.setHandler { [weak self] r in await self?.handle(r) ?? .failure(.cannotConnectToHost) }
    }

    var bootstrapEdit: (@Sendable (JSONObject) -> JSONObject)? {
        get { state.current.bootstrapEdit }
        set { state.withLock { $0.bootstrapEdit = newValue } }
    }

    /// The next bootstrap fails with this reply.
    var bootstrapError: StubReply? {
        get { state.current.bootstrapError }
        set { state.withLock { $0.bootstrapError = newValue } }
    }

    /// The next upload fails with this reply.
    var uploadError: StubReply? {
        get { state.current.uploadError }
        set { state.withLock { $0.uploadError = newValue } }
    }

    func setConversationPages(_ pages: [ConversationPage]) {
        state.withLock {
            $0.conversationPages = pages.map { p in
                ["conversations": .array(p.conversations.map { .object($0.toJSON()) }), "has_more": .bool(p.hasMore)]
            }
        }
    }

    func setMessagesItems(_ items: [TimelineItem]) {
        state.withLock { $0.messagesItems = items.map { .object($0.toJSON()) } }
    }

    /// Uploads wait until `openUploadGate()`.
    func closeUploadGate() {
        let (stream, c) = AsyncStream.makeStream(of: Void.self)
        gate.withLock { $0 = c }
        state.withLock { $0.uploadGate = stream }
    }

    func openUploadGate() {
        gate.withLock { $0?.finish() }
    }

    // MARK: Recorded calls

    var bootstraps: [BootstrapCall] {
        server.requests(path: "/bootstrap").map { r in
            BootstrapCall(token: r.json.str("token"), locale: r.json.str("locale"))
        }
    }

    var putDevices: [JSONObject] { server.requests(path: "/devices", method: "PUT").map(\.json) }

    /// (visitor token, push token)
    var deleteDevices: [(String, String)] {
        server.requests(path: "/devices", method: "DELETE").map { ($0.header(visitorTokenHeader) ?? "", $0.json.strOr("token")) }
    }

    /// (visitor token, install id)
    var resets: [(String, String?)] {
        server.requests(path: "/reset").map { ($0.header(visitorTokenHeader) ?? "", $0.json.str("install_id")) }
    }

    var offlineMessages: [OfflineCall] {
        server.requests(path: "/offline-message").map { OfflineCall(message: $0.json.strOr("message"), name: $0.json.str("name"), email: $0.json.str("email")) }
    }

    var messageCalls: [MessagesCall] {
        server.requests(path: "/messages", method: "GET").map { r in
            let q = r.query
            return MessagesCall(before: q["before_seq"].flatMap { Int($0) }, after: q["after_seq"].flatMap { Int($0) }, limit: q["limit"].flatMap { Int($0) })
        }
    }

    var uploads: [UploadCall] {
        server.requests(path: "/uploads").map { r in
            let text = r.bodyText
            let filename = text.range(of: "filename=\"").map { String(text[$0.upperBound...].prefix { $0 != "\"" }) } ?? ""
            let type = text.range(of: "Content-Type: ").map { String(text[$0.upperBound...].prefix { !$0.isNewline }) } ?? ""
            let size = Self.partSize(r.body)
            return UploadCall(filename: filename, contentType: type, size: size)
        }
    }

    /// (status, after)
    var listCalls: [(String, String?)] {
        server.requests(path: "/conversations", method: "GET").map { ($0.query["status"] ?? "", $0.query["after"]) }
    }

    private static func partSize(_ body: Data) -> Int {
        let sep = Data("\r\n\r\n".utf8)
        guard let start = body.range(of: sep)?.upperBound,
              let end = body.range(of: Data("\r\n--".utf8), options: .backwards)?.lowerBound else { return 0 }
        return end - start
    }

    // MARK: Routing

    private func handle(_ r: RecordedRequest) async -> StubReply {
        let path = r.path
        if path.hasSuffix("/bootstrap") {
            let err = state.withLock { s -> StubReply? in
                defer { s.bootstrapError = nil }
                return s.bootstrapError
            }
            if let err { return err }
            let (fresh, edit) = state.withLock { ($0.freshToken, $0.bootstrapEdit) }
            var j = bootstrapFixture().with(["visitor_token": .string(r.json.str("token") ?? fresh)])
            if let edit { j = edit(j) }
            return .json(j)
        }
        if path.hasSuffix("/uploads") {
            let (gateStream, n) = state.withLock { s -> (AsyncStream<Void>?, Int) in
                s.uploadCount += 1
                return (s.uploadGate, s.uploadCount)
            }
            if let gateStream { for await _ in gateStream {} }
            let err = state.withLock { s -> StubReply? in
                defer { s.uploadError = nil }
                return s.uploadError
            }
            if let err { return err }
            let call = uploads.last!
            return .json(["id": .string("file_\(n)"), "name": .string(call.filename), "size": .number(Double(call.size)), "type": .string(call.contentType)])
        }
        if path.hasSuffix("/devices") { return .json(#"{"ok":true}"#) }
        if path.hasSuffix("/reset") { return .json(#"{"visitor_token":"tok_reset","visitor_id":"vis_reset"}"#) }
        if path.hasSuffix("/offline-message") {
            return .json(#"{"conversation":{"id":"conv_off","site_id":"site_1","visitor_id":"vis_1","status":"open"},"message_id":"m_off"}"#)
        }
        if path.hasSuffix("/messages"), r.method == "GET" {
            let items = state.current.messagesItems
            return .json(["items": .array(items), "has_more": false])
        }
        if path.hasSuffix("/conversations"), r.method == "GET" {
            let pages = state.current.conversationPages
            let i = listCalls.count - 1
            return .json(pages[min(max(i, 0), pages.count - 1)])
        }
        return .json(#"{"statusCode":404,"name":"not_found","message":"no route"}"#, status: 404)
    }
}

/// Bootstrap edit: no active conversation, empty timeline.
@Sendable func noConversation(_ j: JSONObject) -> JSONObject {
    j.with(["conversation": .null, "timeline": []])
}

/// Bootstrap edit: the team is away and the site wants an email.
func offline(_ capture: String = "email_optional") -> @Sendable (JSONObject) -> JSONObject {
    { j in
        j.with([
            "availability": .object(json(#"{"online":false,"within_hours":false,"next_open_at":null,"agents_online":0}"#)),
            "config": .object((j["config"]?.objectValue ?? [:]).with(["offline_capture": .string(capture)])),
        ])
    }
}
