import Foundation

/// Kinds of conversion the SDK reports.
public enum HatangConversionKind: Sendable, Hashable {
    /// The visitor sent their first message.
    case chatStarted
    /// A lead form was submitted.
    case lead
    /// An order was paid.
    case purchase
}

/// A conversion the host may forward to its analytics.
public struct HatangConversion: Sendable, Hashable {
    public var kind: HatangConversionKind
    /// Extra data (`value`, `currency`, `transaction_id` for purchases).
    public var data: JSONObject

    public init(kind: HatangConversionKind, data: JSONObject = [:]) {
        self.kind = kind
        self.data = data
    }
}

/// Why the session changed.
public enum HatangSessionChangeReason: Sendable, Hashable {
    /// `identify` merged this visitor into an earlier one.
    case identityMerged
    /// `reset()` created a fresh visitor.
    case reset
    /// A magic link restored another device's session.
    case restored
    /// The gateway refused the stored token; a fresh visitor was created.
    case tokenRejected
}

/// Something a host app may react to (`ChatEngine.events()`).
public enum HatangEvent: Sendable, Hashable {
    /// Bootstrapped and authenticated; the conversation (if any) is loaded.
    case ready(visitorId: String, conversationId: String?)
    /// The chat screen was shown (emitted by the UI layer).
    case opened
    /// The chat screen was dismissed (emitted by the UI layer).
    case closed
    /// A message from the team, bot or system arrived.
    case messageReceived(MessageDto)
    /// A message from this visitor was stored (echo, possibly from another device).
    case messageSent(MessageDto)
    /// The conversation's status changed.
    case conversationStatus(conversationId: String, status: ConversationStatus)
    /// A conversion the host may forward to its analytics.
    case conversion(HatangConversion)
    /// The visitor identity behind this session changed.
    case sessionChanged(visitorId: String, reason: HatangSessionChangeReason)
    /// The gateway no longer speaks this SDK's protocol version; ship an update.
    case protocolOutdated(reason: String)
}
