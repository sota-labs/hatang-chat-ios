import Foundation

// Wire DTOs. Decoding is lenient: unknown keys are ignored, nulls and values of the wrong type fall back
// to defaults, unknown enum values map to a fallback case, so a newer gateway never breaks an older SDK.
// Every type is Codable through its `init(json:)` / `toJSON()` pair, keyed by its `CodingKeys`.

private func decodeObject(_ decoder: any Decoder) throws -> JSONObject {
    let v = try JSONValue(from: decoder)
    guard let o = v.objectValue else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected an object"))
    }
    return o
}

private func encodeObject(_ o: JSONObject, _ encoder: any Encoder) throws {
    try JSONValue.object(o).encode(to: encoder)
}

/// A string-backed enum read leniently from the wire.
public protocol WireEnum: RawRepresentable, Codable, Sendable, Hashable, CaseIterable where RawValue == String {
    /// The value for anything this SDK does not know.
    static var fallback: Self { get }
}

extension WireEnum {
    /// Parses the wire value; unknown values give `fallback`.
    public static func parse(_ s: String?) -> Self {
        s.flatMap { Self(rawValue: $0) } ?? fallback
    }

    /// The wire value.
    public var code: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let v = try JSONValue(from: decoder)
        self = Self.parse(v.stringValue)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Languages the Hatang widget and SDK speak.
public enum HatangLocale: String, WireEnum {
    /// Vietnamese (the product default).
    case vi
    /// English.
    case en

    public static var fallback: HatangLocale { .vi }

    /// Parses `vi` / `en`, returning nil for anything else.
    public static func tryParse(_ code: String?) -> HatangLocale? {
        code.flatMap { HatangLocale(rawValue: $0) }
    }
}

/// Conversation lifecycle status.
public enum ConversationStatus: String, WireEnum {
    /// Waiting for the team.
    case open
    /// Waiting for the visitor (or off-hours).
    case pending
    /// Resolved by the team; the visitor may reopen it by writing.
    case resolved
    /// Closed for good.
    case closed
    /// A status this SDK version does not know.
    case unknown

    public static var fallback: ConversationStatus { .unknown }

    /// Still active (open or pending).
    public var isActive: Bool { self == .open || self == .pending }
}

/// Who wrote a message or caused an event.
public enum SenderType: String, WireEnum {
    /// The customer (this app's user).
    case visitor
    /// A human agent.
    case agent
    /// The AI assistant.
    case bot
    /// The system (status changes, notices). Unknown senders count as system.
    case system

    public static var fallback: SenderType { .system }
}

/// What the site asks for before a visitor writes while nobody is online.
public enum OfflineCapture: String, WireEnum {
    /// An email is required.
    case emailRequired = "email_required"
    /// An email is requested but can be skipped.
    case emailOptional = "email_optional"
    /// No pre-chat form.
    case off

    public static var fallback: OfflineCapture { .off }
}

/// The site's preferred colour scheme.
public enum SiteTheme: String, WireEnum {
    case light, dark, auto

    public static var fallback: SiteTheme { .auto }
}

/// The launcher's preset icon.
public enum LauncherIcon: String, WireEnum {
    case chat, support, help, message

    public static var fallback: LauncherIcon { .chat }
}

/// Who the chat header shows: the online agents' faces or the business logo.
public enum HeaderProfile: String, WireEnum {
    case agents, business

    public static var fallback: HeaderProfile { .agents }
}

/// Who signs the greeting.
public enum GreetingSender: String, WireEnum {
    /// Nobody (a plain team greeting).
    case none
    /// The first online agent, as if they wrote it.
    case onlineAgent = "online_agent"

    public static var fallback: GreetingSender { .none }
}

/// Another way to reach the business.
public enum ContactKind: String, WireEnum {
    case zalo, messenger, phone, email
    /// A kind this SDK version does not know.
    case unknown

    public static var fallback: ContactKind { .unknown }
}

// MARK: - Attachment

/// A file attached to a message.
public struct Attachment: Codable, Sendable, Hashable {
    /// Upload id.
    public var id: String
    /// Original file name.
    public var name: String
    /// Size in bytes.
    public var size: Int
    /// MIME type.
    public var type: String
    /// Signed download URL (rotates; fetch the message again when it expires).
    public var url: String?

    enum CodingKeys: String, CodingKey {
        case id, name, size, type, url
    }

    public init(id: String = "", name: String = "", size: Int = 0, type: String = "application/octet-stream", url: String? = nil) {
        self.id = id
        self.name = name
        self.size = size
        self.type = type
        self.url = url
    }

    /// The attachment is an image.
    public var isImage: Bool { type.hasPrefix("image/") }

    /// Parses the wire shape.
    public init(json j: JSONObject) {
        self.init(
            id: j.strOr(CodingKeys.id.rawValue),
            name: j.strOr(CodingKeys.name.rawValue),
            size: j.intOr(CodingKeys.size.rawValue),
            type: j.strOr(CodingKeys.type.rawValue, "application/octet-stream"),
            url: j.str(CodingKeys.url.rawValue)
        )
    }

    /// The wire shape.
    public func toJSON() -> JSONObject {
        compact(("id", id.json), ("name", name.json), ("size", size.json), ("type", type.json), ("url", url.json))
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

// MARK: - Timeline

/// One row of a conversation: a message or an event.
public enum TimelineItem: Codable, Sendable, Hashable {
    case message(MessageDto)
    case event(ConversationEventDto)

    /// Unique id.
    public var id: String {
        switch self {
        case .message(let m): return m.id
        case .event(let e): return e.id
        }
    }

    /// The conversation this row belongs to.
    public var conversationId: String {
        switch self {
        case .message(let m): return m.conversationId
        case .event(let e): return e.conversationId
        }
    }

    /// Position in the conversation (monotonic).
    public var seq: Int {
        switch self {
        case .message(let m): return m.seq
        case .event(let e): return e.seq
        }
    }

    /// When it was created.
    public var createdAt: Date {
        switch self {
        case .message(let m): return m.createdAt
        case .event(let e): return e.createdAt
        }
    }

    /// `message` or `event`.
    public var kind: String {
        switch self {
        case .message: return "message"
        case .event: return "event"
        }
    }

    /// Rows the SDK made up locally (`showLocalMessage`, notices); never persisted.
    public var isLocal: Bool { id.hasPrefix("local-") }

    /// The message, when this row is one.
    public var message: MessageDto? {
        if case .message(let m) = self { return m }
        return nil
    }

    /// The event, when this row is one.
    public var event: ConversationEventDto? {
        if case .event(let e) = self { return e }
        return nil
    }

    /// Parses either shape, dispatching on `kind` (or on the presence of `sender_type` for older payloads).
    public init(json j: JSONObject) {
        let kind = j.str("kind") ?? (j["sender_type"] != nil ? "message" : "event")
        self = kind == "event" ? .event(ConversationEventDto(json: j)) : .message(MessageDto(json: j))
    }

    /// The wire shape, including `kind`.
    public func toJSON() -> JSONObject {
        switch self {
        case .message(let m): return m.toJSON()
        case .event(let e): return e.toJSON()
        }
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }

    /// Every object in `list` as a timeline item; anything else is skipped.
    static func list(_ v: JSONValue?) -> [TimelineItem] {
        (v?.arrayValue ?? []).compactMap(\.objectValue).map(TimelineItem.init(json:))
    }
}

/// A chat message.
public struct MessageDto: Codable, Sendable, Hashable {
    public var id: String
    public var conversationId: String
    public var seq: Int
    /// Who wrote it.
    public var senderType: SenderType
    /// Message text (may be empty when only attachments are sent).
    public var content: String
    public var createdAt: Date
    /// The sender's id.
    public var senderId: String?
    /// Display name of the sender when known.
    public var senderName: String?
    /// `public` for everything a visitor sees.
    public var visibility: String
    /// `text` or `file`.
    public var contentType: String
    /// Attached files.
    public var attachments: [Attachment]
    /// The optimistic id the sender chose; matches a pending bubble.
    public var clientId: String?
    /// Rich card payload and other channel data (see `cardOf`).
    public var metadata: JSONObject?
    /// Outbound delivery status on other channels.
    public var deliveryStatus: String?
    /// Outbound delivery error on other channels.
    public var deliveryError: String?
    /// When the other side read it.
    public var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, seq, content, visibility, attachments, metadata
        case conversationId = "conversation_id"
        case senderType = "sender_type"
        case createdAt = "created_at"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case contentType = "content_type"
        case clientId = "client_id"
        case deliveryStatus = "delivery_status"
        case deliveryError = "delivery_error"
        case readAt = "read_at"
    }

    public init(
        id: String = "",
        conversationId: String = "",
        seq: Int = 0,
        senderType: SenderType = .system,
        content: String = "",
        createdAt: Date = Date(timeIntervalSince1970: 0),
        senderId: String? = nil,
        senderName: String? = nil,
        visibility: String = "public",
        contentType: String = "text",
        attachments: [Attachment] = [],
        clientId: String? = nil,
        metadata: JSONObject? = nil,
        deliveryStatus: String? = nil,
        deliveryError: String? = nil,
        readAt: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.seq = seq
        self.senderType = senderType
        self.content = content
        self.createdAt = createdAt
        self.senderId = senderId
        self.senderName = senderName
        self.visibility = visibility
        self.contentType = contentType
        self.attachments = attachments
        self.clientId = clientId
        self.metadata = metadata
        self.deliveryStatus = deliveryStatus
        self.deliveryError = deliveryError
        self.readAt = readAt
    }

    /// Written by this app's user.
    public var isMine: Bool { senderType == .visitor }

    /// Parses the wire shape.
    public init(json j: JSONObject) {
        typealias K = CodingKeys
        self.init(
            id: j.strOr(K.id.rawValue),
            conversationId: j.strOr(K.conversationId.rawValue),
            seq: j.intOr(K.seq.rawValue),
            senderType: SenderType.parse(j.str(K.senderType.rawValue)),
            content: j.strOr(K.content.rawValue),
            createdAt: j.date(K.createdAt.rawValue) ?? Date(timeIntervalSince1970: 0),
            senderId: j.str(K.senderId.rawValue),
            senderName: j.str(K.senderName.rawValue),
            visibility: j.strOr(K.visibility.rawValue, "public"),
            contentType: j.strOr(K.contentType.rawValue, "text"),
            attachments: j.objList(K.attachments.rawValue).map(Attachment.init(json:)),
            clientId: j.str(K.clientId.rawValue),
            metadata: j.obj(K.metadata.rawValue),
            deliveryStatus: j.str(K.deliveryStatus.rawValue),
            deliveryError: j.str(K.deliveryError.rawValue),
            readAt: j.date(K.readAt.rawValue)
        )
    }

    /// The wire shape, including `kind`.
    public func toJSON() -> JSONObject {
        typealias K = CodingKeys
        return compact(
            ("kind", "message"),
            (K.id.rawValue, id.json),
            (K.conversationId.rawValue, conversationId.json),
            (K.seq.rawValue, seq.json),
            (K.senderType.rawValue, senderType.code.json),
            (K.content.rawValue, content.json),
            (K.createdAt.rawValue, formatISODate(createdAt).json),
            (K.senderId.rawValue, senderId.json),
            (K.senderName.rawValue, senderName.json),
            (K.visibility.rawValue, visibility.json),
            (K.contentType.rawValue, contentType.json),
            (K.attachments.rawValue, .array(attachments.map { .object($0.toJSON()) })),
            (K.clientId.rawValue, clientId.json),
            (K.metadata.rawValue, metadata.map(JSONValue.object)),
            (K.deliveryStatus.rawValue, deliveryStatus.json),
            (K.deliveryError.rawValue, deliveryError.json),
            (K.readAt.rawValue, readAt.map { .string(formatISODate($0)) })
        )
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

/// Something that happened in a conversation (status change, handoff, notice, ...).
public struct ConversationEventDto: Codable, Sendable, Hashable {
    public var id: String
    public var conversationId: String
    public var seq: Int
    /// Event type (`status_changed`, `handoff`, `notice`, `rated`, ...).
    public var type: String
    public var createdAt: Date
    /// Who caused it.
    public var actorType: SenderType
    /// The actor's id.
    public var actorId: String?
    /// Event payload.
    public var data: JSONObject

    enum CodingKeys: String, CodingKey {
        case id, seq, type, data
        case conversationId = "conversation_id"
        case createdAt = "created_at"
        case actorType = "actor_type"
        case actorId = "actor_id"
    }

    public init(
        id: String = "",
        conversationId: String = "",
        seq: Int = 0,
        type: String = "",
        createdAt: Date = Date(timeIntervalSince1970: 0),
        actorType: SenderType = .system,
        actorId: String? = nil,
        data: JSONObject = [:]
    ) {
        self.id = id
        self.conversationId = conversationId
        self.seq = seq
        self.type = type
        self.createdAt = createdAt
        self.actorType = actorType
        self.actorId = actorId
        self.data = data
    }

    /// Parses the wire shape.
    public init(json j: JSONObject) {
        typealias K = CodingKeys
        self.init(
            id: j.strOr(K.id.rawValue),
            conversationId: j.strOr(K.conversationId.rawValue),
            seq: j.intOr(K.seq.rawValue),
            type: j.strOr(K.type.rawValue),
            createdAt: j.date(K.createdAt.rawValue) ?? Date(timeIntervalSince1970: 0),
            actorType: SenderType.parse(j.str(K.actorType.rawValue)),
            actorId: j.str(K.actorId.rawValue),
            data: j.obj(K.data.rawValue) ?? [:]
        )
    }

    /// The wire shape, including `kind`.
    public func toJSON() -> JSONObject {
        typealias K = CodingKeys
        return compact(
            ("kind", "event"),
            (K.id.rawValue, id.json),
            (K.conversationId.rawValue, conversationId.json),
            (K.seq.rawValue, seq.json),
            (K.type.rawValue, type.json),
            (K.createdAt.rawValue, formatISODate(createdAt).json),
            (K.actorType.rawValue, actorType.code.json),
            (K.actorId.rawValue, actorId.json),
            (K.data.rawValue, .object(data))
        )
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

// MARK: - Visitor

/// Which registered app and build a visitor uses.
public struct VisitorAppInfo: Codable, Sendable, Hashable {
    /// Site app id.
    public var id: String
    /// `ios`, `android`, `flutter`, ...
    public var platform: String
    /// App version string.
    public var version: String?
    /// SDK name and version.
    public var sdk: String?

    enum CodingKeys: String, CodingKey {
        case id, platform, version, sdk
    }

    public init(id: String = "", platform: String = "", version: String? = nil, sdk: String? = nil) {
        self.id = id
        self.platform = platform
        self.version = version
        self.sdk = sdk
    }

    public init(json j: JSONObject) {
        self.init(id: j.strOr("id"), platform: j.strOr("platform"), version: j.str("version"), sdk: j.str("sdk"))
    }

    public func toJSON() -> JSONObject {
        compact(("id", id.json), ("platform", platform.json), ("version", version.json), ("sdk", sdk.json))
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

/// The visitor (this app's user as the site sees them).
public struct VisitorDto: Codable, Sendable, Hashable {
    public var id: String
    public var siteId: String
    public var email: String?
    public var name: String?
    public var phone: String?
    public var avatarUrl: String?
    /// The host app's user id (from `identify`).
    public var externalId: String?
    /// Custom data (from `identify` / `setData`).
    public var customData: JSONObject
    /// Preferred locale.
    public var locale: HatangLocale?
    /// When the visitor was identified.
    public var identifiedAt: Date?
    /// `web` or `app`.
    public var client: String
    /// Registered app details for app visitors.
    public var app: VisitorAppInfo?
    /// The screen the app reported.
    public var currentScreen: String?
    /// Number of visits.
    public var visits: Int
    /// The full wire payload.
    public var raw: JSONObject

    enum CodingKeys: String, CodingKey {
        case id, email, name, phone, locale, client, app, visits
        case siteId = "site_id"
        case avatarUrl = "avatar_url"
        case externalId = "external_id"
        case customData = "custom_data"
        case identifiedAt = "identified_at"
        case currentScreen = "current_screen"
    }

    public init(
        id: String = "",
        siteId: String = "",
        email: String? = nil,
        name: String? = nil,
        phone: String? = nil,
        avatarUrl: String? = nil,
        externalId: String? = nil,
        customData: JSONObject = [:],
        locale: HatangLocale? = nil,
        identifiedAt: Date? = nil,
        client: String = "app",
        app: VisitorAppInfo? = nil,
        currentScreen: String? = nil,
        visits: Int = 1,
        raw: JSONObject = [:]
    ) {
        self.id = id
        self.siteId = siteId
        self.email = email
        self.name = name
        self.phone = phone
        self.avatarUrl = avatarUrl
        self.externalId = externalId
        self.customData = customData
        self.locale = locale
        self.identifiedAt = identifiedAt
        self.client = client
        self.app = app
        self.currentScreen = currentScreen
        self.visits = visits
        self.raw = raw
    }

    /// Identified via `identify` (has an external id or email).
    public var isIdentified: Bool { identifiedAt != nil || externalId != nil || email != nil }

    public init(json j: JSONObject) {
        typealias K = CodingKeys
        self.init(
            id: j.strOr(K.id.rawValue),
            siteId: j.strOr(K.siteId.rawValue),
            email: j.str(K.email.rawValue),
            name: j.str(K.name.rawValue),
            phone: j.str(K.phone.rawValue),
            avatarUrl: j.str(K.avatarUrl.rawValue),
            externalId: j.str(K.externalId.rawValue),
            customData: j.obj(K.customData.rawValue) ?? [:],
            locale: HatangLocale.tryParse(j[K.locale.rawValue]?.strictString),
            identifiedAt: j.date(K.identifiedAt.rawValue),
            client: j.strOr(K.client.rawValue, "app"),
            app: j.obj(K.app.rawValue).map(VisitorAppInfo.init(json:)),
            currentScreen: j.str(K.currentScreen.rawValue),
            visits: j.intOr(K.visits.rawValue, 1),
            raw: j
        )
    }

    /// The wire shape (unknown fields from `raw` kept).
    public func toJSON() -> JSONObject {
        typealias K = CodingKeys
        let fields = compact(
            (K.id.rawValue, id.json),
            (K.siteId.rawValue, siteId.json),
            (K.email.rawValue, email.json),
            (K.name.rawValue, name.json),
            (K.phone.rawValue, phone.json),
            (K.avatarUrl.rawValue, avatarUrl.json),
            (K.externalId.rawValue, externalId.json),
            (K.customData.rawValue, .object(customData)),
            (K.locale.rawValue, locale?.code.json),
            (K.identifiedAt.rawValue, identifiedAt.map { .string(formatISODate($0)) }),
            (K.client.rawValue, client.json),
            (K.app.rawValue, app.map { .object($0.toJSON()) }),
            (K.currentScreen.rawValue, currentScreen.json),
            (K.visits.rawValue, visits.json)
        )
        return raw.merging(fields) { _, new in new }
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

// MARK: - Conversations

/// A conversation as the gateway reports it on `ready` / `conversation.start`.
public struct ConversationSummary: Codable, Sendable, Hashable {
    public var id: String
    public var siteId: String
    public var visitorId: String
    public var status: ConversationStatus
    /// Latest sequence number.
    public var seq: Int
    /// Messages the visitor has not read.
    public var visitorUnread: Int
    public var lastMessageAt: Date?
    public var lastMessagePreview: String?
    public var lastMessageSenderType: SenderType?
    /// `user` or `bot`.
    public var assigneeKind: String?
    public var assigneeId: String?
    public var firstResponseAt: Date?
    public var resolvedAt: Date?
    public var subject: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    /// The full wire payload.
    public var raw: JSONObject

    enum CodingKeys: String, CodingKey {
        case id, status, seq, subject
        case siteId = "site_id"
        case visitorId = "visitor_id"
        case visitorUnread = "visitor_unread"
        case lastMessageAt = "last_message_at"
        case lastMessagePreview = "last_message_preview"
        case lastMessageSenderType = "last_message_sender_type"
        case assigneeKind = "assignee_kind"
        case assigneeId = "assignee_id"
        case firstResponseAt = "first_response_at"
        case resolvedAt = "resolved_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String = "",
        siteId: String = "",
        visitorId: String = "",
        status: ConversationStatus = .open,
        seq: Int = 0,
        visitorUnread: Int = 0,
        lastMessageAt: Date? = nil,
        lastMessagePreview: String? = nil,
        lastMessageSenderType: SenderType? = nil,
        assigneeKind: String? = nil,
        assigneeId: String? = nil,
        firstResponseAt: Date? = nil,
        resolvedAt: Date? = nil,
        subject: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        raw: JSONObject = [:]
    ) {
        self.id = id
        self.siteId = siteId
        self.visitorId = visitorId
        self.status = status
        self.seq = seq
        self.visitorUnread = visitorUnread
        self.lastMessageAt = lastMessageAt
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageSenderType = lastMessageSenderType
        self.assigneeKind = assigneeKind
        self.assigneeId = assigneeId
        self.firstResponseAt = firstResponseAt
        self.resolvedAt = resolvedAt
        self.subject = subject
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.raw = raw
    }

    public init(json j: JSONObject) {
        typealias K = CodingKeys
        self.init(
            id: j.strOr(K.id.rawValue),
            siteId: j.strOr(K.siteId.rawValue),
            visitorId: j.strOr(K.visitorId.rawValue),
            status: j.str(K.status.rawValue).map(ConversationStatus.parse) ?? .open,
            seq: j.intOr(K.seq.rawValue),
            visitorUnread: j.intOr(K.visitorUnread.rawValue),
            lastMessageAt: j.date(K.lastMessageAt.rawValue),
            lastMessagePreview: j.str(K.lastMessagePreview.rawValue),
            lastMessageSenderType: j.str(K.lastMessageSenderType.rawValue).map(SenderType.parse),
            assigneeKind: j.str(K.assigneeKind.rawValue),
            assigneeId: j.str(K.assigneeId.rawValue),
            firstResponseAt: j.date(K.firstResponseAt.rawValue),
            resolvedAt: j.date(K.resolvedAt.rawValue),
            subject: j.str(K.subject.rawValue),
            createdAt: j.date(K.createdAt.rawValue),
            updatedAt: j.date(K.updatedAt.rawValue),
            raw: j
        )
    }

    /// The wire shape (unknown fields from `raw` kept).
    public func toJSON() -> JSONObject {
        typealias K = CodingKeys
        let d: (Date?) -> JSONValue? = { $0.map { .string(formatISODate($0)) } }
        let fields = compact(
            (K.id.rawValue, id.json),
            (K.siteId.rawValue, siteId.json),
            (K.visitorId.rawValue, visitorId.json),
            (K.status.rawValue, status.code.json),
            (K.seq.rawValue, seq.json),
            (K.visitorUnread.rawValue, visitorUnread.json),
            (K.lastMessageAt.rawValue, d(lastMessageAt)),
            (K.lastMessagePreview.rawValue, lastMessagePreview.json),
            (K.lastMessageSenderType.rawValue, lastMessageSenderType?.code.json),
            (K.assigneeKind.rawValue, assigneeKind.json),
            (K.assigneeId.rawValue, assigneeId.json),
            (K.firstResponseAt.rawValue, d(firstResponseAt)),
            (K.resolvedAt.rawValue, d(resolvedAt)),
            (K.subject.rawValue, subject.json),
            (K.createdAt.rawValue, d(createdAt)),
            (K.updatedAt.rawValue, d(updatedAt))
        )
        return raw.merging(fields) { _, new in new }
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

/// The human handling a conversation.
public struct AgentSummary: Codable, Sendable, Hashable {
    /// Display name.
    public var name: String
    /// Avatar URL.
    public var avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case name
        case avatarUrl = "avatar_url"
    }

    public init(name: String = "", avatarUrl: String? = nil) {
        self.name = name
        self.avatarUrl = avatarUrl
    }

    public init(json j: JSONObject) {
        self.init(name: j.strOr(CodingKeys.name.rawValue), avatarUrl: j.str(CodingKeys.avatarUrl.rawValue))
    }

    public func toJSON() -> JSONObject {
        compact((CodingKeys.name.rawValue, name.json), (CodingKeys.avatarUrl.rawValue, avatarUrl.json))
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

/// A team member shown in the chat header.
public typealias AgentAvatar = AgentSummary

/// The visitor-safe view of one of their conversations (history list, `conversation.update`).
public struct VisitorConversationDto: Codable, Sendable, Hashable {
    public var id: String
    public var status: ConversationStatus
    public var siteId: String
    public var seq: Int
    public var visitorUnread: Int
    public var lastMessageAt: Date?
    public var lastMessagePreview: String?
    public var lastMessageSenderType: SenderType?
    public var firstResponseAt: Date?
    public var resolvedAt: Date?
    public var subject: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    /// The human handling it, when assigned.
    public var agent: AgentSummary?
    /// The full wire payload.
    public var raw: JSONObject

    enum CodingKeys: String, CodingKey {
        case id, status, seq, subject, agent
        case siteId = "site_id"
        case visitorUnread = "visitor_unread"
        case lastMessageAt = "last_message_at"
        case lastMessagePreview = "last_message_preview"
        case lastMessageSenderType = "last_message_sender_type"
        case firstResponseAt = "first_response_at"
        case resolvedAt = "resolved_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String = "",
        status: ConversationStatus = .unknown,
        siteId: String = "",
        seq: Int = 0,
        visitorUnread: Int = 0,
        lastMessageAt: Date? = nil,
        lastMessagePreview: String? = nil,
        lastMessageSenderType: SenderType? = nil,
        firstResponseAt: Date? = nil,
        resolvedAt: Date? = nil,
        subject: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        agent: AgentSummary? = nil,
        raw: JSONObject = [:]
    ) {
        self.id = id
        self.status = status
        self.siteId = siteId
        self.seq = seq
        self.visitorUnread = visitorUnread
        self.lastMessageAt = lastMessageAt
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageSenderType = lastMessageSenderType
        self.firstResponseAt = firstResponseAt
        self.resolvedAt = resolvedAt
        self.subject = subject
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.agent = agent
        self.raw = raw
    }

    public init(json j: JSONObject) {
        typealias K = CodingKeys
        self.init(
            id: j.strOr(K.id.rawValue),
            status: ConversationStatus.parse(j.str(K.status.rawValue)),
            siteId: j.strOr(K.siteId.rawValue),
            seq: j.intOr(K.seq.rawValue),
            visitorUnread: j.intOr(K.visitorUnread.rawValue),
            lastMessageAt: j.date(K.lastMessageAt.rawValue),
            lastMessagePreview: j.str(K.lastMessagePreview.rawValue),
            lastMessageSenderType: j.str(K.lastMessageSenderType.rawValue).map(SenderType.parse),
            firstResponseAt: j.date(K.firstResponseAt.rawValue),
            resolvedAt: j.date(K.resolvedAt.rawValue),
            subject: j.str(K.subject.rawValue),
            createdAt: j.date(K.createdAt.rawValue),
            updatedAt: j.date(K.updatedAt.rawValue),
            agent: j.obj(K.agent.rawValue).map(AgentSummary.init(json:)),
            raw: j
        )
    }

    /// The wire shape (unknown fields from `raw` kept).
    public func toJSON() -> JSONObject {
        typealias K = CodingKeys
        let d: (Date?) -> JSONValue? = { $0.map { .string(formatISODate($0)) } }
        let fields = compact(
            (K.id.rawValue, id.json),
            (K.status.rawValue, status.code.json),
            (K.siteId.rawValue, siteId.json),
            (K.seq.rawValue, seq.json),
            (K.visitorUnread.rawValue, visitorUnread.json),
            (K.lastMessageAt.rawValue, d(lastMessageAt)),
            (K.lastMessagePreview.rawValue, lastMessagePreview.json),
            (K.lastMessageSenderType.rawValue, lastMessageSenderType?.code.json),
            (K.firstResponseAt.rawValue, d(firstResponseAt)),
            (K.resolvedAt.rawValue, d(resolvedAt)),
            (K.subject.rawValue, subject.json),
            (K.createdAt.rawValue, d(createdAt)),
            (K.updatedAt.rawValue, d(updatedAt)),
            (K.agent.rawValue, agent.map { .object($0.toJSON()) })
        )
        return raw.merging(fields) { _, new in new }
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

// MARK: - Site

/// How the launcher button looks: a preset icon or the site's own image, and an optional short label per
/// language that turns it into a pill.
public struct LauncherConfig: Codable, Sendable, Hashable {
    /// Preset icon.
    public var icon: LauncherIcon
    /// https image that replaces the icon.
    public var imageUrl: String?
    /// Label per locale; empty means icon only.
    public var label: [String: String]

    enum CodingKeys: String, CodingKey {
        case icon, label
        case imageUrl = "image_url"
    }

    public init(icon: LauncherIcon = .chat, imageUrl: String? = nil, label: [String: String] = [:]) {
        self.icon = icon
        self.imageUrl = imageUrl
        self.label = label
    }

    /// The label for `locale`, or nil for an icon-only button (no fallback to the other language).
    public func labelFor(_ locale: HatangLocale) -> String? {
        guard let l = label[locale.code]?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty else { return nil }
        return l
    }

    public init(json j: JSONObject) {
        self.init(
            icon: LauncherIcon.parse(j.str(CodingKeys.icon.rawValue)),
            imageUrl: j.str(CodingKeys.imageUrl.rawValue),
            label: j.stringMap(CodingKeys.label.rawValue)
        )
    }

    public func toJSON() -> JSONObject {
        compact(
            (CodingKeys.icon.rawValue, icon.code.json),
            (CodingKeys.imageUrl.rawValue, imageUrl.json),
            (CodingKeys.label.rawValue, .object(label.mapValues(JSONValue.string)))
        )
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

/// The chat header: a subtitle per language, the business logo, and whether it shows the business or the
/// online agents.
public struct HeaderConfig: Codable, Sendable, Hashable {
    /// Subtitle per locale; empty means none.
    public var subtitle: [String: String]
    /// https logo shown when `profile` is `business`.
    public var logoUrl: String?
    /// Business logo or agent faces.
    public var profile: HeaderProfile

    enum CodingKeys: String, CodingKey {
        case subtitle, profile
        case logoUrl = "logo_url"
    }

    public init(subtitle: [String: String] = [:], logoUrl: String? = nil, profile: HeaderProfile = .agents) {
        self.subtitle = subtitle
        self.logoUrl = logoUrl
        self.profile = profile
    }

    /// The subtitle for `locale`, or nil when empty (no fallback to the other language).
    public func subtitleFor(_ locale: HatangLocale) -> String? {
        guard let s = subtitle[locale.code]?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    public init(json j: JSONObject) {
        self.init(
            subtitle: j.stringMap(CodingKeys.subtitle.rawValue),
            logoUrl: j.str(CodingKeys.logoUrl.rawValue),
            profile: HeaderProfile.parse(j.str(CodingKeys.profile.rawValue))
        )
    }

    public func toJSON() -> JSONObject {
        compact(
            (CodingKeys.subtitle.rawValue, .object(subtitle.mapValues(JSONValue.string))),
            (CodingKeys.logoUrl.rawValue, logoUrl.json),
            (CodingKeys.profile.rawValue, profile.code.json)
        )
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

/// When the greeting shows and who signs it.
public struct GreetingOptions: Codable, Sendable, Hashable {
    /// Show the greeting at all.
    public var enabled: Bool
    /// Show it on phones (apps count as phones).
    public var onMobile: Bool
    /// Who signs it.
    public var sender: GreetingSender
    /// Web only: seconds before the greeting pops over the closed launcher (0 = never).
    public var teaserSeconds: Int

    enum CodingKeys: String, CodingKey {
        case enabled, sender
        case onMobile = "on_mobile"
        case teaserSeconds = "teaser_seconds"
    }

    public init(enabled: Bool = true, onMobile: Bool = true, sender: GreetingSender = .none, teaserSeconds: Int = 0) {
        self.enabled = enabled
        self.onMobile = onMobile
        self.sender = sender
        self.teaserSeconds = teaserSeconds
    }

    public init(json j: JSONObject) {
        typealias K = CodingKeys
        self.init(
            enabled: j.bool(K.enabled.rawValue) ?? true,
            onMobile: j.bool(K.onMobile.rawValue) ?? true,
            sender: GreetingSender.parse(j.str(K.sender.rawValue)),
            teaserSeconds: j.intOr(K.teaserSeconds.rawValue)
        )
    }

    public func toJSON() -> JSONObject {
        typealias K = CodingKeys
        return compact(
            (K.enabled.rawValue, enabled.json),
            (K.onMobile.rawValue, onMobile.json),
            (K.sender.rawValue, sender.code.json),
            (K.teaserSeconds.rawValue, teaserSeconds.json)
        )
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

/// A button under the header that leaves the chat for another channel (Zalo OA, Messenger page, phone,
/// email). The gateway resolves `url` to `https://zalo.me/…`, `https://m.me/…`, `tel:…` or `mailto:…`.
public struct ContactButton: Codable, Sendable, Hashable {
    /// Channel.
    public var kind: ContactKind
    /// Link to open.
    public var url: String
    /// Label (the Zalo OA or page name).
    public var label: String

    enum CodingKeys: String, CodingKey {
        case kind, url, label
    }

    public init(kind: ContactKind = .unknown, url: String = "", label: String = "") {
        self.kind = kind
        self.url = url
        self.label = label
    }

    /// A known kind with an `https:`, `tel:` or `mailto:` link; anything else is not shown.
    public var isOpenable: Bool {
        guard kind != .unknown else { return false }
        let u = url.lowercased()
        return u.hasPrefix("https:") || u.hasPrefix("tel:") || u.hasPrefix("mailto:")
    }

    public init(json j: JSONObject) {
        self.init(
            kind: ContactKind.parse(j.str(CodingKeys.kind.rawValue)),
            url: j.strOr(CodingKeys.url.rawValue),
            label: j.strOr(CodingKeys.label.rawValue)
        )
    }

    public func toJSON() -> JSONObject {
        compact(
            (CodingKeys.kind.rawValue, kind.code.json),
            (CodingKeys.url.rawValue, url.json),
            (CodingKeys.label.rawValue, label.json)
        )
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

/// Site settings the widget and SDK render from.
public struct SiteConfig: Codable, Sendable, Hashable {
    public var siteId: String
    /// Site (business) name shown in the header.
    public var name: String
    /// Accent colour as `#rrggbb`.
    public var color: String
    /// Launcher position on the web (`left` / `right`).
    public var position: String
    /// `vi`, `en` or `auto`.
    public var localeDefault: String
    /// Greeting per locale, shown when the conversation is empty.
    public var greeting: [String: String]
    /// Away message per locale, shown while nobody is online.
    public var awayMessage: [String: String]
    /// Pre-chat form policy.
    public var offlineCapture: OfflineCapture
    /// Hide the launcher while offline (web).
    public var hideWhenOffline: Bool
    /// Preferred colour scheme.
    public var theme: SiteTheme
    /// The AI assistant answers first.
    public var botEnabled: Bool
    /// Online team members for the header.
    public var agentAvatars: [AgentAvatar]
    /// How the launcher button looks.
    public var launcher: LauncherConfig
    /// Header subtitle, logo and profile; nil from older gateways.
    public var header: HeaderConfig?
    /// Greeting display; nil from older gateways (the greeting always shows).
    public var greetingOptions: GreetingOptions?
    /// Other ways to reach the business, in display order.
    public var contactButtons: [ContactButton]
    /// The full wire payload (campaigns, social proof, ...).
    public var raw: JSONObject

    enum CodingKeys: String, CodingKey {
        case name, color, position, greeting, theme, launcher, header
        case siteId = "site_id"
        case localeDefault = "locale_default"
        case awayMessage = "away_message"
        case offlineCapture = "offline_capture"
        case hideWhenOffline = "hide_when_offline"
        case botEnabled = "bot_enabled"
        case agentAvatars = "agent_avatars"
        case greetingOptions = "greeting_options"
        case contactButtons = "contact_buttons"
    }

    public init(
        siteId: String = "",
        name: String = "",
        color: String = "#0ea5e9",
        position: String = "right",
        localeDefault: String = "auto",
        greeting: [String: String] = [:],
        awayMessage: [String: String] = [:],
        offlineCapture: OfflineCapture = .off,
        hideWhenOffline: Bool = false,
        theme: SiteTheme = .auto,
        botEnabled: Bool = false,
        agentAvatars: [AgentAvatar] = [],
        launcher: LauncherConfig = LauncherConfig(),
        header: HeaderConfig? = nil,
        greetingOptions: GreetingOptions? = nil,
        contactButtons: [ContactButton] = [],
        raw: JSONObject = [:]
    ) {
        self.siteId = siteId
        self.name = name
        self.color = color
        self.position = position
        self.localeDefault = localeDefault
        self.greeting = greeting
        self.awayMessage = awayMessage
        self.offlineCapture = offlineCapture
        self.hideWhenOffline = hideWhenOffline
        self.theme = theme
        self.botEnabled = botEnabled
        self.agentAvatars = agentAvatars
        self.launcher = launcher
        self.header = header
        self.greetingOptions = greetingOptions
        self.contactButtons = contactButtons
        self.raw = raw
    }

    /// Greeting for `locale`, falling back to the other language.
    public func greetingFor(_ locale: HatangLocale) -> String? { SiteConfig.pick(greeting, locale) }

    /// Whether the greeting shows in an app (apps count as phones): always when the gateway sends no
    /// `greeting_options`, else only when it is enabled and on for phones.
    public var showsGreetingInApp: Bool {
        guard let g = greetingOptions else { return true }
        return g.enabled && g.onMobile
    }

    /// The name that signs the greeting: the first online agent's, when the site asks for it and the team is
    /// online; nil otherwise.
    public func greetingSigner(online: Bool) -> String? {
        guard greetingOptions?.sender == .onlineAgent, online,
              let name = agentAvatars.first?.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return name
    }

    /// Away message for `locale`, falling back to the other language.
    public func awayMessageFor(_ locale: HatangLocale) -> String? { SiteConfig.pick(awayMessage, locale) }

    private static func pick(_ m: [String: String], _ l: HatangLocale) -> String? {
        if let v = m[l.code], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v }
        for k in m.keys.sorted() {
            if let v = m[k], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v }
        }
        return nil
    }

    public init(json j: JSONObject) {
        typealias K = CodingKeys
        self.init(
            siteId: j.strOr(K.siteId.rawValue),
            name: j.strOr(K.name.rawValue),
            color: j.strOr(K.color.rawValue, "#0ea5e9"),
            position: j.strOr(K.position.rawValue, "right"),
            localeDefault: j.strOr(K.localeDefault.rawValue, "auto"),
            greeting: j.stringMap(K.greeting.rawValue),
            awayMessage: j.stringMap(K.awayMessage.rawValue),
            offlineCapture: OfflineCapture.parse(j.str(K.offlineCapture.rawValue)),
            hideWhenOffline: j.boolOr(K.hideWhenOffline.rawValue),
            theme: SiteTheme.parse(j.str(K.theme.rawValue)),
            botEnabled: j.boolOr(K.botEnabled.rawValue),
            agentAvatars: j.objList(K.agentAvatars.rawValue).map(AgentAvatar.init(json:)),
            launcher: j.obj(K.launcher.rawValue).map(LauncherConfig.init(json:)) ?? LauncherConfig(),
            header: j.obj(K.header.rawValue).map(HeaderConfig.init(json:)),
            greetingOptions: j.obj(K.greetingOptions.rawValue).map(GreetingOptions.init(json:)),
            contactButtons: j.objList(K.contactButtons.rawValue).map(ContactButton.init(json:)),
            raw: j
        )
    }

    /// The wire shape (unknown fields from `raw` kept).
    public func toJSON() -> JSONObject {
        typealias K = CodingKeys
        let fields = compact(
            (K.siteId.rawValue, siteId.json),
            (K.name.rawValue, name.json),
            (K.color.rawValue, color.json),
            (K.position.rawValue, position.json),
            (K.localeDefault.rawValue, localeDefault.json),
            (K.greeting.rawValue, .object(greeting.mapValues(JSONValue.string))),
            (K.awayMessage.rawValue, .object(awayMessage.mapValues(JSONValue.string))),
            (K.offlineCapture.rawValue, offlineCapture.code.json),
            (K.hideWhenOffline.rawValue, hideWhenOffline.json),
            (K.theme.rawValue, theme.code.json),
            (K.botEnabled.rawValue, botEnabled.json),
            (K.agentAvatars.rawValue, .array(agentAvatars.map { .object($0.toJSON()) })),
            (K.launcher.rawValue, .object(launcher.toJSON())),
            (K.header.rawValue, header.map { .object($0.toJSON()) }),
            (K.greetingOptions.rawValue, greetingOptions.map { .object($0.toJSON()) }),
            (K.contactButtons.rawValue, contactButtons.isEmpty ? nil : .array(contactButtons.map { .object($0.toJSON()) }))
        )
        return raw.merging(fields) { _, new in new }
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

/// Whether the team can answer right now.
public struct Availability: Codable, Sendable, Hashable {
    /// Someone (or the bot) can reply now.
    public var online: Bool
    /// Inside office hours.
    public var withinHours: Bool
    /// When office hours next start.
    public var nextOpenAt: Date?
    /// Number of agents online.
    public var agentsOnline: Int

    enum CodingKeys: String, CodingKey {
        case online
        case withinHours = "within_hours"
        case nextOpenAt = "next_open_at"
        case agentsOnline = "agents_online"
    }

    public init(online: Bool = false, withinHours: Bool = true, nextOpenAt: Date? = nil, agentsOnline: Int = 0) {
        self.online = online
        self.withinHours = withinHours
        self.nextOpenAt = nextOpenAt
        self.agentsOnline = agentsOnline
    }

    /// Nobody is online yet (before bootstrap).
    public static let offline = Availability(online: false)

    public init(json j: JSONObject) {
        typealias K = CodingKeys
        self.init(
            online: j.boolOr(K.online.rawValue),
            withinHours: j.bool(K.withinHours.rawValue) ?? true,
            nextOpenAt: j.date(K.nextOpenAt.rawValue),
            agentsOnline: j.intOr(K.agentsOnline.rawValue)
        )
    }

    public func toJSON() -> JSONObject {
        typealias K = CodingKeys
        return compact(
            (K.online.rawValue, online.json),
            (K.withinHours.rawValue, withinHours.json),
            (K.nextOpenAt.rawValue, nextOpenAt.map { .string(formatISODate($0)) }),
            (K.agentsOnline.rawValue, agentsOnline.json)
        )
    }

    public init(from decoder: any Decoder) throws { self.init(json: try decodeObject(decoder)) }
    public func encode(to encoder: any Encoder) throws { try encodeObject(toJSON(), encoder) }
}

/// The name hosts see for `Availability`.
public typealias HatangAvailability = Availability

// MARK: - Client payloads

/// The screen the app shows (the native counterpart of a page).
public struct ScreenInfo: Sendable, Hashable {
    /// Screen name (route), at most 200 characters on the wire.
    public var name: String
    /// Small string parameters (ids, tabs).
    public var params: [String: String]?

    public init(name: String, params: [String: String]? = nil) {
        self.name = name
        self.params = params
    }

    /// The wire shape.
    public func toJSON() -> JSONObject {
        let p = params.flatMap { $0.isEmpty ? nil : JSONValue.object($0.mapValues(JSONValue.string)) }
        return compact(("name", String(name.prefix(200)).json), ("params", p))
    }
}

/// Install and build details sent on bootstrap and auth.
public struct AppContext: Sendable, Hashable {
    /// Stable per-install id (8..128 chars).
    public var installId: String
    /// Host app version.
    public var version: String?
    /// SDK name and version, e.g. `ios/0.1.0`.
    public var sdk: String?
    /// `ios`, `android`, `web`, `macos`, `windows`, `linux`, `other`.
    public var os: String?
    /// OS version.
    public var osVersion: String?
    /// Device model.
    public var deviceModel: String?
    /// Device locale.
    public var locale: String?

    public init(
        installId: String,
        version: String? = nil,
        sdk: String? = nil,
        os: String? = nil,
        osVersion: String? = nil,
        deviceModel: String? = nil,
        locale: String? = nil
    ) {
        self.installId = installId
        self.version = version
        self.sdk = sdk
        self.os = os
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.locale = locale
    }

    /// The wire shape.
    public func toJSON() -> JSONObject {
        compact(
            ("install_id", installId.json),
            ("version", version.json),
            ("sdk", sdk.json),
            ("os", os.json),
            ("os_version", osVersion.json),
            ("device_model", deviceModel.json),
            ("locale", locale.json)
        )
    }
}

/// The SDK identifying itself on the socket.
public struct ClientInfo: Sendable, Hashable {
    /// `ios`.
    public var sdk: String
    /// SDK version.
    public var version: String

    public init(sdk: String, version: String) {
        self.sdk = sdk
        self.version = version
    }

    /// The wire shape.
    public func toJSON() -> JSONObject {
        compact(("sdk", sdk.json), ("version", version.json))
    }
}

/// What `POST /bootstrap` returns.
public struct BootstrapResponse: Sendable, Hashable {
    /// The visitor token to keep and send on every call.
    public var visitorToken: String
    /// The visitor.
    public var visitor: VisitorDto
    /// Site settings.
    public var config: SiteConfig
    /// Team availability.
    public var availability: Availability
    /// The last messages of the active conversation, oldest first.
    public var timeline: [TimelineItem]
    /// Socket URL (query already carries site, app and install).
    public var wsUrl: String
    /// The active conversation, if any.
    public var conversation: ConversationSummary?
    /// Protocol version the gateway speaks.
    public var protocolVersion: Int
    /// Older items exist before `timeline`; nil from gateways that do not say.
    public var timelineHasMore: Bool?
    /// The site app id the key resolved to.
    public var appId: String?
    /// The site app platform.
    public var appPlatform: String?

    /// Parses the wire shape.
    public init(json j: JSONObject) {
        let app = j.obj("app")
        visitorToken = j.strOr("visitor_token")
        visitor = VisitorDto(json: j.obj("visitor") ?? [:])
        config = SiteConfig(json: j.obj("config") ?? [:])
        availability = j.obj("availability").map(Availability.init(json:)) ?? .offline
        conversation = j.obj("conversation").map(ConversationSummary.init(json:))
        timeline = TimelineItem.list(j["timeline"])
        timelineHasMore = j.bool("timeline_has_more")
        wsUrl = j.strOr("ws_url")
        protocolVersion = j.intOr("protocol_version", 1)
        appId = app?.str("id")
        appPlatform = app?.str("platform")
    }
}
