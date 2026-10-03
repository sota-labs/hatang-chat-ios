import Foundation

/// Where the engine is in its life.
public enum ChatPhase: Sendable, Hashable {
    /// Not started.
    case idle
    /// Bootstrapping over REST.
    case bootstrapping
    /// Bootstrapped; the socket may or may not be connected.
    case ready
    /// Bootstrap failed for good (bad app key, disabled site).
    case failed
    /// The gateway rejected this protocol version.
    case outdated
}

/// Socket connection state as exposed to hosts.
public enum HatangConnectionState: Sendable, Hashable {
    /// No socket.
    case disconnected
    /// Bootstrapping or (re)connecting.
    case connecting
    /// Authenticated and live.
    case connected
    /// Stopped: the gateway wants a newer SDK.
    case outdated
}

/// A read-only view of the session for hosts.
public struct HatangSession: Sendable, Hashable {
    /// Locale in use.
    public var locale: HatangLocale
    /// Visitor id (after bootstrap).
    public var visitorId: String?
    /// Active conversation id.
    public var conversationId: String?
    /// `identify` attached an identity.
    public var isIdentified: Bool
    /// Known email.
    public var email: String?
    /// Known name.
    public var name: String?
}

/// Immutable snapshot of everything the UI renders (`ChatEngine.states()`).
public struct ChatState: Sendable, Hashable {
    /// Life-cycle phase.
    public var phase: ChatPhase = .idle
    /// Socket state.
    public var connection: HatangConnectionState = .disconnected
    /// Site settings (after bootstrap).
    public var config: SiteConfig?
    /// The visitor (after bootstrap).
    public var visitor: VisitorDto?
    /// The active conversation.
    public var conversation: ConversationSummary?
    /// Loaded items.
    public var timeline: Timeline = .empty
    /// Outgoing messages without an ack.
    public var pending: [PendingMessage] = []
    /// Name of the agent typing (empty string when unnamed); nil when nobody is.
    public var typingAgent: String?
    /// Team availability.
    public var availability: Availability = .offline
    /// Messages received while the screen was not visible.
    public var unread: Int = 0
    /// Locale in use.
    public var locale: HatangLocale = .vi
    /// Show the pre-chat (offline) form before sending.
    public var needsEmail: Bool = false
    /// The visitor skipped the optional email form this session.
    public var skippedEmail: Bool = false
    /// Score the visitor gave (from a `rated` event or `rate`).
    public var rated: Int?
    /// Last error worth a banner (cleared by the UI).
    public var transientError: HatangError?
    /// Why the gateway wants a newer SDK.
    public var outdatedReason: String?
    /// Email known for the visitor (from bootstrap, identify or forms).
    public var visitorEmail: String?
    /// Name known for the visitor.
    public var visitorName: String?
    /// An earlier page is loading.
    public var loadingEarlier: Bool = false
    /// The conversation is on screen.
    public var visible: Bool = false
    /// The app is in the foreground.
    public var foreground: Bool = true
    /// Text held back by the pre-chat form; sent once it is answered.
    public var draft: String?

    public init() {}

    /// `visible && foreground`: incoming messages count as read.
    public var canRead: Bool { visible && foreground }

    /// The site is online (someone or the bot can reply).
    public var online: Bool { availability.online }

    /// Host-facing session view.
    public var session: HatangSession {
        HatangSession(
            locale: locale,
            visitorId: visitor?.id,
            conversationId: conversation?.id,
            isIdentified: visitor?.isIdentified ?? false,
            email: visitorEmail ?? visitor?.email,
            name: visitorName ?? visitor?.name
        )
    }
}
