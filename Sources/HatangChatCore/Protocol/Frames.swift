import Foundation

/// A frame the SDK sends: `{t, d, id?, v: 1}`.
public struct ClientFrame: Sendable, Hashable {
    /// Frame type.
    public var t: String
    /// Payload.
    public var d: JSONObject?

    public init(_ t: String, _ d: JSONObject? = nil) {
        self.t = t
        self.d = d
    }

    /// The wire shape with the protocol version and an optional request `id`.
    public func toJSON(id: String? = nil, version: Int = protocolVersion) -> JSONObject {
        compact(("t", t.json), ("d", d.map(JSONValue.object)), ("id", id.json), ("v", version.json))
    }

    /// First frame on every connection; must arrive within 5 s.
    public static func auth(
        token: String,
        siteId: String,
        screen: ScreenInfo? = nil,
        app: AppContext? = nil,
        client: ClientInfo? = nil,
        locale: String? = nil,
        foreground: Bool? = nil
    ) -> ClientFrame {
        ClientFrame("auth", compact(
            ("token", token.json),
            ("site_id", siteId.json),
            ("screen", screen.map { .object($0.toJSON()) }),
            ("app", app.map { .object($0.toJSON()) }),
            ("client", client.map { .object($0.toJSON()) }),
            ("locale", locale.json),
            ("app_state", foreground.map { .object(["foreground": .bool($0)]) })
        ))
    }

    /// The app moved to another screen.
    public static func screen(_ screen: ScreenInfo) -> ClientFrame {
        ClientFrame("screen", screen.toJSON())
    }

    /// Foreground/background and the thread on screen (`conversation_id` is sent even when nil).
    public static func appState(foreground: Bool, conversationId: String? = nil) -> ClientFrame {
        ClientFrame("app.state", ["foreground": .bool(foreground), "conversation_id": conversationId.json ?? .null])
    }

    /// Send a message; the reply is `message.ack` (the echo comes separately).
    public static func send(clientId: String, content: String, conversationId: String? = nil, attachments: [String]? = nil) -> ClientFrame {
        let a = attachments.flatMap { $0.isEmpty ? nil : JSONValue.array($0.map(JSONValue.string)) }
        return ClientFrame("message.send", compact(
            ("conversation_id", conversationId.json),
            ("client_id", clientId.json),
            ("content", content.json),
            ("attachments", a)
        ))
    }

    /// Typing indicator.
    public static func typing(conversationId: String, on: Bool) -> ClientFrame {
        ClientFrame("typing", compact(("conversation_id", conversationId.json), ("on", on.json)))
    }

    /// Read receipt up to `upToSeq`.
    public static func read(conversationId: String, upToSeq: Int) -> ClientFrame {
        ClientFrame("read", compact(("conversation_id", conversationId.json), ("up_to_seq", upToSeq.json)))
    }

    /// Attach an identity or custom data to the visitor.
    public static func identify(
        userId: String? = nil,
        email: String? = nil,
        name: String? = nil,
        phone: String? = nil,
        hash: String? = nil,
        data: JSONObject? = nil
    ) -> ClientFrame {
        ClientFrame("identify", compact(
            ("user_id", userId.json),
            ("email", email.json),
            ("name", name.json),
            ("phone", phone.json),
            ("hash", hash.json),
            ("data", data.map(JSONValue.object))
        ))
    }

    /// A custom event (recorded on the active conversation).
    public static func event(name: String, data: JSONObject? = nil) -> ClientFrame {
        ClientFrame("event", compact(("name", name.json), ("data", .object(data ?? [:]))))
    }

    /// Ask for items after `afterSeq` of one of the visitor's conversations.
    public static func resume(conversationId: String, afterSeq: Int) -> ClientFrame {
        ClientFrame("resume", compact(("conversation_id", conversationId.json), ("after_seq", afterSeq.json)))
    }

    /// Rate a resolved conversation.
    public static func rate(conversationId: String, score: Int, comment: String? = nil) -> ClientFrame {
        let c = comment.flatMap { $0.isEmpty ? nil : JSONValue.string($0) }
        return ClientFrame("rate", compact(("conversation_id", conversationId.json), ("score", score.json), ("comment", c)))
    }

    /// Keep-alive; the server replies `pong`.
    public static func ping() -> ClientFrame {
        ClientFrame("ping")
    }
}

/// A frame the gateway sends. Unknown types decode to `.unknown` and are ignored.
public enum ServerFrame: Sendable, Hashable {
    case ready(ReadyFrame)
    case message(MessageFrame)
    case messageAck(MessageAckFrame)
    case event(EventFrame)
    case typing(TypingFrame)
    case availability(AvailabilityFrame)
    case read(ReadFrame)
    case resume(ResumeFrame)
    case conversationStart(ConversationStartFrame)
    case conversationUpsert(ConversationUpsertFrame)
    case conversationUpdate(ConversationUpdateFrame)
    case session(SessionFrame)
    case reload(ReloadFrame)
    case error(ErrorFrame)
    case pong(PongFrame)
    case unknown(UnknownFrame)

    /// Frame type.
    public var t: String {
        switch self {
        case .ready: return "ready"
        case .message: return "message"
        case .messageAck: return "message.ack"
        case .event: return "event"
        case .typing: return "typing"
        case .availability: return "availability"
        case .read: return "read"
        case .resume: return "resume"
        case .conversationStart: return "conversation.start"
        case .conversationUpsert: return "conversation.upsert"
        case .conversationUpdate: return "conversation.update"
        case .session: return "session"
        case .reload: return "reload"
        case .error: return "error"
        case .pong: return "pong"
        case .unknown(let f): return f.t
        }
    }

    /// Echo of the request id this frame answers.
    public var id: String? {
        switch self {
        case .ready(let f): return f.id
        case .message(let f): return f.id
        case .messageAck(let f): return f.id
        case .event(let f): return f.id
        case .typing(let f): return f.id
        case .availability(let f): return f.id
        case .read(let f): return f.id
        case .resume(let f): return f.id
        case .conversationStart(let f): return f.id
        case .conversationUpsert(let f): return f.id
        case .conversationUpdate(let f): return f.id
        case .session(let f): return f.id
        case .reload(let f): return f.id
        case .error(let f): return f.id
        case .pong(let f): return f.id
        case .unknown(let f): return f.id
        }
    }

    /// Parses the wire shape; unknown types (and the agent-side `ready`) become `.unknown`.
    public init(json j: JSONObject) {
        let t = j.str("t") ?? ""
        let id = j.str("id")
        let raw = j["d"]
        let d = raw?.objectValue ?? [:]
        switch t {
        case "ready":
            // The agent-side `ready` has no availability; treat it as unknown.
            guard d["availability"] != nil else {
                self = .unknown(UnknownFrame(t: t, d: raw, id: id))
                return
            }
            self = .ready(ReadyFrame(
                visitor: VisitorDto(json: d.obj("visitor") ?? [:]),
                timeline: TimelineItem.list(d["timeline"]),
                availability: d.obj("availability").map(Availability.init(json:)) ?? .offline,
                conversation: d.obj("conversation").map(ConversationSummary.init(json:)),
                timelineHasMore: d.bool("timeline_has_more"),
                id: id
            ))
        case "message":
            self = .message(MessageFrame(message: MessageDto(json: d), id: id))
        case "message.ack":
            self = .messageAck(MessageAckFrame(
                clientId: d.strOr("client_id"),
                messageId: d.strOr("id"),
                seq: d.intOr("seq"),
                conversationId: d.strOr("conversation_id"),
                id: id
            ))
        case "event":
            self = .event(EventFrame(event: ConversationEventDto(json: d), id: id))
        case "typing":
            self = .typing(TypingFrame(
                conversationId: d.strOr("conversation_id"),
                side: d.strOr("side", "agent"),
                on: d.boolOr("on"),
                name: d.str("name"),
                id: id
            ))
        case "availability":
            self = .availability(AvailabilityFrame(availability: Availability(json: d), id: id))
        case "read":
            self = .read(ReadFrame(conversationId: d.strOr("conversation_id"), side: d.strOr("side", "agent"), upToSeq: d.intOr("up_to_seq"), id: id))
        case "resume":
            self = .resume(ResumeFrame(
                conversationId: d.strOr("conversation_id"),
                items: TimelineItem.list(d["items"]),
                hasMore: d.boolOr("has_more"),
                id: id
            ))
        case "conversation.start":
            self = .conversationStart(ConversationStartFrame(
                conversation: ConversationSummary(json: d.obj("conversation") ?? [:]),
                open: d.boolOr("open"),
                id: id
            ))
        case "conversation.upsert":
            self = .conversationUpsert(ConversationUpsertFrame(conversation: ConversationSummary(json: d), id: id))
        case "conversation.update":
            self = .conversationUpdate(ConversationUpdateFrame(conversation: VisitorConversationDto(json: d), id: id))
        case "session":
            self = .session(SessionFrame(visitorToken: d.strOr("visitor_token"), visitorId: d.strOr("visitor_id"), reason: d.strOr("reason"), id: id))
        case "reload":
            self = .reload(ReloadFrame(reason: d.strOr("reason"), id: id))
        case "error":
            self = .error(ErrorFrame(code: d.strOr("code", "error"), message: d.strOr("message"), forId: d.str("for"), id: id))
        case "pong":
            self = .pong(PongFrame(now: d.date("now"), id: id))
        default:
            self = .unknown(UnknownFrame(t: t, d: raw, id: id))
        }
    }
}

/// Auth succeeded: the visitor, the active conversation and its tail.
public struct ReadyFrame: Sendable, Hashable {
    public var visitor: VisitorDto
    /// Last items of the active conversation, oldest first.
    public var timeline: [TimelineItem]
    public var availability: Availability
    public var conversation: ConversationSummary?
    /// Older items exist before `timeline`; nil from gateways that do not say.
    public var timelineHasMore: Bool?
    public var id: String?

    public init(visitor: VisitorDto, timeline: [TimelineItem], availability: Availability, conversation: ConversationSummary? = nil, timelineHasMore: Bool? = nil, id: String? = nil) {
        self.visitor = visitor
        self.timeline = timeline
        self.availability = availability
        self.conversation = conversation
        self.timelineHasMore = timelineHasMore
        self.id = id
    }
}

/// A message in one of the visitor's conversations.
public struct MessageFrame: Sendable, Hashable {
    public var message: MessageDto
    public var id: String?
}

/// Reply to `message.send`.
public struct MessageAckFrame: Sendable, Hashable {
    /// The client id that was sent.
    public var clientId: String
    /// The stored message id.
    public var messageId: String
    /// The stored sequence number.
    public var seq: Int
    /// The conversation the message landed in (new when none was active).
    public var conversationId: String
    public var id: String?
}

/// A conversation event visible to visitors.
public struct EventFrame: Sendable, Hashable {
    public var event: ConversationEventDto
    public var id: String?
}

/// Someone is typing.
public struct TypingFrame: Sendable, Hashable {
    public var conversationId: String
    /// `agent` or `visitor`.
    public var side: String
    public var on: Bool
    /// The agent's name.
    public var name: String?
    public var id: String?
}

/// Team availability changed.
public struct AvailabilityFrame: Sendable, Hashable {
    public var availability: Availability
    public var id: String?
}

/// The other side read up to a sequence number.
public struct ReadFrame: Sendable, Hashable {
    public var conversationId: String
    /// Who read: `agent` or `visitor`.
    public var side: String
    /// Read up to and including this seq.
    public var upToSeq: Int
    public var id: String?
}

/// Reply to `resume`.
public struct ResumeFrame: Sendable, Hashable {
    public var conversationId: String
    /// Items after the requested seq, oldest first.
    public var items: [TimelineItem]
    /// More items follow the last one returned.
    public var hasMore: Bool
    public var id: String?
}

/// The team started a conversation with the visitor.
public struct ConversationStartFrame: Sendable, Hashable {
    public var conversation: ConversationSummary
    /// The UI should open.
    public var open: Bool
    public var id: String?
}

/// A conversation summary changed (team-side shape; tolerated).
public struct ConversationUpsertFrame: Sendable, Hashable {
    public var conversation: ConversationSummary
    public var id: String?
}

/// One of the visitor's conversations changed status or handler.
public struct ConversationUpdateFrame: Sendable, Hashable {
    public var conversation: VisitorConversationDto
    public var id: String?
}

/// The session moved to another visitor record; store the token and start over.
public struct SessionFrame: Sendable, Hashable {
    public var visitorToken: String
    /// The surviving visitor id.
    public var visitorId: String
    /// `identity_merged` or `reset`.
    public var reason: String
    public var id: String?
}

/// The gateway asks the client to start over.
public struct ReloadFrame: Sendable, Hashable {
    public var reason: String
    public var id: String?
}

/// A request failed (with the request id) or an unsolicited error.
public struct ErrorFrame: Sendable, Hashable {
    public var code: String
    public var message: String
    /// The request this error is for (older gateways).
    public var forId: String?
    public var id: String?
}

/// Reply to `ping`.
public struct PongFrame: Sendable, Hashable {
    /// Server time.
    public var now: Date?
    public var id: String?
}

/// A frame type this SDK does not know; ignored for forward compatibility.
public struct UnknownFrame: Sendable, Hashable {
    public var t: String
    /// Raw payload.
    public var d: JSONValue?
    public var id: String?
}
