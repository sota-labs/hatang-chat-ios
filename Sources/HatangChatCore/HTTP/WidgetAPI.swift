import Foundation

/// Header carrying the site app key.
public let appKeyHeader = "x-hatang-app-key"

/// Header carrying the visitor token.
public let visitorTokenHeader = "x-visitor-token"

/// Called as an upload body goes out: `sent` of `total` bytes (on a URLSession queue).
public typealias UploadProgress = @Sendable (_ sent: Int64, _ total: Int64) -> Void

/// A page of the visitor's conversations.
public struct ConversationPage: Sendable, Hashable {
    /// Conversations, newest activity first.
    public var conversations: [VisitorConversationDto]
    /// More pages follow.
    public var hasMore: Bool

    public init(conversations: [VisitorConversationDto], hasMore: Bool) {
        self.conversations = conversations
        self.hasMore = hasMore
    }
}

/// A page of timeline items.
public struct MessagesPage: Sendable, Hashable {
    /// Items, oldest first.
    public var items: [TimelineItem]
    /// More items exist beyond this page (in the direction asked).
    public var hasMore: Bool

    public init(items: [TimelineItem], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}

/// Reply to the HTTP send fallback.
public struct SendResult: Sendable, Hashable {
    public var id: String
    public var seq: Int
    /// The client id was seen before.
    public var duplicate: Bool
}

/// Reply to the offline form.
public struct OfflineMessageResult: Sendable, Hashable {
    /// The conversation the message went into.
    public var conversation: ConversationSummary
    /// The stored message id.
    public var messageId: String
}

/// Reply to `reset`.
public struct ResetResult: Sendable, Hashable {
    public var visitorToken: String
    public var visitorId: String
}

/// Reply to `sessions/restore`.
public struct RestoreResult: Sendable, Hashable {
    public var visitorToken: String
    public var visitorId: String
    /// The conversation the link pointed at.
    public var conversationId: String
    public var conversation: ConversationSummary?
}

/// Reply to `leads`.
public struct LeadResult: Sendable, Hashable {
    public var conversationId: String?
    public var visitorId: String?
}

/// A device registered for pushes.
public struct DeviceRegistration: Sendable, Hashable {
    public var token: String
    public var provider: PushProvider
    /// `ios`, `android`, `web`, ...
    public var platform: String
    public var installId: String?
    public var locale: String?
    public var appVersion: String?
    public var osVersion: String?
    public var deviceModel: String?

    public init(
        token: String,
        provider: PushProvider,
        platform: String,
        installId: String? = nil,
        locale: String? = nil,
        appVersion: String? = nil,
        osVersion: String? = nil,
        deviceModel: String? = nil
    ) {
        self.token = token
        self.provider = provider
        self.platform = platform
        self.installId = installId
        self.locale = locale
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }

    /// The wire shape.
    public func toJSON() -> JSONObject {
        compact(
            ("token", token.json),
            ("provider", provider.code.json),
            ("platform", platform.json),
            ("install_id", installId.json),
            ("locale", locale.json),
            ("app_version", appVersion.json),
            ("os_version", osVersion.json),
            ("device_model", deviceModel.json)
        )
    }
}

/// The visitor REST API (`/widget/v1/sites/{siteId}/…`) over URLSession. Every call sends the app key and
/// the user agent; token calls add `x-visitor-token`. Failures throw `HatangError`: gateway errors
/// (`{statusCode, name, message}`) keep their `name` as the code and the HTTP status; transport failures
/// are `network_error`.
public final class WidgetAPI: Sendable {
    /// Gateway origin (`https://chat.hatang.dev`), optionally with a path prefix.
    public let baseURL: String
    /// The site.
    public let siteId: String
    /// The site app key (`hak_…`).
    public let appKey: String
    /// `User-Agent` sent on every call.
    public let userAgent: String
    /// Per-request timeout.
    public let timeout: Duration
    /// The session requests go through.
    public let session: URLSession
    private let ownsSession: Bool

    public init(baseURL: String, siteId: String, appKey: String, userAgent: String, session: URLSession? = nil, timeout: Duration = .seconds(20)) {
        self.baseURL = baseURL
        self.siteId = siteId
        self.appKey = appKey
        self.userAgent = userAgent
        self.timeout = timeout
        self.ownsSession = session == nil
        self.session = session ?? URLSession(configuration: .ephemeral)
    }

    /// Builds the URL for `path` (`/bootstrap`) under the site.
    public func url(_ path: String, query: [(String, String)] = []) -> URL? {
        guard var c = URLComponents(string: baseURL) else { return nil }
        var segments = c.path.split(separator: "/").map(String.init)
        segments += ["widget", "v1", "sites", siteId]
        segments += path.split(separator: "/").map(String.init)
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        c.percentEncodedPath = "/" + segments.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
        c.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return c.url
    }

    /// First call: config, a visitor token (new or existing) and the current conversation.
    public func bootstrap(app: AppContext, token: String? = nil, screen: ScreenInfo? = nil, locale: String? = nil, campaign: [String: String]? = nil) async throws -> BootstrapResponse {
        let j = try await send("POST", "/bootstrap", body: compact(
            ("token", token.json),
            ("app", .object(app.toJSON())),
            ("screen", screen.map { .object($0.toJSON()) }),
            ("locale", locale.json),
            ("campaign", campaign.map { .object($0.mapValues(JSONValue.string)) })
        ))
        return BootstrapResponse(json: j)
    }

    /// The visitor's conversations, newest activity first, resolved ones included.
    public func listConversations(token: String, status: String = "all", limit: Int? = nil, after: String? = nil) async throws -> ConversationPage {
        let j = try await get("/conversations", token: token, query: Self.query(("status", status), ("limit", limit.map(String.init)), ("after", after)))
        return ConversationPage(
            conversations: j.objList("conversations").map(VisitorConversationDto.init(json:)),
            hasMore: j.boolOr("has_more")
        )
    }

    /// Timeline items of one conversation: after `afterSeq` (forward) or before `beforeSeq` (older history,
    /// the newest `limit` before it; `afterSeq` is then ignored).
    public func messages(token: String, conversationId: String, afterSeq: Int? = nil, beforeSeq: Int? = nil, limit: Int? = nil) async throws -> MessagesPage {
        let j = try await get("/conversations/\(conversationId)/messages", token: token, query: Self.query(
            ("before_seq", beforeSeq.map(String.init)),
            ("after_seq", beforeSeq == nil ? afterSeq.map(String.init) : nil),
            ("limit", limit.map(String.init))
        ))
        return MessagesPage(items: TimelineItem.list(j["items"]), hasMore: j.bool("has_more") ?? j.boolOr("hasMore"))
    }

    /// HTTP fallback for `message.send`.
    public func sendMessage(token: String, conversationId: String, clientId: String, content: String, attachments: [String]? = nil) async throws -> SendResult {
        let a = attachments.flatMap { $0.isEmpty ? nil : JSONValue.array($0.map(JSONValue.string)) }
        let j = try await send("POST", "/conversations/\(conversationId)/messages", body: compact(
            ("client_id", clientId.json), ("content", content.json), ("attachments", a)
        ), token: token)
        return SendResult(id: j.strOr("id"), seq: j.intOr("seq"), duplicate: j.boolOr("duplicate"))
    }

    /// Uploads a file (multipart field `file`); the returned id goes into `message.send.attachments`.
    /// `onProgress` is called as the body goes out and once more with the full size when the upload is done.
    public func upload(token: String, data: Data, filename: String, contentType: String, onProgress: UploadProgress? = nil) async throws -> Attachment {
        guard let u = url("/uploads") else { throw HatangError.network("Bad base URL \(baseURL)") }
        let boundary = "hatang-\(UUID().uuidString)"
        let body = Multipart.body(boundary: boundary, field: "file", filename: filename, contentType: contentType, data: data)
        var req = request(u, token: token)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        req.httpBody = body
        let total = Int64(body.count)
        let delegate = onProgress.map { ProgressDelegate(total: total, onProgress: $0) }
        let reply = try await execute(req, delegate: delegate)
        if let delegate { delegate.finish() }
        return Attachment(json: try decode(reply, req))
    }

    /// Offline / pre-chat form.
    public func offlineMessage(token: String, message: String, name: String? = nil, email: String? = nil) async throws -> OfflineMessageResult {
        let j = try await send("POST", "/offline-message", body: compact(
            ("name", name.flatMap { $0.isEmpty ? nil : .string($0) }),
            ("email", email.flatMap { $0.isEmpty ? nil : .string($0) }),
            ("message", message.json)
        ), token: token)
        return OfflineMessageResult(conversation: ConversationSummary(json: j.obj("conversation") ?? [:]), messageId: j.strOr("message_id"))
    }

    /// Forget this visitor; the old token stops working.
    public func reset(token: String, installId: String? = nil) async throws -> ResetResult {
        let j = try await send("POST", "/reset", body: compact(("install_id", installId.json)), token: token)
        return ResetResult(visitorToken: j.strOr("visitor_token"), visitorId: j.strOr("visitor_id"))
    }

    /// Swap a magic-link token for the visitor's session.
    public func restoreSession(linkToken: String) async throws -> RestoreResult {
        let j = try await send("POST", "/sessions/restore", body: compact(("token", linkToken.json)))
        return RestoreResult(
            visitorToken: j.strOr("visitor_token"),
            visitorId: j.strOr("visitor_id"),
            conversationId: j.strOr("conversation_id"),
            conversation: j.obj("conversation").map(ConversationSummary.init(json:))
        )
    }

    /// Lead capture (works without a token).
    public func lead(token: String? = nil, name: String? = nil, phone: String? = nil, email: String? = nil, message: String? = nil, source: String? = nil, fields: [String: String]? = nil) async throws -> LeadResult {
        let j = try await send("POST", "/leads", body: compact(
            ("name", name.json), ("phone", phone.json), ("email", email.json), ("message", message.json), ("source", source.json),
            ("fields", fields.map { .object($0.mapValues(JSONValue.string)) })
        ), token: token)
        return LeadResult(conversationId: j.str("conversation_id"), visitorId: j.str("visitor_id"))
    }

    /// Registers (or moves) a push token for this visitor. A gateway without the endpoint (404) returns false.
    @discardableResult
    public func putDevice(token: String, device: DeviceRegistration) async throws -> Bool {
        try await tolerate404 { _ = try await send("PUT", "/devices", body: device.toJSON(), token: token) }
    }

    /// Removes a push token. A gateway without the endpoint (404) returns false.
    @discardableResult
    public func deleteDevice(token: String, pushToken: String) async throws -> Bool {
        try await tolerate404 { _ = try await send("DELETE", "/devices", body: compact(("token", pushToken.json)), token: token) }
    }

    /// Releases the URL session when this API created it.
    public func close() {
        if ownsSession { session.finishTasksAndInvalidate() }
    }

    // MARK: - Plumbing

    private func tolerate404(_ block: () async throws -> Void) async throws -> Bool {
        do {
            try await block()
            return true
        } catch let e as HatangError where e.status == 404 {
            return false
        }
    }

    private static func query(_ pairs: (String, String?)...) -> [(String, String)] {
        pairs.compactMap { k, v in v.map { (k, $0) } }
    }

    private func request(_ url: URL, token: String?) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = Double(timeout.inMilliseconds) / 1000
        r.setValue("application/json", forHTTPHeaderField: "accept")
        r.setValue(userAgent, forHTTPHeaderField: "user-agent")
        r.setValue(appKey, forHTTPHeaderField: appKeyHeader)
        if let token { r.setValue(token, forHTTPHeaderField: visitorTokenHeader) }
        return r
    }

    private func get(_ path: String, token: String?, query: [(String, String)]) async throws -> JSONObject {
        guard let u = url(path, query: query) else { throw HatangError.network("Bad base URL \(baseURL)") }
        var req = request(u, token: token)
        req.httpMethod = "GET"
        return try decode(try await execute(req, delegate: nil), req)
    }

    private func send(_ method: String, _ path: String, body: JSONObject, token: String? = nil) async throws -> JSONObject {
        guard let u = url(path) else { throw HatangError.network("Bad base URL \(baseURL)") }
        var req = request(u, token: token)
        req.httpMethod = method
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "content-type")
        req.httpBody = Data(JSONValue.object(body).jsonText.utf8)
        return try decode(try await execute(req, delegate: nil), req)
    }

    private struct Reply {
        let status: Int
        let body: Data
    }

    private func execute(_ req: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> Reply {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req, delegate: delegate)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if let u = error as? URLError, u.code == .timedOut { throw HatangError.network("The request timed out") }
            throw HatangError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let reply = Reply(status: status, body: data)
        if (200..<300).contains(status) { return reply }
        throw Self.error(reply)
    }

    private func decode(_ reply: Reply, _ req: URLRequest) throws -> JSONObject {
        if reply.body.isEmpty { return [:] }
        guard let v = JSONValue.parse(reply.body) else {
            throw HatangError(code: "decode_error", message: "Bad JSON from \(req.url?.absoluteString ?? "?")", status: reply.status)
        }
        return v.objectValue ?? [:]
    }

    private static func error(_ reply: Reply) -> HatangError {
        // Not JSON (a proxy page): fall through to a status-derived code.
        let j = JSONValue.parse(reply.body)?.objectValue ?? [:]
        let code = j.str("name") ?? j.str("code") ?? codeForStatus(reply.status)
        let message = j.str("message") ?? "HTTP \(reply.status)"
        return HatangError(code: code, message: message, status: reply.status)
    }

    private static func codeForStatus(_ status: Int) -> String {
        switch status {
        case 401: return "unauthorized"
        case 403: return "forbidden"
        case 404: return "not_found"
        case 422: return "validation_error"
        case 429: return "rate_limit_exceeded"
        default: return status >= 500 ? "server_error" : "http_error"
        }
    }
}

/// Reports `didSendBodyData`, then the full size once the request finished (stubbed sessions and some
/// transports never report body progress).
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let total: Int64
    private let onProgress: UploadProgress
    private let sent = Locked<Int64>(0)

    init(total: Int64, onProgress: @escaping UploadProgress) {
        self.total = total
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let expected = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : total
        let report = sent.withLock { last -> Bool in
            guard totalBytesSent > last else { return false }
            last = totalBytesSent
            return true
        }
        if report { onProgress(totalBytesSent, expected) }
    }

    func finish() {
        let report = sent.withLock { last -> Bool in
            guard last < total else { return false }
            last = total
            return true
        }
        if report { onProgress(total, total) }
    }
}
